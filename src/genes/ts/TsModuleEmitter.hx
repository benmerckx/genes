package genes.ts;

import genes.SourceMapGenerator.SourcePosition;
import genes.Dependencies;
import genes.CompilerDiagnostic;
import genes.CompilerInternal;
import genes.ExplicitTypeArguments;
import genes.ExplicitTypeArguments.ExplicitTypeArgument;
import genes.Module;
import genes.TypeAccessor;
import genes.Module.Field as GenesField;
import genes.Module.FieldKind;
import genes.es.ModuleEmitter as JsModuleEmitter;
import genes.dts.TypeEmitter;
import genes.util.Timer.timer;
import genes.util.TypeUtil;
import genes.PublicSurface;
import genes.PublicSurface.PublicMember;
import genes.NullishContract;
import genes.DependencyPlan.DependencyModuleRequest;
import genes.NullishContract.NullishMissingValue;
import genes.NamePlan.NamePlanProfile;
import genes.TempPlan.LoweredForIterator;
import genes.JsxPlan;
import genes.JsxPlan.JsxCapabilityPolicy;
import genes.JsxPlan.JsxIntent;
import genes.JsxPlan.JsxChildIntent;
import genes.JsxPlan.JsxPropIntent;
import genes.JsxPlan.JsxTagIntent;
import genes.JsxPlan.JsxValueSource;
import genes.TemplateLiteralPlan.TemplateLiteralIntent;
import genes.JsonTypeSupport;
import genes.ModuleFunctionPlan.ModuleFunctionEntry;
import genes.CallableSignaturePlan;
import haxe.ds.Option;
import haxe.macro.Expr;
import haxe.macro.Type;
import genes.util.IteratorUtil.*;

using genes.util.TypeUtil;
using Lambda;
using haxe.macro.Tools;

typedef PrivateMethodCall = {
  final owner: ClassType;
  final field: ClassField;
  final receiver: Null<TypedExpr>;
}

/**
 * Minimal TS module emitter (M1):
 * - Emits `.ts` modules with ESM imports/exports
 * - Emits `export class` declarations (not `export const Foo = class Foo`)
 * - Adds enough type annotations for `tsc --noEmit` under `strict`
 *
 * This is intentionally incomplete. Expression coverage and richer typing land in later milestones.
 */
class TsModuleEmitter extends JsModuleEmitter {
  var emitTsMemberSourcePositions = true;

  /**
   * Applies the shared compiler-internal provenance projection in TS mode.
   *
   * Why: the TS enum printer emits several merged type/value declarations, so
   * suppressing only the first token would still map invented constructors and
   * runtime assignments back to user source. What/How: the member loop scopes
   * this flag around the complete top-level type, and the inherited emitter
   * keeps mapping every neighboring ordinary member as before.
   */
  override public function emitPos(pos: SourcePosition) {
    if (emitTsMemberSourcePositions)
      super.emitPos(pos);
  }

  var jsxEmitTsx: Bool = false;
  var inAssignTarget: Bool = false;
  var currentClass: Null<ClassType> = null;
  var currentReturnIsVoidLike: Bool = false;
  var localTsTypeOverrides: Map<Int, String> = [];
  var narrowingPlan: Null<TsNarrowingPlan> = null;
  var boundaryPlan: Null<TsBoundaryPlan> = null;
  var currentCallableSignature: Null<CallableSignaturePlan> = null;
  var inRawSyntaxTemplate: Bool = false;
  var suppressOptionalFieldNullNormalization: Bool = false;
  var suppressPromiseResolveNullThenableCast: Bool = false;

  /**
   * Type witnesses scoped to the value inside one compiler-owned carrier call.
   *
   * The carrier stores the checked Haxe types on the exact typed-AST occurrence,
   * so nested macro output cannot borrow facts through equal source positions or
   * stale process state. The previous scope is restored after the carried value,
   * and neither the carrier nor these witnesses reaches generated output.
   */
  var currentExplicitTypeArguments: Null<Array<ExplicitTypeArgument>> = null;

  function typeEmitsAny(t: Type): Bool {
    final fast = switch t {
      case TDynamic(null):
        true;
      case TInst(_.get() => cl, _)
        if (cl.module != null && cl.module.startsWith('haxe.macro')):
        true;
      case TType(_.get() => dt, _)
        if (dt.module != null && dt.module.startsWith('haxe.macro')):
        true;
      default:
        false;
    };
    if (fast)
      return true;

    final out = new StringBuf();
    final noop = function() {}
    final writer: genes.dts.TypeEmitter.TypeWriter = {
      write: out.add,
      writeNewline: noop,
      emitComment: function(_comment: String) {},
      increaseIndent: noop,
      decreaseIndent: noop,
      emitPos: function(_pos) {},
      includeType: function(_type: Type) {},
      typeAccessor: ctx.typeAccessor,
      typeParameterName: parameter -> parameter.name
    };
    TypeEmitter.emitType(writer, t);
    return out.toString() == 'any';
  }

  /**
   * Whether one authored null literal already matches an exact TS projection.
   *
   * This is intentionally narrower than general union parsing. It only removes
   * a compiler-inserted assertion when the actual expression is literally
   * `null` and the expected Haxe boundary prints as exactly `null`. Nullable
   * locals flowing to ordinary non-null parameters retain their existing
   * strict-TypeScript safeguard. The shared literal check unwraps only inert
   * compile-time wrappers; a checked `cast(value, Type)` remains executable.
   */
  function acceptsExactProjectedNull(expected: Type, actual: TypedExpr): Bool {
    return TypeUtil.isNullConstant(actual)
      && explicitTypeProjection(expected) == 'null';
  }

  /**
   * Reads an explicit host projection without invoking the type printer.
   *
   * Why: expression emission runs after dependency planning, so probing a
   * general imported type through `TypeEmitter` can request an unplanned
   * accessor. What: only metadata owned by the expected nominal type is
   * relevant to the exact-null exception. How: inspect instance/abstract
   * metadata directly and unwrap only compiler-lazy shells; typedefs remain
   * their own named TypeScript boundary rather than borrowing an underlying
   * projection.
   */
  static function explicitTypeProjection(type: Type): Null<String> {
    return switch type {
      case TInst(_.get().meta => meta, _) | TAbstract(_.get().meta => meta, _):
        extractStringMeta(meta,
          ':ts.type') ?? extractStringMeta(meta, ':genes.type');
      case TLazy(resolve):
        explicitTypeProjection(resolve());
      case TMono(reference) if (reference.get() != null):
        explicitTypeProjection(reference.get());
      default:
        null;
    }
  }

  /**
   * Decides whether a raw JavaScript `undefined` literal should become `null`.
   *
   * Why: ordinary Haxe nullable values use `null`, while JavaScript host APIs
   * often use `undefined`. genes-ts normally normalizes raw
   * `js.Syntax.code("undefined")` into `null` when the surrounding Haxe type is
   * nullable, preserving Haxe runtime expectations under TS strict null checks.
   *
   * What/How: `genes.ts.Undefinable<T>` and `genes.ts.Unknown` are explicit
   * boundary contracts where `undefined` is semantically meaningful. For those
   * types, and for expected/return contexts of those types, keep the real
   * JavaScript `undefined` value instead of collapsing it to Haxe `null`.
   */
  function shouldNormalizeUndefinedToNull(t: Type): Bool {
    final value = NullishContract.forType(t);
    final expectedPreserves = currentExpectedValueType != null
      && NullishContract.forType(currentExpectedValueType).preservesUndefined;
    final returnPreserves = currentReturnType != null
      && NullishContract.forType(currentReturnType).preservesUndefined;
    return !isVoidLike(t)
      && value.shouldNormalizeRawUndefinedToNull()
      && !expectedPreserves && !returnPreserves;
  }

  function shouldNormalizeOptionalFieldRead(e: TypedExpr): Bool {
    final expected = currentExpectedValueType;
    final field = nullishFieldContract(e);
    return field != null
      && field.normalizeUndefinedReadToNull
      && expected != null
      && NullishContract.forType(expected).haxeAllowsNull
      && !NullishContract.forType(expected).preservesUndefined
      && !isNarrowedOptionalField(e);
  }

  function nativeMapReadNeedsAssertion(e: TypedExpr): Bool {
    final expected = currentExpectedValueType;
    if (expected == null)
      return false;
    final mapRead = NullishContract.forNativeMapRead(e.t);
    final destination = NullishContract.forType(expected);
    return mapRead.missingValue == MissingAsNull
      && !destination.haxeAllowsNull && !destination.preservesUndefined;
  }

  public function emitTsModule(module: Module, importExtension: Null<String>) {
    final endTimer = timer('emitTsModule');
    moduleFunctionPlan = module.moduleFunctionPlan;
    jsxEmitTsx = genes.Genes.outExtension == '.tsx';
    configureLowering(module, TypeScriptReadable, jsxEmitTsx);
    configureTemplateLiterals(module.templateLiteralPlan);
    narrowingPlan = module.tsNarrowingPlan;
    boundaryPlan = module.tsBoundaryPlan;
    final jsxPlan = module.jsxPlan;
    final jsxCapability = JsxCapabilityPolicy.current();
    final needsJsxNamespaceImport = jsxPlan.hasIntents
      || module.dependencyPlan.usesJsxNamespaceType;

    // Runtime and type-only bindings share one collision-safe allocator, while
    // only the ordered runtime request array controls ESM evaluation order.
    final projection = module.implementationProjection;
    final deps = projection.bindings;
    ctx.typeAccessor = deps.typeAccessor;
    configureJsx(jsxPlan, jsxCapability, deps);

    emitDirectivePrologue(module);
    if (haxe.macro.Context.defined('genes.banner')) {
      write(haxe.macro.Context.definedValue('genes.banner'));
      writeNewline();
    }

    // Some JSX runtimes expose `JSX` as a module export instead of a global
    // namespace. This optional type import keeps `JSX.Element` annotations
    // resolvable in both `.ts` and `.tsx` output without forcing a runtime
    // binding. A module can need the type even when it contains no markup, so
    // the typed dependency plan contributes independently from `JsxPlan`.
    final jsxImportSource = haxe.macro.Context.definedValue('genes.ts.jsx_import_source');
    if (needsJsxNamespaceImport && jsxImportSource != null
      && jsxImportSource.length > 0) {
      write('import type {JSX} from ');
      emitString(jsxImportSource);
      writeNewline();
    }

    final endImportTimer = timer('emitImports');
    for (declaration in projection.declarations) {
      final requestPlan = declaration.requestPlan;
      final request = requestPlan.request;
      final where = request.external ? request.path : module.toPath(request.path);
      if (!declaration.typeOnly && requestPlan.bindings.length == 0)
        emitTsSideEffectImport(request, where, importExtension);
      else
        emitTsImports(where, [for (binding in requestPlan.bindings) binding],
          importExtension, declaration.typeOnly);
    }
    endImportTimer();

    if (JsonTypeSupport.moduleUsesJsonTypes(module)
      || JsonTypeSupport.dependenciesUseJsonTypes(deps)) {
      writeNewline();
      JsonTypeSupport.emitAliases(line -> {
        write(line);
        writeNewline();
      });
    }

    // Keep Genes behavior for js.Lib.global feature.
    final hasRuntimeCode = module.members.exists(m -> switch m {
      case MClass(cl, _, _) if (cl.isInterface): false;
      case MType(_, _): false;
      case _: true;
    });
    if (hasRuntimeCode && module.module != 'genes.Register'
      && ctx.hasFeature('js.Lib.global')) {
      writeNewline();
      write("const $global = ");
      write(ctx.typeAccessor(TypeUtil.registerType));
      write(".$global");
      writeNewline();
    }

    for (member in module.members) {
      final memberProjection = Module.memberProjection(member);
      if (!memberProjection.emitImplementation)
        continue;
      final previousSourcePositions = emitTsMemberSourcePositions;
      emitTsMemberSourcePositions = memberProjection.emitSourcePosition;
      switch member {
        case MClass(cl, params, _) if (cl.isInterface):
          emitTsInterface(cl, params, memberProjection.exportImplementation);
        case MClass(cl, _, fields):
          final emittableFields = Module.emittableFields(fields);
          emitTsModuleFunctions(cl);
          final endClassTimer = timer('emitClass');
          emitTsClass(module.isCyclic, cl, emittableFields,
            memberProjection.exportImplementation,
            memberProjection.registerRuntimeType);
          endClassTimer();
          final endStaticsTimer = timer('emitStatics');
          emitTsStatics(module.isCyclic, cl, emittableFields);
          endStaticsTimer();
          emitInit(cl);
        case MEnum(et, _):
          final endEnumTimer = timer('emitEnums');
          emitTsEnum(et, memberProjection.exportImplementation,
            memberProjection.registerRuntimeType);
          endEnumTimer();
        case MType(def, params):
          emitTsTypeDefinition(def, params,
            memberProjection.exportImplementation);
        case MMain(e):
          writeNewline();
          emitExpr(e);
        default:
      }
      emitTsMemberSourcePositions = previousSourcePositions;
    }

    for (export in module.expose)
      emitExport(export, module.toPath(export.module), importExtension,
        export.isType);

    return endTimer();
  }

  static function isReactJsxMarkerCallExpr(e: TypedExpr): Bool {
    return JsxPlan.isMarkerCallExpression(e);
  }

  static function isReactJsxMarkerCallee(callee: TypedExpr): Null<String> {
    return JsxPlan.markerName(callee);
  }

  static function unwrapExpr(e: TypedExpr): TypedExpr {
    var cur = e;
    while (cur != null) {
      switch cur.expr {
        case TMeta(_, e1):
          cur = e1;
        case TCast(e1, null):
          cur = e1;
        case TParenthesis(e1):
          cur = e1;
        default:
          return cur;
      }
    }
    return e;
  }

  function emitTsImports(where: String,
      imports: Array<genes.Dependencies.Dependency>, extension: Null<String>,
      typeOnly: Bool) {
    final named: Array<genes.Dependencies.Dependency> = [];
    for (def in imports)
      switch def.type {
        case genes.Dependencies.DependencyType.DAsterisk | genes.Dependencies.DependencyType.DDefault:
          emitTsImport([def], where, extension, typeOnly);
        default:
          named.push(def);
      }
    for (group in Dependencies.groupByImportAttribute(named))
      emitTsImport(group, where, extension, typeOnly);
  }

  /** Emits a bare ESM request from the shared runtime-order projection. */
  function emitTsSideEffectImport(request: DependencyModuleRequest,
      where: String, extension: Null<String>): Void {
    write('import');
    writeSpace();
    emitPos(request.pos);
    emitString(if (!request.external && extension != null)
      '$where$extension' else where);
    if (request.importAttributeType != null) {
      write(' with { type: ');
      emitString(request.importAttributeType);
      write(' }');
    }
    writeNewline();
  }

  function emitTsImport(what: Array<genes.Dependencies.Dependency>,
      where: String, extension: Null<String>, typeOnly: Bool) {
    write(typeOnly ? 'import type' : 'import');
    writeSpace();
    switch what {
      case [def = {type: genes.Dependencies.DependencyType.DAsterisk}]:
        emitPos(def.pos);
        write('* as ' + if (def.alias != null) def.alias else def.name);
      case [def = {type: genes.Dependencies.DependencyType.DDefault}]:
        emitPos(def.pos);
        write(if (def.alias != null) def.alias else def.name);
      case defs:
        write('{');
        for (def in join(defs, write.bind(', '))) {
          emitPos(def.pos);
          write(def.name
            + if (def.alias != null && def.alias != def.name)
              ' as ${def.alias}' else '');
        }
        write('}');
    }
    writeSpace();
    write('from');
    writeSpace();
    var isExternal = false;
    for (dependency in what)
      if (dependency.external) {
        isExternal = true;
        break;
      }
    emitString(if (!isExternal && extension != null) '$where$extension' else
      where);
    final importAttributeType = Dependencies.commonImportAttributeType(what);
    if (!typeOnly && importAttributeType != null) {
      write(' with { type: ');
      emitString(importAttributeType);
      write(' }');
    }
    writeNewline();
  }

  function emitTsStatics(checkCycles: (module: String) -> Bool, cl: ClassType,
      fields: Array<GenesField>) {
    // Emit typed declarations inside the class (for TS), then reuse JS emitter's
    // static initialization logic outside the class.
    //
    // NOTE: This is intentionally conservative to avoid semantic changes.
    // We only declare static fields here; actual initialization remains outside.

    // No-op for now: declarations are emitted in emitTsClass.
    super.emitStatics(checkCycles, cl, fields);
  }

  override function emitStatic(cl: ClassType, field: GenesField) {
    // Some TS special-cases for strict type-checking.
    // `unique symbol` statics must be `readonly`, but Haxe emits assignments after
    // the class body. Keep runtime behavior but silence TS on that assignment.
    if (field.tsType == 'unique symbol') {
      writeNewline();
      write('// @ts-ignore');
      writeNewline();
      emitPos(field.pos);
      emitIdent(TypeUtil.className(cl));
      emitField(staticName(cl, field));
      write(' = ');
      emitValue(field.expr);
      return;
    }
    super.emitStatic(cl, field);
  }

  override function emitCall(e: TypedExpr, params: Array<TypedExpr>,
      inValue: Bool) {
    if (emitPlannedTemplateLiteralCall(e, params))
      return;
    if (emitPlannedJsxCall(e, params))
      return;
    final privateMethod = privateMethodCall(e);
    if (privateMethod != null) {
      emitPrivateMethodCall(privateMethod, params);
      return;
    }
    switch [e.expr, params] {
      case [TConst(TSuper), args]:
        // Constructors (`new`) are implemented via the `[Register.new]` runtime
        // initializer. In TS output we still emit a normal `constructor`, but
        // `super(...)` calls inside Haxe constructor bodies must target the
        // initializer chain.
        emitPos(e.pos);
        switch extendsExtern {
          case Some(t):
            write(ctx.typeAccessor(t));
            write(args.length > 0 ? '.call(this, ' : '.call(this');
          case None:
            // `[Register.new]` overload signatures are intentionally typed as
            // uncallable (`never[]`) to avoid forcing TS constructor signature
            // compatibility across inheritance. Use an unsafe cast here to
            // call the super initializer without leaking `any`.
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.unsafeCast<Function>(');
            write('super[');
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.new]');
            write(').call(this');
            if (args.length > 0) write(', ');
        }
        for (param in join(args, write.bind(', ')))
          emitValue(param);
        write(')');
        return;
      default:
    }
    // An annotated generic extern asks TypeScript to reuse Haxe's already
    // checked instantiation. This is intentionally declaration-driven: an
    // ordinary generic call keeps native TS inference, and classic JS never
    // enters this emitter. See `ExplicitTypeArguments` for validation and the
    // structural type-parameter binding contract.
    final explicitCallSite = currentExplicitTypeArguments;
    final explicitTypeArguments = ExplicitTypeArguments.forCall(e,
      explicitCallSite);
    if (explicitCallSite != null && explicitTypeArguments != null) {
      // A carrier belongs to one direct call occurrence. Clear it as soon as
      // that call claims the witness so a nested call to the same extern field
      // cannot accidentally receive the outer call's type argument.
      currentExplicitTypeArguments = null;
    }
    final enumDecision = boundaryPlan == null ? null : boundaryPlan.enumCall(e);
    if (enumDecision != null) {
      // A Haxe enum constructor is a generic function in emitted TS. TypeScript
      // normally infers from payloads alone. The immutable boundary plan owns
      // the exact destination application, payload bridges, and every type-only
      // dependency this expression is allowed to print.
      emitValue(e);
      TypeEmitter.emitParams(this, enumDecision.parameters, false);
      write('(');
      for (i in 0...params.length) {
        if (i > 0)
          write(', ');
        final expectedArg = i < enumDecision.argumentTypes.length ? enumDecision.argumentTypes[i] : null;
        final actual = params[i];
        final bridge = enumDecision.bridgeAt(i);
        if (bridge != null) {
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.unsafeCast<');
          TypeEmitter.emitType(this, bridge.target);
          write('>(');
          // Preserve the source value's own null/undefined contract before the
          // planned TypeScript assertion. Passing the enum payload's non-null
          // destination here would suppress `?? null` on an optional field and
          // could expose raw JavaScript `undefined` to Haxe code.
          emitValueWithExpectedType(null, bridge.source);
          write(')');
        } else {
          emitValueWithExpectedType(expectedArg, actual);
        }
      }
      write(')');
      return;
    }
    final callDecision = boundaryPlan == null ? null : boundaryPlan.call(e);
    if (callDecision != null) {
      // The dependency planner has already reserved every assertion target.
      // This branch only renders those immutable decisions and evaluates each
      // original argument once.
      emitPos(e.pos);
      emitCallCallee(e, explicitTypeArguments);
      write('(');
      for (i in 0...params.length) {
        if (i > 0)
          write(', ');
        final expectedArg = i < callDecision.argumentTypes.length ? callDecision.argumentTypes[i] : null;
        final bridge = callDecision.bridgeAt(i);
        if (bridge != null) {
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.unsafeCast<');
          TypeEmitter.emitType(this, bridge.target);
          write('>(');
          // Emit the source value using its own null/undefined rules first.
          // The assertion is a later TypeScript assignment boundary.
          emitValueWithExpectedType(null, bridge.source);
          write(')');
        } else {
          emitValueWithExpectedType(expectedArg, params[i]);
        }
      }
      write(')');
      return;
    }
    // A few established literal and metadata projections still need a custom
    // argument writer: an unconstrained generic receiving literal `null`,
    // an explicit host type override, or an authored type whose TypeScript
    // projection is exactly `null`. These are not general Haxe-to-TypeScript
    // conversions; nullability-only value conversions are owned by the
    // immutable boundary plan above.
    final isEnumCtorCall = switch unwrapExpr(e).expr {
      case TField(_, FEnum(_, _)): true;
      default: false;
    }
    final fnType = haxe.macro.Context.followWithAbstracts(e.t);
    final args = switch fnType {
      case TFun(a, _): a;
      default: null;
    }
    final cachedArgTsTypes = cachedCallableArgTsTypes(e);
    if (params.length > 0) {
      inline function isUnresolvedMono(t: Type): Bool
        return switch t {
          case TMono(r): r.get() == null;
          default: false;
        }
      var needsCasts = false;
      if (isEnumCtorCall && params.exists(p -> isNullConst(unwrapExpr(p))))
        needsCasts = true;
      if (!needsCasts && args != null) {
        final max = params.length < args.length ? params.length : args.length;
        for (i in 0...max) {
          final expected = args[i].t;
          final actual = params[i];
          final actualUnwrapped = unwrapExpr(actual);
          // Route exact projected nulls through the plain-call argument writer
          // below. A generic TCast would otherwise emit a redundant assertion
          // before this expected-type fact can be observed.
          if (acceptsExactProjectedNull(expected, actual)) {
            needsCasts = true;
            break;
          }
          if (isUnresolvedMono(expected) && isNullConst(actualUnwrapped)) {
            needsCasts = true;
            break;
          }
        }
      }
      if (!needsCasts && cachedArgTsTypes.length > 0) {
        final max = params.length < cachedArgTsTypes.length ? params.length : cachedArgTsTypes.length;
        for (i in 0...max) {
          final expectedTsType = cachedArgTsTypes[i];
          if (expectedTsType != null
            && needsEnumAbstractExpectedAssertion(expectedTsType, params[i])) {
            needsCasts = true;
            break;
          }
        }
      }
      final isPlainCall = switch unwrapExpr(e).expr {
        case TIdent('`trace' | "__resources__" | "__new__" | "__instanceof__" | "__typeof__" | "__strict_eq__" | "__strict_neq__" | "__define_feature__" | "__feature__"):
          false;
        case TCall(_, _):
          false;
        case TField(_,
          FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: _})):
          false;
        default:
          true;
      }
      if (needsCasts && isPlainCall) {
        emitPos(e.pos);
        emitCallCallee(e, explicitTypeArguments);
        write('(');
        for (i in 0...params.length) {
          if (i > 0)
            write(', ');
          final expected = args != null && i < args.length ? args[i].t : null;
          final expectedTsType = i < cachedArgTsTypes.length ? cachedArgTsTypes[i] : null;
          final actual = params[i];
          final actualUnwrapped = unwrapExpr(actual);
          if (expected != null && acceptsExactProjectedNull(expected, actual)) {
            emitPos(actual.pos);
            write('null');
          } else if (expectedTsType != null
            && needsEnumAbstractExpectedAssertion(expectedTsType, actual)) {
            write('(');
            emitValue(actual);
            write(' as ');
            write(expectedTsType);
            write(')');
          } else if (expected != null && isUnresolvedMono(expected)
            && isNullConst(unwrapExpr(actual))) {
            // Avoid TS inferring `null` for unconstrained generic params.
            // `never` keeps the call assignable without introducing `any`.
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.unsafeCast<never>(null)');
          } else if (isEnumCtorCall && isNullConst(actualUnwrapped)
            && (expected == null || typeAllowsNull(expected))) {
            // Enum constructors are often used with `null` (e.g. `Noise`). Casting
            // to `never` avoids TS inferring `null` for generic params.
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.unsafeCast<never>(null)');
          } else {
            // One sibling may have selected this manual argument loop. Keep
            // the normal expected-type context for every untouched argument;
            // object literals need it for host field names and optional
            // null-to-undefined writes.
            emitValueWithExpectedType(expected, actual);
          }
        }
        write(')');
        return;
      }
    }
    if (isJsPromiseResolveCallee(e)
      && params.exists(param -> isNullConst(unwrapExpr(param)))) {
      emitPromiseResolveCall(e, params, inValue);
    } else if (explicitTypeArguments != null) {
      emitPos(e.pos);
      emitCallCallee(e, explicitTypeArguments);
      write('(');
      emitCallParams(e, params);
      write(')');
    } else {
      super.emitCall(e, params, inValue);
    }
  }

  /** Emits one typed callee plus an optional explicit TS instantiation. */
  function emitCallCallee(callee: TypedExpr,
      arguments: Null<Array<ExplicitTypeArgument>>): Void {
    emitValue(callee);
    if (arguments != null) {
      write('<');
      for (index in 0...arguments.length) {
        if (index > 0)
          write(', ');
        final argument = arguments[index];
        if (argument.tsType == null) {
          TypeEmitter.emitType(this, argument.type);
        } else {
          write(argument.tsType);
        }
      }
      write('>');
    }
  }

  /**
   * Emits native TypeScript syntax that preserves contextual template inference.
   *
   * Why: `"prefix" + value` always widens to `string`, even when the destination
   * is a template-literal type. A backtick expression lets TypeScript prove the
   * shape without a cast or runtime helper.
   *
   * What/How: static intent remains an ordinary quoted literal. Dynamic intent
   * alternates escaped cooked chunks with each typed value exactly once. The
   * surrounding expected type is not propagated into interpolations, preventing
   * a route-like destination from manufacturing assertions inside `${...}`.
   */
  override function emitTemplateLiteralIntent(intent: TemplateLiteralIntent): Void {
    emitPos(intent.pos);
    if (intent.values.length == 0) {
      emitString(intent.chunks[0]);
      return;
    }
    write('`');
    for (index in 0...intent.values.length) {
      write(escapeTemplateLiteralChunk(intent.chunks[index]));
      write('$${');
      final value = intent.values[index];
      emitValueWithExpectedType(value.t, value);
      write('}');
    }
    write(escapeTemplateLiteralChunk(intent.chunks[intent.chunks.length - 1]));
    write('`');
  }

  /**
   * Escapes one cooked Haxe string chunk without changing its runtime value.
   *
   * Backticks, backslashes, and `${` would otherwise reopen TypeScript template
   * syntax. Control characters use explicit escapes so generated lines and
   * source-map columns stay deterministic, including authored multiline text.
   */
  static function escapeTemplateLiteralChunk(value: String): String {
    final result = new StringBuf();
    var index = 0;
    while (index < value.length) {
      final code = value.charCodeAt(index);
      if (code == '$'.code && index + 1 < value.length
        && value.charCodeAt(index + 1) == '{'.code) {
        result.add('\\$${');
        index += 2;
        continue;
      }
      result.add(switch code {
        case '\\'.code: '\\\\';
        case '`'.code: '\\`';
        case '\n'.code: '\\n';
        case '\r'.code: '\\r';
        case '\t'.code: '\\t';
        case value if (value < 32): '\\x' + StringTools.hex(value, 2);
        case value: String.fromCharCode(value);
      });
      index++;
    }
    return result.toString();
  }

  static function explicitErasedCastSource(expr: TypedExpr): Null<TypedExpr> {
    return switch expr.expr {
      case TCast(inner, null): inner;
      case TMeta(_, inner) | TParenthesis(inner):
        explicitErasedCastSource(inner);
      default:
        null;
    }
  }

  function emitPromiseResolveCall(e: TypedExpr, params: Array<TypedExpr>,
      inValue: Bool) {
    final previous = suppressPromiseResolveNullThenableCast;
    suppressPromiseResolveNullThenableCast = true;
    super.emitCall(e, params, inValue);
    suppressPromiseResolveNullThenableCast = previous;
  }

  /** Chooses TSX spelling or typed createElement spelling for shared intent. */
  override function emitJsxIntent(intent: JsxIntent): Void {
    switch intent {
      case ElementIntent(tag, props, children, _):
        if (jsxEmitTsx)
          emitJsxSourceElement(tag, props, children);
        else
          emitCreateElement(requireJsxRuntimeBinding(intent), tag, props,
            children);
      case FragmentIntent(children, _):
        if (jsxEmitTsx)
          emitJsxSourceFragment(children);
        else
          emitCreateElementFragment(requireJsxRuntimeBinding(intent), children);
    }
  }

  /** `.tsx` preserves JSX source; plain `.ts` retains createElement lowering. */
  override function emitsJsxSource(): Bool {
    return jsxEmitTsx;
  }

  /** JSX props preserve explicit `undefined`; omission is not Haxe `null`. */
  override function emitJsxValue(expression: TypedExpr,
      source: JsxValueSource): Void {
    final previous = suppressOptionalFieldNullNormalization;
    final previousExpected = currentExpectedValueType;
    suppressOptionalFieldNullNormalization = true;
    currentExpectedValueType = expression.t;
    super.emitJsxValue(expression, source);
    currentExpectedValueType = previousExpected;
    suppressOptionalFieldNullNormalization = previous;
  }

  function emitCreateElement(runtime: String, tag: JsxTagIntent,
      props: Array<JsxPropIntent>, children: Array<JsxChildIntent>) {
    final functionPropsType = validatedFunctionPropsType(tag);
    // React accepts nested children as later createElement arguments, but its
    // TypeScript overloads do not count those arguments when checking a
    // required `children` property. When HXX has already proved that nested
    // markup supplies that property, write it last in the property object.
    // This evaluates it once and preserves React's rule that nested content
    // overrides an earlier optional spread value.
    final childrenBelongInProps = jsxPlan != null
      && jsxPlan.nestedChildrenSupplyRequiredProperty(tag);
    write(runtime);
    write('.createElement');
    if (functionPropsType != null) {
      write('<');
      TypeEmitter.emitType(this, functionPropsType);
      write('>');
    }
    write('(');
    emitValue(JsxPlan.tagExpression(tag));
    write(', ');
    emitCreateElementProps(runtime, tag, props, functionPropsType,
      childrenBelongInProps ? children : []);
    if (!childrenBelongInProps) {
      for (child in children) {
        write(', ');
        emitJsxChildValue(child);
      }
    }
    write(')');
  }

  function emitCreateElementFragment(runtime: String,
      children: Array<JsxChildIntent>) {
    write(runtime);
    write('.createElement(');
    write(runtime);
    write('.Fragment, null');
    for (child in children) {
      write(', ');
      emitJsxChildValue(child);
    }
    write(')');
  }

  function emitCreateElementProps(runtime: String, tag: JsxTagIntent,
      props: Array<JsxPropIntent>, functionPropsType: Null<Type>,
      requiredChildren: Array<JsxChildIntent>) {
    if (props.length == 0 && requiredChildren.length == 0) {
      write('null');
      return;
    }
    final hasTagSpecificPropsContract = switch tag {
      case IntrinsicTag(_, _) | ComponentTag(_): true;
      case DynamicIntrinsicTag(_): false;
    };
    if (hasTagSpecificPropsContract)
      write('(');
    write('{');
    for (p in join(props, write.bind(', '))) {
      switch p {
        case SpreadProp(e, source):
          write('...');
          emitJsxValue(e, source);
        case NamedProp(name, value, source):
          emitObjectKey(name);
          write(': ');
          emitJsxValue(value, source);
      }
    }
    if (requiredChildren.length > 0) {
      if (props.length > 0)
        write(', ');
      write('children: ');
      if (requiredChildren.length == 1) {
        emitJsxChildValue(requiredChildren[0]);
      } else {
        write('[');
        for (child in join(requiredChildren, write.bind(', ')))
          emitJsxChildValue(child);
        write(']');
      }
    }
    write('}');
    // A runtime String tells React which intrinsic to create only when this
    // code executes. There is therefore no single tag-specific
    // `ComponentPropsWithRef` contract that TypeScript can honestly check
    // here. HXX has already rejected unsafe values and non-object spreads, and
    // the exact object literal keeps its inferred TypeScript type for React's
    // string-tag overload. Static intrinsic and component tags continue below
    // and retain their stronger `satisfies` checks.
    if (!hasTagSpecificPropsContract)
      return;
    write(' satisfies ');
    write('(');
    if (functionPropsType == null) {
      write(runtime);
      // React treats `ref` as a checked property of intrinsic elements and,
      // in React 19, of components that declare it. `ComponentPropsWithRef`
      // keeps that host contract visible in typed createElement output. HXX
      // has already validated the same closed property before this printer
      // runs, so the utility is an independent parity check, not a cast.
      write('.ComponentPropsWithRef<');
      emitComponentPropsTypeArgForTag(tag);
      write('>');
    } else {
      TypeEmitter.emitType(this, functionPropsType);
    }
    // React's `key` belongs to Attributes rather than a component's ordinary
    // property object. HXX validates it separately and createElement accepts
    // the same intersection, matching JSX syntax without widening other props.
    write(' & ');
    write(runtime);
    write('.Attributes');
    // In TSX, TypeScript allows `data-*` / `aria-*` attributes by default.
    // In low-level `createElement(...)` mode, we add explicit mapped types so
    // real-world attributes don't get blocked by excess property checks.
    write(' & { [K in `data-$${string}`]?: string | number | boolean | null | undefined }');
    write(' & { [K in `aria-$${string}`]?: string | number | boolean | null | undefined }');
    write(')');
    write(')');
  }

  /**
   * Returns Haxe's already-inferred property type for a function component.
   *
   * React's `ComponentPropsWithRef<typeof GenericComponent>` necessarily
   * substitutes `unknown` for a still-generic function. The typed Haxe tag has
   * already been unified with its HXX values, so carrying that exact argument
   * type into `createElement<P>` preserves inference without a cast or wrapper
   * component. The plan returns no specialization when a type parameter is
   * still unbound or when metadata supplies a wrapper/class contract; those
   * cases keep React's ordinary utility-type inference and never name a
   * checker-only schema in generated code.
   */
  function validatedFunctionPropsType(tag: JsxTagIntent): Null<Type> {
    return switch tag {
      case ComponentTag(_):
        jsxPlan == null ? null : jsxPlan.componentPropsType(tag);
      default: null;
    }
  }

  function emitObjectKey(name: String) {
    if (isValidTsObjectKey(name)) {
      write(name);
      return;
    }
    emitString(name);
  }

  static function isValidTsObjectKey(name: String): Bool {
    if (name == null || name.length == 0)
      return false;
    final first = name.charCodeAt(0);
    if (!((first >= 'a'.code && first <= 'z'.code)
      || (first >= 'A'.code && first <= 'Z'.code)
      || first == '_'.code
      || first == '$'.code))
      return false;
    for (i in 1...name.length) {
      final c = name.charCodeAt(i);
      if (!((c >= 'a'.code && c <= 'z'.code)
        || (c >= 'A'.code && c <= 'Z'.code)
        || (c >= '0'.code && c <= '9'.code) || c == '_'.code || c == '$'.code))
        return false;
    }
    return true;
  }

  function emitComponentPropsTypeArgForTag(tag: JsxTagIntent) {
    switch tag {
      case IntrinsicTag(name, _):
        emitString(name);
      case DynamicIntrinsicTag(expression) | ComponentTag(expression):
        write('typeof ');
        emitValue(expression);
    }
  }

  /**
   * Emits a class constructor where Haxe runtime reflection requires a
   * JavaScript `Function`.
   *
   * Why: a generated class can declare an unrelated static `toString` or
   * `apply` whose signature conflicts with TypeScript's structural Function
   * interface. The runtime value is still the ES class constructor and
   * therefore still a Function.
   *
   * What/How: the typed `TsReflectionClassValue` proof decides whether this
   * exact class surface needs `Register.unsafeCast<Function>`. The callback
   * prints the original local or imported class expression once. Callers use
   * this helper only for `__interfaces__`, `__super__`, `__class__`, and
   * runtime registration; ordinary class values remain fully structural.
   */
  function emitReflectedFunctionClassValue(owner: ClassType,
      emitClassValue: () -> Void): Void {
    final needsBridge = TsReflectionClassValue.needsFunctionBridge(owner);
    if (needsBridge) {
      write(ctx.typeAccessor(TypeUtil.registerType));
      write('.unsafeCast<Function>(');
    }
    emitClassValue();
    if (needsBridge)
      write(')');
  }

  function emitTsClass(checkCycles: (module: String) -> Bool, cl: ClassType,
      fields: Array<GenesField>, export = true, registerRuntimeType = true) {
    final prevClass = currentClass;
    currentClass = cl;

    writeNewline();
    emitComment(cl.doc);
    emitPos(cl.pos);
    if (export)
      write('export ');
    write('class ');
    write(TypeUtil.className(cl));
    if (cl.params != null && cl.params.length > 0)
      emitTypeParamDecls(cl.params.map(p -> p.t), true);

    final extendsInherits = cl.superClass != null
      || JsModuleEmitter.hasConstructor(fields);
    if (extendsInherits) {
      write(' extends ');
      switch cl.superClass {
        case null:
          // Root classes still use `Register.inherits()` so we can share the same
          // `[Register.new]` initialization convention across the runtime.
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.inherits()');
        case {t: ref, params: superParams}:
          final t: ModuleType = TClassDecl(ref);
          final isCyclic = checkCycles(TypeUtil.moduleTypeModule(t));
          // Preserve Genes' runtime semantics (especially cycle handling) by
          // always extending a `Register.inherits(...)` base class. We then cast
          // to the concrete superclass type so TS can see inherited members.
          write('(');
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.inherits(');
          if (isCyclic)
            write('() => ');
          write(ctx.typeAccessor(t));
          if (isCyclic)
            write(', true');
          write(') as typeof ');
          write(ctx.typeAccessor(t));
          write(')');
          if (superParams != null)
            TypeEmitter.emitParams(this, superParams, false);
      }
    }

    extendsExtern = switch cl.superClass {
      case null: None;
      case {t: t = _.get() => {isExtern: true}}:
        Some(cl.superClass.t.get());
      default: None;
    }

    write(' {');
    increaseIndent();

    // Emit a typed TS constructor wrapper that forwards to `super(...)`.
    //
    // The actual Haxe initialization logic lives in `[Register.new](...)` and is
    // invoked by the `Register.inherits(...)` constructor at runtime. Having a
    // real TS `constructor` gives correct `new (...)` typing for consumers.
    if (extendsInherits) {
      final ctorField = fields.find(f -> f.kind.equals(Constructor));
      if (ctorField != null)
        switch ctorField.expr {
          case {expr: TFunction(f)}:
            writeNewline();
            emitPos(ctorField.pos);
            write('constructor(');
            emitTypedFunctionArguments(f, ctorField);
            write(') {');
            increaseIndent();
            writeNewline();
            // Haxe constructors are routed through `Register.inherits(...)`
            // and `[Register.new]`. The superclass type may have an unrelated
            // TS constructor signature, so we silence `super(...)` arity/type
            // checks here while keeping the public constructor signature typed.
            if (cl.superClass != null) {
              write('// @ts-ignore');
              writeNewline();
            }
            write('super(');
            emitForwardArgs(f, ctorField);
            write(');');
            decreaseIndent();
            writeNewline();
            write('}');
          default:
        }
    }

    // Emit typed property declarations so TS code can type-check under `strict`.
    for (field in fields) {
      switch field.kind {
        case Property:
          currentCallableSignature = null;
          // Skip native accessors for now (handled by JS emitter behavior).
          // Still declare the property name as a field so TS knows it exists.
          writeNewline();
          emitPos(field.pos);
          write('declare ');
          if (field.isStatic) {
            if (field.tsType == 'unique symbol')
              write('static readonly ');
            else
              write('static ');
          }
          emitMemberName(field.isStatic ? staticName(cl,
            field) : moduleFieldName(field));
          final propertyNullish = NullishContract.forProperty(field.type,
            field.meta);
          if (propertyNullish.emitOptionalSyntax)
            write('?');
          write(': ');
          // Node vs DOM timer handles: `setInterval` return type varies by lib.
          // Model `haxe.Timer.id` as whatever the host `setInterval` returns.
          if (!field.isStatic
            && field.name == 'id'
            && cl.pack.join('.') == 'haxe'
            && cl.name == 'Timer') {
            write('ReturnType<typeof setInterval> | null');
          } else {
            emitFieldTsType(field);
          }
          write(';');
        case Method #if (haxe_ver >= 4.2) if (!field.isAbstract) #end:
          // Module-level externs (KModuleFields) can be declared as extern
          // functions (no body) with `@:jsRequire`. These appear as static
          // fields on the module fields class, so we declare them as function
          //-typed properties and bind them at runtime in the JS emitter.
          if (field.expr == null && field.isStatic && field.meta != null #if (haxe_ver >= 4.2)
            && cl.kind.match(KModuleFields(_)) #end
          ) {
            final hasJsRequire = switch field.meta.extract(':jsRequire') {
              case [_]: true;
              default: false;
            };
            if (!hasJsRequire)
              continue;
            writeNewline();
            emitPos(field.pos);
            write('declare static ');
            emitMemberName(staticName(cl, field));
            write(': ');
            currentCallableSignature = field.callableSignature;
            emitType(field.type, field.callableSignature.parameters());
            write(';');
          }
        default:
      }
    }

    // Emit methods/ctors with typed args/returns.
    for (field in fields) {
      final moduleFunction = moduleFunctionPlan == null ? null : moduleFunctionPlan.entryFor(cl,
        field);
      if (moduleFunction != null) {
        emitTsModuleFunctionDescriptorSeed(cl, moduleFunction);
        continue;
      }
      if (!shouldEmitClassMethod(cl, field))
        continue;
      switch field.kind {
        case Constructor | Method
          #if (haxe_ver >= 4.2) if (!field.isAbstract) #end:
          switch field.expr {
            case null:
            case {expr: TFunction(f)}:
              writeMemberNewline(field.doc != null);
              emitComment(field.doc);
              if (!field.kind.equals(Constructor) && field.overloads.length > 0)
                emitClassMethodOverloadSignatures(cl, field);
              emitPos(field.pos);
              final isAsync = field.meta != null
                && (field.meta.has(':jsAsync') || field.meta.has('jsAsync'));
              if (field.isStatic) {
                write('static ');
                if (isAsync)
                  write('async ');
                emitMemberName(staticName(cl, field));
              } else if (field.kind.equals(Constructor)) {
                // Provide an overload signature for `[Register.new]` so
                // subclasses can have different constructor signatures without
                // triggering override incompatibilities in TS.
                //
                // We intentionally make this overload uncallable (`never[]`) to
                // keep `[Register.new]` an internal runtime convention; TS
                // consumers should use `new (...)`.
                write('[');
                write(ctx.typeAccessor(TypeUtil.registerType));
                write('.new](...args: never[]): void;');
                writeNewline();
                emitPos(field.pos);
                write('[');
                write(ctx.typeAccessor(TypeUtil.registerType));
                write('.new]');
              } else {
                if (isAsync)
                  write('async ');
                emitMemberName(moduleFieldName(field));
              }

              if (field.overloads.length > 0 && !field.kind.equals(Constructor))
                emitOverloadedImplementationTypeParams(field);
              else
                emitMethodTypeParams(field);
              write('(');
              if (field.overloads.length > 0 && !field.kind.equals(Constructor))
                emitOverloadedImplementationArguments(f, field);
              else
                emitTypedFunctionArguments(f, field);
              write(')');

              // Return type
              if (field.kind.equals(Constructor)) {
                write(': void ');
              } else {
                write(': ');
                if (field.overloads.length > 0)
                  emitOverloadedImplementationReturnType(field, f);
                else
                  emitReturnTsType(field, f, null);
                write(' ');
              }

              final body = getFunctionBody(f);
              final returnOverride = field.meta != null ? (switch extractStringMeta(field.meta,
                ':ts.returnType') {
                case null: extractStringMeta(field.meta, ':genes.returnType');
                case v: v;
              }) : null;
              final isRuntimeUnsafeCast = field.isStatic
                && field.name == 'unsafeCast'
                && cl.module == 'genes.Register' && cl.name == 'Register';
              if (isRuntimeUnsafeCast) {
                // `Register.unsafeCast` must be the identity function at runtime.
                // Avoid emitter-inserted casts causing infinite recursion here.
                write('{');
                increaseIndent();
                writeNewline();
                write('return ');
                if (f.args.length > 0)
                  emitLocalVar(f.args[0].v);
                else
                  write('undefined');
                write(';');
                decreaseIndent();
                writeNewline();
                write('}');
              } else {
                switch [returnOverride, body.expr] {
                  case [v, TBlock([])]
                    if (v != null
                      && v != 'any'
                      && v != 'void'
                      && v != 'undefined'):
                    // TS requires a return for non-void declared return types.
                    // Preserve JS runtime behavior by returning `undefined`.
                    write('{');
                    increaseIndent();
                    writeNewline();
                    write('return ');
                    write(ctx.typeAccessor(TypeUtil.registerType));
                    write('.unsafeCast<');
                    write(v);
                    write('>(undefined);');
                    decreaseIndent();
                    writeNewline();
                    write('}');
                  default:
                    final prevReturn = currentReturnType;
                    final prevVoidLike = currentReturnIsVoidLike;
                    currentReturnType = switch field.type {
                      case TFun(_, ret): ret;
                      default: null;
                    }
                    currentReturnIsVoidLike = switch returnOverride {
                      case "void" | "Promise<void>":
                        true;
                      default: currentReturnType != null && isVoidLike(currentReturnType);
                    }
                    emitExpr(body);
                    currentReturnType = prevReturn;
                    currentReturnIsVoidLike = prevVoidLike;
                }
              }
            default:
          }
        default:
      }
    }

    currentCallableSignature = null;

    // Keep Genes runtime identity helpers.
    writeNewline();
    write('static get __name__(): string {');
    increaseIndent();
    writeNewline();
    write('return ');
    emitString(cl.pack.concat([cl.name]).join('.'));
    decreaseIndent();
    writeNewline();
    write('}');

    switch cl.interfaces {
      case []:
      case v:
        writeNewline();
        write('static get __interfaces__(): Function[] {');
        increaseIndent();
        writeNewline();
        write('return [');
        for (i in join(v, write.bind(', '))) {
          final interfaceType = i.t.get();
          emitReflectedFunctionClassValue(interfaceType,
            () -> write(ctx.typeAccessor(interfaceType)));
        }
        write(']');
        decreaseIndent();
        writeNewline();
        write('}');
    }

    switch cl.superClass {
      case null:
      case {t: superRef}:
        final t: ModuleType = TClassDecl(superRef);
        writeNewline();
        write('static get __super__(): Function {');
        increaseIndent();
        writeNewline();
        write('return ');
        final superType = superRef.get();
        emitReflectedFunctionClassValue(superType,
          () -> write(ctx.typeAccessor(t)));
        decreaseIndent();
        writeNewline();
        write('}');
    }

    writeNewline();
    write('get __class__(): Function {');
    increaseIndent();
    writeNewline();
    write('return ');
    emitReflectedFunctionClassValue(cl,
      () -> emitIdent(TypeUtil.className(cl)));
    decreaseIndent();
    writeNewline();
    write('}');

    decreaseIndent();
    writeNewline();
    write('}');

    emitTsModuleFunctionBindings(cl);
    emitPrivateMethodHelpers(cl, fields);

    // Register class in $hxClasses registry (Genes runtime compatibility).
    final id = cl.pack.concat([TypeUtil.className(cl)]).join('.');
    if (registerRuntimeType && id != 'genes.Register'
      && !haxe.macro.Context.defined('genes.ts.minimal_runtime')) {
      writeNewline();
      write(ctx.typeAccessor(TypeUtil.registerType));
      write('.setHxClass(');
      emitString(id);
      write(', ');
      emitReflectedFunctionClassValue(cl,
        () -> emitIdent(TypeUtil.className(cl)));
      write(');');
      writeNewline();
    }

    // Ensure Haxe/Genes reflection works similarly to the JS emitter:
    // - instance vars should appear on the prototype for Type.getInstanceFields()
    // - native accessor properties should exist at runtime for Reflect.field()
    final className = TypeUtil.className(cl);
    for (field in fields) {
      if (!field.kind.equals(Property) || field.isStatic)
        continue;

      if (field.getter || field.setter) {
        writeNewline();
        write('Object.defineProperty(');
        emitIdent(className);
        write('.prototype, ');
        emitString(moduleFieldName(field));
        write(', {');
        increaseIndent();
        if (field.getter) {
          writeNewline();
          write('get: function ');
          if (cl.params.length > 0)
            emitTypeParamDecls(cl.params.map(param -> param.t), true);
          write('(this: ');
          emitIdent(className);
          if (cl.params.length > 0)
            TypeEmitter.emitParams(this, cl.params.map(param -> param.t),
              false);
          write(') { return this.get_');
          write(field.name);
          write('(); },');
        }
        if (field.setter) {
          writeNewline();
          write('set: function ');
          if (cl.params.length > 0)
            emitTypeParamDecls(cl.params.map(param -> param.t), true);
          write('(this: ');
          emitIdent(className);
          if (cl.params.length > 0)
            TypeEmitter.emitParams(this, cl.params.map(param -> param.t),
              false);
          write(', v: ');
          emitFieldTsType(field);
          write(') { this.set_');
          write(field.name);
          write('(v); },');
        }
        decreaseIndent();
        writeNewline();
        write('});');
        writeNewline();
      } else {
        writeNewline();
        write(ctx.typeAccessor(TypeUtil.registerType));
        write('.seedProtoField(');
        emitIdent(className);
        write(', ');
        emitString(moduleFieldName(field));
        write(');');
        writeNewline();
      }
    }

    currentCallableSignature = null;
    currentClass = prevClass;
  }

  /** Emits selected method bodies once as genuine typed module functions. */
  function emitTsModuleFunctions(cl: ClassType): Void {
    if (moduleFunctionPlan == null)
      return;
    final previousClass = currentClass;
    currentClass = cl;
    for (entry in moduleFunctionPlan.entriesFor(cl)) {
      switch entry.field.expr {
        case {expr: TFunction(functionBody)}:
          writeNewline();
          emitPos(entry.field.pos);
          final isAsync = entry.field.meta != null
            && (entry.field.meta.has(':jsAsync')
              || entry.field.meta.has('jsAsync'));
          if (entry.publicExportName != null)
            write('export ');
          if (isAsync)
            write('async ');
          write('function ');
          write(entry.requestedName);
          emitMethodTypeParams(entry.field);
          write('(');
          emitTypedFunctionArguments(functionBody, entry.field);
          write('): ');
          emitReturnTsType(entry.field, functionBody, null);
          write(' ');
          emitSelectedModuleFunctionBody(entry.field, functionBody);
        default:
          // ModuleFunctionPlan rejects missing/non-function bodies.
      }
    }
    currentCallableSignature = null;
    currentClass = previousClass;
  }

  /**
   * Prints the moved body under the same return/nullability context as a method.
   *
   * The function keeps its original typed AST. In particular, recursive calls
   * remain `Owner.field(...)`, so later reassignment has the same observable
   * effect as it did before lowering.
   */
  function emitSelectedModuleFunctionBody(field: GenesField,
      functionBody: TFunc): Void {
    final body = getFunctionBody(functionBody);
    final returnOverride = field.meta != null ? (switch extractStringMeta(field.meta,
      ':ts.returnType') {
      case null: extractStringMeta(field.meta, ':genes.returnType');
      case value: value;
    }) : null;
    final previousReturn = currentReturnType;
    final previousVoidLike = currentReturnIsVoidLike;
    currentReturnType = switch field.type {
      case TFun(_, result): result;
      default: null;
    };
    currentReturnIsVoidLike = switch returnOverride {
      case 'void' | 'Promise<void>': true;
      default: currentReturnType != null && isVoidLike(currentReturnType);
    };
    emitExpr(body);
    currentReturnType = previousReturn;
    currentReturnIsVoidLike = previousVoidLike;
  }

  /**
   * Keeps the original non-enumerable method slot without retaining its body.
   *
   * TypeScript exposes the real public signature as an overload. The following
   * zero-argument `never` implementation creates the ordinary class-method
   * descriptor in the original key position; it cannot be observed because
   * the class property is replaced immediately after class evaluation.
   */
  function emitTsModuleFunctionDescriptorSeed(cl: ClassType,
      entry: ModuleFunctionEntry): Void {
    final field = entry.field;
    switch field.expr {
      case {expr: TFunction(functionBody)}:
        writeMemberNewline(field.doc != null);
        emitComment(field.doc);
        emitPos(field.pos);
        write('static ');
        emitMemberName(entry.classPropertyName);
        emitMethodTypeParams(field);
        write('(');
        // This declaration preserves the public method type but has no body.
        // The real module function above owns default-value evaluation.
        // TypeScript therefore needs only parameter names and types here:
        // writing `= null` in an overload signature is a compile error.
        emitTypedFunctionArguments(functionBody, field, false);
        write('): ');
        emitReturnTsType(field, functionBody, null);
        write(';');
        writeNewline();
        write('static ');
        emitMemberName(entry.classPropertyName);
        write('(): never {');
        increaseIndent();
        writeNewline();
        write('throw this;');
        decreaseIndent();
        writeNewline();
        write('}');
      default:
        // ModuleFunctionPlan rejects missing/non-function bodies.
    }
  }

  /** Installs the exact module function before helpers, registration, or init. */
  function emitTsModuleFunctionBindings(cl: ClassType): Void {
    if (moduleFunctionPlan == null)
      return;
    for (entry in moduleFunctionPlan.entriesFor(cl)) {
      writeNewline();
      emitIdent(TypeUtil.className(cl));
      emitField(entry.classPropertyName);
      write(' = ');
      write(entry.requestedName);
      write(';');
    }
  }

  function emitPrivateMethodHelpers(cl: ClassType, fields: Array<GenesField>) {
    if (!canLowerPrivateMethods(cl))
      return;
    for (field in fields) {
      if (!canLowerPrivateStaticGenesField(cl, field))
        continue;
      if (isPrivateStaticMain(field))
        continue;
      #if (haxe_ver >= 4.2)
      if (field.isAbstract)
        continue;
      #end
      switch field.expr {
        case {expr: TFunction(f)}:
          writeMemberNewline(field.doc != null);
          emitComment(field.doc);
          emitPos(field.pos);
          final isAsync = field.meta != null
            && (field.meta.has(':jsAsync') || field.meta.has('jsAsync'));
          if (isAsync)
            write('async ');
          write('function ');
          final helperName = privateMethodHelperName(cl, field.name);
          write(helperName);
          emitMethodTypeParams(field);
          write('(');
          emitTypedFunctionArguments(f, field);
          write('): ');
          emitReturnTsType(field, f, null);
          write(' ');
          final prevReturn = currentReturnType;
          final prevVoidLike = currentReturnIsVoidLike;
          currentReturnType = switch field.type {
            case TFun(_, ret): ret;
            default: null;
          }
          currentReturnIsVoidLike = currentReturnType != null
            && isVoidLike(currentReturnType);
          emitExpr(getFunctionBody(f));
          currentReturnType = prevReturn;
          currentReturnIsVoidLike = prevVoidLike;
          emitPrivateMethodRuntimeAssignment(cl, field, helperName);
        default:
      }
    }
  }

  function emitPrivateMethodRuntimeAssignment(cl: ClassType,
      field: GenesField, helperName: String) {
    writeNewline();
    write(ctx.typeAccessor(TypeUtil.registerType));
    write('.unsafeCast<{');
    emitMemberName(moduleFieldName(field));
    write(': typeof ');
    write(helperName);
    write('}>(');
    emitIdent(TypeUtil.className(cl));
    write(')');
    emitField(moduleFieldName(field));
    write(' = ');
    write(helperName);
    write(';');
  }

  /**
   * Emits the consumer-visible overload declarations before one class method.
   *
   * Why: Haxe stores `@:overload` call signatures beside one runtime method.
   * Printing only the canonical implementation type makes valid Haxe calls
   * fail when the generated source is checked by TypeScript. Emitting several
   * method bodies would be worse: JavaScript has only one property and the last
   * body would silently replace the others.
   *
   * What/How: every alternate signature followed by the canonical signature is
   * printed as a body-less TypeScript overload. The single implementation is
   * emitted immediately afterwards with a compatible union signature. The
   * signatures come from typed `Module.Field.overloads` facts rather than being
   * reconstructed from rendered strings.
   */
  function emitClassMethodOverloadSignatures(cl: ClassType,
      field: GenesField): Void {
    final signatures = field.overloads.copy();
    signatures.push(field);
    var first = true;
    for (signature in signatures) {
      if (!first)
        writeNewline();
      first = false;
      emitPos(signature.pos);
      if (field.isStatic)
        write('static ');
      emitMemberName(field.isStatic ? staticName(cl,
        field) : moduleFieldName(field));
      emitMethodTypeParams(signature);
      write('(');
      emitFunctionTypeArguments(signature.type);
      write('): ');
      emitFieldFunctionReturnType(signature);
      write(';');
    }
    writeNewline();
  }

  /**
   * Declares all method-local type parameters needed by an overload body.
   *
   * Alternate Haxe signatures can introduce their own generic parameters. The
   * TypeScript implementation signature mentions a union of those argument and
   * return types, so their names must also be in scope there. Exact parameter
   * identities are emitted once; unrelated parameters with the same source
   * name receive collision-safe names. Each public overload declaration still
   * retains its own independently scoped generic list.
   */
  function emitOverloadedImplementationTypeParams(field: GenesField): Void {
    final signatures = field.overloads.copy();
    signatures.push(field);
    currentCallableSignature = CallableSignaturePlan.merge([
      for (signature in signatures)
        signature.callableSignature
    ]);
    emitTypeParamDecls(currentCallableSignature.parameterTypes(), true);
  }

  /**
   * Emits one TypeScript implementation parameter list for all Haxe overloads.
   *
   * Why: TypeScript requires an overload implementation to accept every
   * declared call shape, but the typed Haxe AST exposes one canonical body.
   * Weakening that body to `any`/`unknown` would leak unsafety into user modules.
   *
   * What/How: canonical formal parameters keep their stable local names while
   * their types become unions of the corresponding overload types. Missing or
   * optional positions become optional. Extra and rest positions are expressed
   * as a union of labeled tuples behind one rest parameter, which preserves the
   * JavaScript function-length behavior of the canonical Haxe method. The body
   * remains a single direct lowering and TypeScript can still reject an overload
   * whose implementation performs operations unsafe for its advertised union.
   */
  function emitOverloadedImplementationArguments(f: TFunc,
      field: GenesField): Void {
    final signatures = field.overloads.copy();
    signatures.push(field);
    final canonicalArgs = switch field.type {
      case TFun(args, _): args;
      default: [];
    };
    var maxArgs = 0;
    for (signature in signatures) {
      switch signature.type {
        case TFun(args, _):
          if (args.length > maxArgs)
            maxArgs = args.length;
        default:
      }
    }

    var prefixCount = canonicalArgs.length;
    for (i in 0...canonicalArgs.length) {
      if (genes.util.TypeUtil.isRest(canonicalArgs[i].t)) {
        prefixCount = i;
        break;
      }
    }

    final cachedSig = currentClass == null ? null : SignatureCache.getSig(currentClass,
      field.isStatic, field.name);
    final cachedArgs = cachedSig != null
      && cachedSig.args.length == canonicalArgs.length ? cachedSig.args : null;
    var noOptionalUntil = -1;
    var hadOptional = true;
    for (i in 0...canonicalArgs.length) {
      final optional = cachedArgs != null ? cachedArgs[i].opt : canonicalArgs[i].opt;
      if (optional) {
        hadOptional = true;
      } else if (hadOptional) {
        noOptionalUntil = i;
        hadOptional = false;
      }
    }

    for (i in 0...prefixCount) {
      if (i > 0)
        write(', ');
      var missing = false;
      var optional = false;
      for (signature in signatures) {
        switch signature.type {
          case TFun(args, _):
            if (i >= args.length)
              missing = true;
            else if (args[i].opt)
              optional = true;
          default:
        }
      }
      final canonicalOptional = (cachedArgs != null ? cachedArgs[i].opt : canonicalArgs[i].opt)
        && i > noOptionalUntil;
      final canonicalNullish = NullishContract.forParameter(f.args[i].v.t,
        canonicalOptional);
      final usesNullDefault = canonicalOptional
        && (cachedArgs != null ? (cachedArgs[i].allowsNull
          && !cachedArgs[i].preservesUndefined) : canonicalNullish.usesNullDefault);
      emitLocalVar(f.args[i].v);
      if ((missing || optional) && !usesNullDefault)
        write('?');
      write(': ');
      var emittedTypes = 0;
      for (signature in signatures) {
        switch signature.type {
          case TFun(args, _) if (i < args.length):
            if (emittedTypes++ > 0)
              write(' | ');
            final fallbackType = signature == field
              && cachedArgs != null ? cachedArgs[i].tsType : null;
            final argumentOverride = signature == field ? (extractStringMeta(f.args[i].v.meta,
              ':ts.type') ?? extractStringMeta(f.args[i].v.meta,
                ':genes.type')) : null;
            final argumentNullish = NullishContract.forParameter(args[i].t,
              args[i].opt);
            final needsParens = args[i].t.match(TFun(_, _))
              || fallbackType != null || argumentOverride != null;
            if (needsParens)
              write('(');
            if (signature == field) {
              emitArgTsType(field, f, i, argumentNullish.emittedType,
                fallbackType);
            } else {
              emitType(argumentNullish.emittedType);
            }
            if (needsParens)
              write(')');
          default:
        }
      }
      if (usesNullDefault)
        write(' = null');
    }

    if (maxArgs > prefixCount) {
      if (prefixCount > 0)
        write(', ');
      write('...');
      if (prefixCount < f.args.length)
        emitLocalVar(f.args[prefixCount].v);
      else
        emitLocalIdent('_genesOverloadArgs');
      write(': ');
      var tupleIndex = 0;
      for (signature in signatures) {
        if (tupleIndex++ > 0)
          write(' | ');
        write('[');
        switch signature.type {
          case TFun(args, _):
            var tupleElement = 0;
            for (i in prefixCount...args.length) {
              if (tupleElement++ > 0)
                write(', ');
              final argument = args[i];
              if (genes.util.TypeUtil.isRest(argument.t))
                write('...');
              emitLocalIdent(argument.name != '' ? argument.name : 'arg$i');
              if (argument.opt)
                write('?');
              write(': ');
              emitType(argument.t);
            }
          default:
        }
        write(']');
      }
    }
  }

  /** Emits the union return accepted by the single overload implementation. */
  function emitOverloadedImplementationReturnType(field: GenesField,
      f: TFunc): Void {
    final signatures = field.overloads.copy();
    signatures.push(field);
    var index = 0;
    for (signature in signatures) {
      if (index++ > 0)
        write(' | ');
      final returnOverride = extractStringMeta(signature.meta,
        ':ts.returnType') ?? extractStringMeta(signature.meta,
          ':genes.returnType');
      final needsParens = returnOverride != null || switch signature.type {
        case TFun(_, result): result.match(TFun(_, _));
        default: false;
      };
      if (needsParens)
        write('(');
      if (signature == field)
        emitReturnTsType(field, f, null);
      else
        emitFieldFunctionReturnType(signature);
      if (needsParens)
        write(')');
    }
  }

  function emitFieldFunctionReturnType(field: GenesField): Void {
    final returnOverride = extractStringMeta(field.meta,
      ':ts.returnType') ?? extractStringMeta(field.meta, ':genes.returnType');
    if (returnOverride != null) {
      write(returnOverride);
      return;
    }
    switch field.type {
      case TFun(_, result):
        emitType(result);
      default:
        write('never');
    }
  }

  function emitMethodTypeParams(field: GenesField) {
    currentCallableSignature = field.callableSignature;
    if (currentCallableSignature.isEmpty())
      return;
    emitTypeParamDecls(currentCallableSignature.parameterTypes(), true);
  }

  function emitTypeParamDecls(params: Array<Type>, withConstraints: Bool) {
    if (params.length == 0)
      return;
    write('<');
    for (param in join(params, write.bind(', '))) {
      switch param {
        case TInst(_.get() => {kind: KTypeParameter(constraints)}, _):
          // Use TypeEmitter so `@:ts.type` / `@:genes.type` overrides apply even
          // on type parameter names (see tests/TestTsTypes.hx expectations).
          TypeEmitter.emitType(this, param);
          if (withConstraints && constraints.length > 0) {
            write(' extends ');
            for (c in join(constraints, write.bind(' & ')))
              TypeEmitter.emitType(this, c);
          }
        default:
          // Fallback: best-effort rendering.
          TypeEmitter.emitType(this, param);
      }
    }
    write('>');
  }

  static inline function typeParamKey(param: Type): Null<String> {
    return switch param {
      case TInst(ref, _):
        final cl = ref.get();
        switch cl.kind {
          case KTypeParameter(_): cl.module + '.' + cl.name;
          default: null;
        }
      default:
        null;
    }
  }

  /**
   * Collects generic parameters referenced by a public callable signature.
   *
   * Why: recursive anonymous types can point back to themselves. Public-surface
   * retention makes more such signatures visible than runtime DCE normally
   * leaves behind, so an unguarded walk can overflow before emission begins.
   *
   * What/How: the type-parameter result remains name-based, while anonymous
   * type refs are tracked by object identity for the duration of one signature
   * walk. Re-visiting a ref contributes no new generic parameters and is safe
   * to stop; sibling fields still share the same visited set.
   */
  static function collectUsedTypeParamKeys(type: Type,
      used: Map<String, Bool>,
      ?seenAnonymous: haxe.ds.ObjectMap<Ref<AnonType>, Bool>) {
    if (seenAnonymous == null)
      seenAnonymous = new haxe.ds.ObjectMap();
    // Do not call `followWithAbstracts` here. For this question, generic
    // arguments already expose every referenced type parameter, while following
    // recursive abstracts/typedefs can manufacture an unbounded structural
    // expansion before the anonymous-ref guard gets a chance to run.
    switch type {
      case TInst(ref, params):
        final cl = ref.get();
        switch cl.kind {
          case KTypeParameter(_):
            used.set(cl.module + '.' + cl.name, true);
          default:
        }
        for (p in params)
          collectUsedTypeParamKeys(p, used, seenAnonymous);
      case TEnum(_, params) | TType(_, params) | TAbstract(_, params):
        for (p in params)
          collectUsedTypeParamKeys(p, used, seenAnonymous);
      case TFun(args, ret):
        for (a in args)
          collectUsedTypeParamKeys(a.t, used, seenAnonymous);
        collectUsedTypeParamKeys(ret, used, seenAnonymous);
      case TAnonymous(a):
        if (seenAnonymous.exists(a))
          return;
        seenAnonymous.set(a, true);
        for (f in a.get().fields)
          collectUsedTypeParamKeys(f.type, used, seenAnonymous);
      case TDynamic(t):
        if (t != null)
          collectUsedTypeParamKeys(t, used, seenAnonymous);
      case TMono(r):
        final inner = r.get();
        if (inner != null)
          collectUsedTypeParamKeys(inner, used, seenAnonymous);
      default:
    }
  }

  function emitTypeParamDeclsUnusedNever(params: Array<Type>,
      withConstraints: Bool, used: Map<String, Bool>, tsxSafe: Bool) {
    if (params.length == 0)
      return;
    write('<');
    var first = true;
    var seenDefault = false;
    for (param in params) {
      if (!first)
        write(', ');
      first = false;
      final key = typeParamKey(param);
      final defaultNever = key != null && !used.exists(key);
      final needsDefault = defaultNever || seenDefault;
      switch param {
        case TInst(_.get() => {kind: KTypeParameter(constraints)}, _):
          TypeEmitter.emitType(this, param);
          if (withConstraints && constraints.length > 0) {
            write(' extends ');
            for (c in join(constraints, write.bind(' & ')))
              TypeEmitter.emitType(this, c);
          }
        default:
          TypeEmitter.emitType(this, param);
      }
      if (needsDefault) {
        write(' = never');
        seenDefault = true;
      }
    }
    if (tsxSafe && jsxEmitTsx && params.length == 1)
      write(',');
    write('>');
  }

  function emitTypeParamDeclsTsxSafe(params: Array<Type>,
      withConstraints: Bool) {
    if (params.length == 0)
      return;
    write('<');
    var first = true;
    for (param in params) {
      if (!first)
        write(', ');
      first = false;
      switch param {
        case TInst(_.get() => {kind: KTypeParameter(constraints)}, _):
          TypeEmitter.emitType(this, param);
          if (withConstraints && constraints.length > 0) {
            write(' extends ');
            for (c in join(constraints, write.bind(' & ')))
              TypeEmitter.emitType(this, c);
          }
        default:
          TypeEmitter.emitType(this, param);
      }
    }
    // In TSX files, a single-type-param arrow function needs a trailing comma
    // to disambiguate from JSX (`<T,>(x) => ...`).
    if (jsxEmitTsx && params.length == 1)
      write(',');
    write('>');
  }

  /**
   * Remembers a local's exact emitted TypeScript type when Haxe may erase it.
   *
   * Why: closed enum abstracts can become their primitive backing type in a
   * later expression node even though the local or parameter declaration was
   * already printed as a literal union. Forgetting that declaration makes the
   * expected-type writer add a redundant `as` expression.
   *
   * What: only an explicit declaration-time override or a compiler-derived
   * enum-abstract literal union is recorded. Broad strings and other ordinary
   * locals contribute no fact, so their existing compatibility assertions are
   * preserved.
   *
   * How: Haxe local IDs are stable within one emitted module. Later local reads
   * compare the recorded TypeScript spelling with the expected union before
   * deciding whether an assertion is necessary. This changes TypeScript
   * syntax only; classic JavaScript never uses this emitter state.
   */
  function rememberEmittedLocalType(variable: TVar, haxeType: Type,
      typeOverride: Null<String>): Void {
    final exactType = typeOverride ?? SignatureCache.enumAbstractLiteralUnionTsType(haxeType);
    if (exactType != null)
      localTsTypeOverrides.set(variable.id, exactType);
  }

  override public function emitVar(v: TVar, eo: Null<TypedExpr>) {
    if (eo != null && isJsxCarrierLocal(v.id)) {
      // The linked HXX carrier is compiler-owned scaffolding, not a public
      // application value. Let TypeScript infer its exact recursive object
      // shape instead of widening a synthetic anonymous carrier to `any`.
      write('${localDeclaration(v, true)} ');
      emitLocalVar(v);
      write(' = ');
      emitValue(eo);
      return;
    }
    // Haxe often creates `_g` temporaries while lowering loops. If such a temp
    // is initialized from an optional field already narrowed by a null guard,
    // emit the temp as non-null so generated TS matches the guarded branch.
    final capturedLocalSourceType = SignatureCache.getLocalSourceType(v);
    final declaredType = capturedLocalSourceType ?? v.t;
    final narrowedOptionalInit = eo != null
      && requireTempPlan().tempForLocal(v) != null
      && typeAllowsNull(declaredType)
      && isNarrowedOptionalField(eo);
    final narrowedNonNullInit = eo != null && typeAllowsNull(declaredType)
      && isNarrowedNonNull(eo);
    // TypeArguments.call(...) has already fixed the exact generic result in
    // the emitted call. An unmodified local can safely infer that narrower
    // result instead of reintroducing Haxe's erased backing type. A reassigned
    // local keeps its declared annotation: otherwise TypeScript would freeze
    // the first narrow result and reject a later assignment Haxe accepted.
    final plan = localBindingPlan;
    final inferExplicitCallType = eo != null
      && plan != null
      && !plan.isReassigned(v)
      && ExplicitTypeArguments.infersPreciseLocalType(eo);
    final emittedType = (narrowedOptionalInit || narrowedNonNullInit) ? stripNull(declaredType) : declaredType;
    final emittedTypeOverride = (narrowedOptionalInit
      || narrowedNonNullInit || inferExplicitCallType) ? null : localTsTypeOverride(eo);
    rememberEmittedLocalType(v, emittedType, emittedTypeOverride);
    write('${localDeclaration(v, eo != null)} ');
    emitLocalVar(v);
    if (!inferExplicitCallType) {
      write(': ');
      emitLocalType(emittedType, emittedTypeOverride,
        capturedLocalSourceType != null);
    }
    switch (eo) {
      case null:
      case {expr: TConst(TNull)}:
        if (typeAllowsNull(emittedType)) {
          write(' = null');
        } else {
          // A non-nullable local initialized with `null` is an intentional
          // Haxe pattern for later assignment, commonly used for mutually
          // recursive callbacks. TypeScript's non-null assertion keeps the
          // runtime value as plain `null` without routing through Register.
          write(' = null!');
        }
      case e:
        write(' = ');
        final bridge = boundaryPlan == null ? null : boundaryPlan.initializerBridge(e);
        if (bridge != null) {
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.unsafeCast<');
          TypeEmitter.emitType(this, bridge.target);
          write('>(');
          emitValueWithExpectedType(null, bridge.source);
          write(')');
        } else {
          emitValueWithExpectedType(emittedType, e);
        }
    }
  }

  /**
   * Reuses declaration-time TS literal unions for locals whose Haxe expression
   * type has already widened to the enum abstract's primitive representation.
   *
   * Why: Haxe enum abstracts erase to their underlying primitive in many typed
   * expression positions, so locals such as `final mode: Mode = choose()` or
   * `final mode: Mode = record.mode` can arrive here as `String` even though the
   * declaration that produced the value is emitted as `"a" | "b"`. TypeScript
   * then rejects passing that local to a parameter that still has the literal
   * union type.
   *
   * What: when the initializer is a call to a cached method, a cached class
   * field read, or an anonymous typedef field read, use the cached TS type for
   * the local annotation. The expression itself is unchanged, and classic JS
   * output is unaffected because this logic lives only in the TS emitter.
   *
   * How: `SignatureCache` records enum-abstract literal unions during
   * `onAfterTyping`, before later compiler phases follow abstracts. This helper
   * bridges that declaration-time fact back into local variable emission.
   */
  function localTsTypeOverride(eo: Null<TypedExpr>): Null<String> {
    if (eo == null)
      return null;
    if (isExceptionCaughtUnwrap(eo))
      return '{} | null | undefined';
    return cachedInitializerTsType(eo);
  }

  /**
   * Detects Haxe's lowered representation of typed catch values.
   *
   * Why: source such as `catch (error:MyError)` is lowered by Haxe to one
   * JavaScript catch variable, then `haxe.Exception.caught(raw).unwrap()` plus
   * runtime type guards for each typed catch arm. The lowered temporary has
   * Haxe type `Dynamic`, which would normally emit as TypeScript `any` in the
   * user module.
   *
   * What/How: when a local initializer is exactly the exception unwrap
   * sequence, annotate the local as `{ } | null | undefined`. That is the
   * broadest useful TypeScript surface that can still contain primitive throws,
   * object throws, and nullish throws without spelling `any` or `unknown` in a
   * user module. TypeScript can then narrow the value with the emitted
   * `typeof`/`instanceof` checks before assigning it to the typed catch
   * variable, while arbitrary `Dynamic` values elsewhere keep their normal Haxe
   * semantics.
   */
  static function isExceptionCaughtUnwrap(expr: TypedExpr): Bool {
    return switch unwrapExpr(expr).expr {
      case TCall(unwrapCallee, []) if (isExceptionUnwrapCallee(unwrapCallee)):
        true;
      default:
        false;
    }
  }

  static function isExceptionUnwrapCallee(callee: TypedExpr): Bool {
    return switch unwrapExpr(callee).expr {
      case TField(receiver, field) if (fieldAccessName(field) == 'unwrap'):
        isExceptionCaughtCall(receiver);
      default:
        false;
    }
  }

  static function isExceptionCaughtCall(expr: TypedExpr): Bool {
    return switch unwrapExpr(expr).expr {
      case TCall(caughtCallee, [_]) if (isExceptionCaughtCallee(caughtCallee)):
        true;
      default:
        false;
    }
  }

  static function isExceptionCaughtCallee(callee: TypedExpr): Bool {
    return switch unwrapExpr(callee).expr {
      case TField(_,
        FStatic(_.get() => {module: 'haxe.Exception', name: 'Exception'},
          _.get() => {name: 'caught'})):
        true;
      default:
        false;
    }
  }

  function cachedInitializerTsType(expr: TypedExpr): Null<String> {
    return switch expr.expr {
      case TCall(callee, _):
        cachedCallableReturnTsType(callee);
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        cachedInitializerTsType(inner);
      default:
        cachedFieldValueTsType(expr);
    }
  }

  function cachedCallableReturnTsType(expr: TypedExpr): Null<String> {
    return switch expr.expr {
      case TField(_, FStatic(_.get() => cl, _.get() => field)):
        final sig = SignatureCache.getSig(cl, true, field.name);
        sig == null ? null : sig.retTsType;
      case TField(_, FInstance(_.get() => cl, _, _.get() => field)):
        final sig = SignatureCache.getSig(cl, false, field.name);
        sig == null ? null : sig.retTsType;
      case TField(_, FClosure({c: _.get() => cl}, _.get() => field)):
        final sig = SignatureCache.getSig(cl, false, field.name);
        sig == null ? null : sig.retTsType;
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        cachedCallableReturnTsType(inner);
      default:
        null;
    }
  }

  function cachedCallableArgTsTypes(expr: TypedExpr): Array<Null<String>> {
    return switch expr.expr {
      case TField(_, FStatic(_.get() => cl, _.get() => field)):
        final sig = SignatureCache.getSig(cl, true, field.name);
        sig == null ? [] : [for (arg in sig.args) arg.tsType];
      case TField(_, FInstance(_.get() => cl, _, _.get() => field)):
        final sig = SignatureCache.getSig(cl, false, field.name);
        sig == null ? [] : [for (arg in sig.args) arg.tsType];
      case TField(_, FClosure({c: _.get() => cl}, _.get() => field)):
        final sig = SignatureCache.getSig(cl, false, field.name);
        sig == null ? [] : [for (arg in sig.args) arg.tsType];
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        cachedCallableArgTsTypes(inner);
      default:
        [];
    }
  }

  /**
   * Returns a receiver's retained Haxe source type only when its emitted local
   * kept that contract.
   *
   * A parameter-level `@:ts.type` can deliberately expose a broader host type
   * than Haxe sees. In that case the emitted override, not the nominal Haxe
   * type, controls field reads, so this lookup fails closed and leaves the
   * existing boundary assertion in place.
   */
  function cachedReceiverSourceType(expr: TypedExpr): Null<Type> {
    return switch expr.expr {
      case TLocal(variable):
        receiverHasEmittedTypeOverride(expr) ? null : SignatureCache.getLocalSourceType(variable);
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        cachedReceiverSourceType(inner);
      default:
        null;
    }
  }

  /** Whether target metadata replaced the receiver's emitted local type. */
  function receiverHasEmittedTypeOverride(expr: TypedExpr): Bool {
    return switch expr.expr {
      case TLocal(variable):
        localTsTypeOverrides.exists(variable.id);
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        receiverHasEmittedTypeOverride(inner);
      default:
        false;
    }
  }

  /**
   * Resolves only outer typedef/abstract shells to one expected class owner.
   *
   * A semantic zero-runtime abstract can retain exact source type arguments
   * even when its emitted receiver is the underlying extern class. Applying
   * those arguments to the accessed field proves a value already has the
   * literal union expected by TypeScript and avoids an unnecessary assertion.
   */
  static function sourceInstanceParameters(type: Type, owner: ClassType,
      depth = 0): Null<Array<Type>> {
    if (depth > 64)
      return null;
    return switch type {
      case TInst(reference, parameters): final sourceOwner = reference.get(); sourceOwner.module == owner.module && sourceOwner.name == owner.name ? parameters : null;
      case TType(reference, parameters):
        final alias = reference.get();
        sourceInstanceParameters(alias.type.applyTypeParameters(alias.params,
          parameters), owner,
          depth
          + 1);
      case TAbstract(reference, parameters):
        final abstraction = reference.get();
        sourceInstanceParameters(abstraction.type.applyTypeParameters(abstraction.params,
          parameters),
          owner, depth
          + 1);
      case TLazy(resolve):
        sourceInstanceParameters(resolve(), owner, depth + 1);
      case TMono(reference) if (reference.get() != null):
        sourceInstanceParameters(reference.get(), owner, depth + 1);
      default:
        null;
    }
  }

  function cachedFieldValueTsType(expr: TypedExpr,
      ?expectedTsType: String): Null<String> {
    return switch expr.expr {
      case TField(_, FStatic(_.get() => cl, _.get() => field)):
        switch field.kind {
          case FVar(_, _):
            explicitFieldTsType(field) ?? SignatureCache.getFieldTsType(cl,
              true, field.name);
          default:
            null;
        }
      case TField(receiver,
        FInstance(_.get() => cl, parameters, _.get() => field)):
        switch field.kind {
          case FVar(_, _):
            // A generic field declaration only contains its owner's type
            // parameter, so the declaration cache cannot know the concrete
            // literal union. Apply the receiver's actual parameters first.
            // This proves expressions such as `pair.first` already carry the
            // same exact TS type as `Pair<ClosedDomain>`; no assertion is
            // needed. If substitution cannot recover a literal union, retain
            // the declaration-time cache and its conservative behavior.
            final explicitType = explicitFieldTsType(field);
            if (explicitType != null) {
              explicitType;
            } else if (receiverHasEmittedTypeOverride(receiver)) {
              null;
            } else {
              final sourceParameters = switch cachedReceiverSourceType(receiver) {
                case null: null;
                case source: sourceInstanceParameters(source, cl);
              };
              final effectiveParameters = sourceParameters != null ? sourceParameters : parameters;
              final instantiatedType = effectiveParameters.length == cl.params.length ? field.type.applyTypeParameters(cl.params,
                effectiveParameters) : field.type;
              SignatureCache.enumAbstractLiteralUnionTsType(instantiatedType) ?? SignatureCache.getFieldTsType(cl,
                false, field.name);
            }
          default:
            null;
        }
      case TField(receiver, FAnon(_.get() => field)):
        // Inline abstracts can synthesize an anonymous storage field after the
        // declaration cache was collected. Its typed field still carries the
        // nominal source leaf; use the frozen enum values before falling back
        // to a declaration-position lookup.
        final explicit = explicitFieldTsType(field);
        final cached = SignatureCache.getAnonFieldTsType(field.pos);
        final direct = SignatureCache.enumAbstractLiteralUnionTsType(field.type);
        if (explicit != null) explicit; else
          if (receiverHasEmittedTypeOverride(receiver)) null; else
            if (expectedTsType == null) cached; else
              if (direct == expectedTsType) direct; else
                if (cached == expectedTsType) cached; else cached ?? direct;
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        cachedFieldValueTsType(inner, expectedTsType);
      default:
        null;
    }
  }

  /** Returns a field's authored TS spelling before derived enum provenance. */
  static function explicitFieldTsType(field: ClassField): Null<String> {
    return extractStringMeta(field.meta,
      ':ts.type') ?? extractStringMeta(field.meta, ':genes.type');
  }

  function emitLocalType(type: Type, typeOverride: Null<String>,
      capturedSourceType = false): Void {
    if (typeOverride != null)
      write(typeOverride);
    else if (capturedSourceType)
      TypeEmitter.emitCapturedSourceType(this, type);
    else
      TypeEmitter.emitType(this, type);
  }

  override function emitValueWithExpectedType(expected: Null<Type>,
      expr: TypedExpr) {
    final expectedTsType = expected == null ? null : SignatureCache.enumAbstractLiteralUnionTsType(expected);
    if (expectedTsType != null
      && needsEnumAbstractExpectedAssertion(expectedTsType, expr)) {
      write('(');
      emitValue(expr);
      write(' as ');
      write(expectedTsType);
      write(')');
      return;
    }
    super.emitValueWithExpectedType(expected, expr);
  }

  /**
   * Re-applies closed enum-abstract parameter types after Haxe lowers values to
   * their primitive runtime representation.
   *
   * Haxe can lower `for (id in [A, B]) consume(id)` to locals initialized from
   * primitive string literals. Those locals are still Haxe-typed as the enum
   * abstract at the call boundary, but TS only sees `string`. A tiny TS
   * assertion at the expected-type boundary preserves the source contract
   * without globally narrowing mutable local declarations.
   */
  function needsEnumAbstractExpectedAssertion(expectedTsType: String,
      expr: TypedExpr): Bool {
    final unwrapped = unwrapExpr(expr);
    switch unwrapped.expr {
      case TConst(TString(_) | TInt(_) | TFloat(_) | TBool(_) | TNull):
        return false;
      case TLocal(v):
        if (localTsTypeOverrides.get(v.id) == expectedTsType)
          return false;
      case TCall(callee, _):
        if (cachedCallableReturnTsType(callee) == expectedTsType)
          return false;
      case TField(_, _):
        if (cachedFieldValueTsType(unwrapped, expectedTsType) == expectedTsType)
          return false;
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        return needsEnumAbstractExpectedAssertion(expectedTsType, inner);
      default:
    }
    return true;
  }

  static function typeAllowsNull(t: Type): Bool {
    return NullishContract.forType(t).haxeAllowsNull;
  }

  static function stripNull(t: Type): Type {
    return NullishContract.stripHaxeNull(t);
  }

  static function isNumberLike(t: Type): Bool {
    return switch haxe.macro.Context.followWithAbstracts(stripNull(t)) {
      case TAbstract(_.get() => {pack: [], name: "Int" | "Float"}, _): true;
      default: false;
    }
  }

  static function isVoidLike(t: Type): Bool {
    return switch haxe.macro.Context.followWithAbstracts(t) {
      case TAbstract(_.get() => {pack: [], name: "Void"}, _):
        true;
      case TInst(_.get() => {module: "js.lib.Promise", name: "Promise"},
        [inner]) |
        TInst(_.get() => {pack: ["js", "lib"], name: "Promise"}, [inner]):
        isVoidLike(inner);
      case TType(_.get() => {module: "js.lib.Promise", name: "Promise"},
        [inner]) |
        TType(_.get() => {pack: ["js", "lib"], name: "Promise"}, [inner]):
        isVoidLike(inner);
      default:
        false;
    }
  }

  /**
   * Why: Haxe's `js.lib.Promise.resolve(null)` can type through the stdlib
   * `ThenableStruct<T>` overload, even though native TypeScript accepts the
   * plain `null` argument and infers the resolved promise type itself.
   *
   * What/How: when the only reason to insert a `Promise.resolve(null)` cast is
   * that Haxe chose one of the stdlib thenable overload shapes
   * (`js.lib.Thenable<T>`, older `ThenableStruct<T>`, or a union containing
   * one), let the argument emit directly in that call's emission context. This
   * keeps generated TS idiomatic (`Promise.resolve(null)`) and avoids leaking
   * an imported helper alias or `PromiseLike<any>` assertion into user modules.
   * Ordinary `Thenable<T>` parameters still keep their strict null assertions.
   */
  static function isPromiseThenableType(t: Type): Bool {
    return switch t {
      case TAbstract(_.get() => {pack: ["js", "lib"], name: "Thenable"}, _):
        true;
      case TType(_.get() => {pack: ["js", "lib"], name: "ThenableStruct"}, _):
        true;
      case TAbstract(_.get() => {pack: ["haxe", "extern"], name: "EitherType"},
        [left, right]): isPromiseThenableType(left) || isPromiseThenableType(right);
      case TMono(tref): final inner = tref.get(); inner != null && isPromiseThenableType(inner);
      case TType(_, _):
        isPromiseThenableType(haxe.macro.Context.follow(t));
      default:
        false;
    }
  }

  static function isJsPromiseResolveCallee(callee: TypedExpr): Bool {
    return switch unwrapExpr(callee).expr {
      case TField(_, f = FStatic(_.get() => cl, _)): (cl.module == 'js.lib.Promise'
          || (cl.pack.join('.') == 'js.lib' && cl.name == 'Promise')) && fieldAccessName(f) == 'resolve';
      default:
        false;
    }
  }

  function typeToString(type: Type): String {
    final buf = new StringBuf();
    final noop = function() {};
    final writer = {
      write: (code: String) -> buf.add(code),
      writeNewline: noop,
      emitComment: (_: String) -> {},
      increaseIndent: noop,
      decreaseIndent: noop,
      emitPos: (_: Dynamic) -> {},
      includeType: (_: Type) -> {},
      typeAccessor: ctx.typeAccessor,
      typeParameterName: parameter -> typeParameterName(parameter)
    }
    TypeEmitter.emitType(writer, type);
    return buf.toString();
  }

  static function addChainedAccessReceiverParens(e: TypedExpr): TypedExpr {
    function loop(e: TypedExpr): TypedExpr
      return switch e.expr {
        case TCast(e1, null) | TMeta(_, e1):
          loop(e1);
        case TConst(TInt(_) | TFloat(_)) | TObjectDecl(_):
          TypeUtil.with(e, TParenthesis(e));
        case _:
          e;
      }
    return loop(e);
  }

  function emitTsFieldAccess(field: FieldAccess) {
    switch field {
      case FStatic(_.get() => c, _):
        emitStaticField(c, TypeUtil.fieldName(field));
      case FEnum(_), FInstance(_), FAnon(_), FDynamic(_), FClosure(_):
        emitField(TypeUtil.fieldName(field));
    }
  }

  function emitChainedAccessReceiver(receiver: TypedExpr, assertNonNull: Bool) {
    final value = addChainedAccessReceiverParens(receiver);
    final wrapRawSyntax = TypeUtil.rawSyntaxReceiverNeedsParens(value);

    if (assertNonNull)
      write('(');
    if (wrapRawSyntax)
      write('(');

    if (assertNonNull) {
      // The following member/index access asserts the receiver is present, so
      // suppress TS-only optional-field `?? null` normalization for this inner
      // value and apply the usual Haxe non-null receiver assertion instead.
      withoutOptionalFieldNullNormalization(() ->
        emitValueWithExpectedType(null, value));
    } else {
      emitValue(value);
    }

    if (wrapRawSyntax)
      write(')');
    if (assertNonNull)
      write('!)');
  }

  function emitArrayAccess(e: TypedExpr, receiver: TypedExpr,
      index: TypedExpr) {
    final contract = NullishContract.forType(e.t);
    final normalizeResult = !inAssignTarget && !contract.preservesUndefined
      && typeAllowsNull(e.t);
    final assertTypedResult = !inAssignTarget
      && !contract.preservesUndefined && !typeAllowsNull(e.t);
    if (normalizeResult)
      write('(');
    if (TypeUtil.rawSyntaxReceiverNeedsParens(receiver)) {
      // Preserve the dedicated raw-syntax precedence repair that originally
      // owned this path. Ordinary indexing stays with the base emitter so its
      // source positions, comments, and assignment rendering remain stable.
      emitChainedAccessReceiver(receiver, typeAllowsNull(receiver.t));
      write('[');
      emitValue(index);
      write(']');
    } else {
      super.emitExpr(e);
    }
    if (normalizeResult)
      write(' ?? null)');
    else if (assertTypedResult)
      write('!');
  }

  override public function emitValue(e: TypedExpr) {
    // Emit only the carried value while its exact generic witness is in scope.
    final explicitTypeArgumentCall = ExplicitTypeArguments.callSiteMarker(e);
    if (explicitTypeArgumentCall != null) {
      final previous = currentExplicitTypeArguments;
      currentExplicitTypeArguments = explicitTypeArgumentCall.arguments;
      emitValue(explicitTypeArgumentCall.value);
      currentExplicitTypeArguments = previous;
      return;
    }
    if (inRawSyntaxTemplate) {
      super.emitValue(e);
      return;
    }

    emitExpressionPos(e);
    final privateMethod = privateMethodCall(e);
    if (privateMethod != null) {
      emitPrivateMethodValue(privateMethod);
      return;
    }
    switch e.expr {
      case TCall({
        expr: TField(_,
          FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))
      },
        [{expr: TConst(TString("undefined"))}])
        if (shouldNormalizeUndefinedToNull(e.t)):
        // See `emitExpr` for rationale.
        write('null');
      case TCall({
        expr: TField(_,
          FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))
      }, args) if (emitSyntaxCodeWithArgs(args)):
        null;
      case TCall(callee = {expr: TField(target, f)}, params)
        if (fieldAccessName(f) == "get" && tsIsIMapType(target.t)
          && isNarrowedNonNull(e)):
        emitCall(callee, params, true);
        write('!');
      case TCall(callee = {expr: TField(target, f)}, params)
        if (fieldAccessName(f) == "get" && tsIsIMapType(target.t)
          && nativeMapReadNeedsAssertion(e)):
        // Haxe's non-null-safe type system can place `Null<V>` into a proven or
        // otherwise non-null destination. Preserve that typed-AST decision as
        // a local TS assertion while leaving unconstrained Map.get reads
        // honestly nullable at the public boundary.
        emitCall(callee, params, true);
        write('!');
      case TBinop(op = OpGt | OpGte | OpLt | OpLte, e1, e2)
        if ((typeAllowsNull(e1.t) && isNumberLike(e1.t))
          || (typeAllowsNull(e2.t) && isNumberLike(e2.t))):
        // See `emitExpr` for rationale.
        inline function emitOperand(expr: TypedExpr) {
          if (typeAllowsNull(expr.t) && isNumberLike(expr.t)) {
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.unsafeCast<number>(');
            emitValue(expr);
            write(')');
          } else {
            emitValue(expr);
          }
        }
        emitOperand(e1);
        writeSpace();
        writeBinop(op);
        writeSpace();
        emitOperand(e2);
      case TIf(cond, thenExpr, elseExpr):
        final expected = currentExpectedValueType;
        emitValue(cond);
        write(' ? ');
        emitValueWithExpectedType(expected, thenExpr);
        write(' : ');
        switch elseExpr {
          case null:
            write('null');
          case branch:
            emitValueWithExpectedType(expected, branch);
        }
      case TField(_, field)
        if (StdlibTypeOverrides.needsArrayBufferAssertion(e.t, field)):
        // Haxe's 4.3.7 extern guarantees ArrayBuffer here; TS6+ widens an
        // unparameterized typed array's property to ArrayBufferLike.
        write('(');
        super.emitValue(e);
        write(' as ArrayBuffer)');
      case TField(_, f) if (isOptionalField(f) && isNarrowedOptionalField(e)):
        emitNarrowedOptionalField(e);
      case TField(_, f)
        if (!inAssignTarget
          && isOptionalField(f)
          && !suppressOptionalFieldNullNormalization
          && shouldNormalizeOptionalFieldRead(e)):
        emitOptionalFieldAsNull(e);
      case TBlock(_):
        super.emitValue(e);
      default:
        super.emitValue(e);
    }
  }

  override public function emitExpr(e: TypedExpr) {
    // Statement-position calls need the same erasure and scoped witness.
    final explicitTypeArgumentCall = ExplicitTypeArguments.callSiteMarker(e);
    if (explicitTypeArgumentCall != null) {
      final previous = currentExplicitTypeArguments;
      currentExplicitTypeArguments = explicitTypeArgumentCall.arguments;
      emitExpr(explicitTypeArgumentCall.value);
      currentExplicitTypeArguments = previous;
      return;
    }
    if (CompilerInternal.isSideEffectImportMarkerCall(e))
      return;
    if (inRawSyntaxTemplate) {
      super.emitExpr(e);
      return;
    }

    emitExpressionPos(e);
    switch e.expr {
      case TBlock(el):
        write('{');
        increaseIndent();
        for (element in el)
          emitBlockElement(element);
        decreaseIndent();
        writeNewline();
        write('}');
      case TLocal(v):
        emitLocalVar(v);
      case TObjectDecl(fields):
        emitObjectDeclWithFieldTypes(e, fields);
      case TNew(c, params, values)
        if (boundaryPlan != null && boundaryPlan.constructor(e) != null):
        final decision = boundaryPlan.constructor(e);
        write(switch c.get().constructor {
          case null: 'new ';
          case _.get() => ctor if (ctor.meta.has(':selfCall')): '';
          default: 'new ';
        });
        write(ctx.typeAccessor(TClassDecl(c)));
        if (params.length > 0 && params.exists(typeUsesTypeParameter))
          TypeEmitter.emitParams(this, params, false);
        write('(');
        for (index in 0...values.length) {
          if (index > 0)
            write(', ');
          final expected = index < decision.argumentTypes.length ? decision.argumentTypes[index] : null;
          final bridge = decision.bridgeAt(index);
          if (bridge == null) {
            emitValueWithExpectedType(expected, values[index]);
          } else {
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.unsafeCast<');
            TypeEmitter.emitType(this, bridge.target);
            write('>(');
            emitValueWithExpectedType(null, bridge.source);
            write(')');
          }
        }
        write(')');
      case TNew(c, params, values)
        if (params.length > 0 && params.exists(typeUsesTypeParameter)):
        // Constructor inference cannot recover outer method/class parameters
        // from a polymorphic function argument (`new LazyFunc(Empty.make)` is a
        // common example). The typed AST already contains the exact
        // instantiation, so print it only when it references an in-scope type
        // parameter and inference would otherwise be lossy.
        write(switch c.get().constructor {
          case null: 'new ';
          case _.get() => ctor if (ctor.meta.has(':selfCall')): '';
          default: 'new ';
        });
        write(ctx.typeAccessor(TClassDecl(c)));
        TypeEmitter.emitParams(this, params, false);
        write('(');
        for (value in join(values, write.bind(', ')))
          emitValue(value);
        write(')');
      case TCall({
        expr: TField(_,
          FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))
      },
        [{expr: TConst(TString("undefined"))}])
        if (shouldNormalizeUndefinedToNull(e.t)):
        // Haxe stdlib sometimes uses `js.Syntax.code("undefined")` in places
        // where `null` is the intended "no value" signal (e.g. `HxOverrides.cca`).
        // Normalize to `null` to keep TS `strictNullChecks` consistent.
        write('null');
      case TCall({
        expr: TField(_,
          FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))
      }, args) if (emitSyntaxCodeWithArgs(args)):
        null;
      case TConst(TNull):
        if (typeAllowsNull(e.t)
          || (suppressPromiseResolveNullThenableCast
            && isPromiseThenableType(e.t))) {
          write('null');
        } else {
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.unsafeCast<');
          TypeEmitter.emitType(this, e.t);
          write('>(null)');
        }
      case TCast(e1, null):
        // Haxe inserts implicit casts in a few places where its non-null-safe
        // type system differs from TS strict null checks. Preserve those casts
        // as TS-only assertions (no runtime effect).
        // If the cast target is `any`, emitting `unsafeCast<any>(...)` would
        // leak `any` into user modules. For `any`, the cast is a no-op in TS
        // anyway, so omit it.
        final nullThenableCast = suppressPromiseResolveNullThenableCast
          && isNullConst(unwrapExpr(e1)) && isPromiseThenableType(e.t);
        // In the scoped `Promise.resolve(null)` path, TypeScript can choose its
        // value overload naturally, so Haxe's internal thenable-overload cast
        // would only make the generated code noisier and harder to import.
        if (typeEmitsAny(e.t) || nullThenableCast
          || (!typeAllowsNull(e.t) && typeAllowsNull(e1.t)
            && isNarrowedNonNull(e1))) {
          emitValue(e1);
        } else {
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.unsafeCast<');
          TypeEmitter.emitType(this, e.t);
          write('>(');
          emitValue(e1);
          write(')');
        }
      case TBinop(op = OpAssign, lhs = {expr: TField(_, f)}, rhs)
        if (isOverriddenField(f)):
        inAssignTarget = true;
        emitValue(lhs);
        inAssignTarget = false;
        writeSpace();
        writeBinop(op);
        writeSpace();
        final meta = switch f {
          case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf): cf.get()
              .meta;
          default: null;
        }
        final typeOverride = extractStringMeta(meta,
          ':ts.type') ?? extractStringMeta(meta, ':genes.type');
        // If the override is `any`, no cast is required and emitting `<any>`
        // would leak `any` into user modules.
        if (typeOverride == null || typeOverride == 'any') {
          emitValueWithExpectedType(lhs.t, rhs);
        } else {
          write(ctx.typeAccessor(TypeUtil.registerType));
          write('.unsafeCast<');
          write(typeOverride);
          write('>(');
          emitValueWithExpectedType(lhs.t, rhs);
          write(')');
        }
      case TBinop(op = OpAssign, lhs, rhs)
        if (boundaryPlan != null && boundaryPlan.assignmentBridge(e) != null):
        final bridge = boundaryPlan.assignmentBridge(e);
        inAssignTarget = true;
        emitValue(lhs);
        inAssignTarget = false;
        writeSpace();
        writeBinop(op);
        writeSpace();
        write(ctx.typeAccessor(TypeUtil.registerType));
        write('.unsafeCast<');
        TypeEmitter.emitType(this, bridge.target);
        write('>(');
        emitValueWithExpectedType(null, bridge.source);
        write(')');
      case TBinop(op = OpAssign | OpAssignOp(_), lhs, rhs):
        // Avoid optional-field `?? null` rewrites on assignment targets.
        inAssignTarget = true;
        emitValue(lhs);
        inAssignTarget = false;
        writeSpace();
        writeBinop(op);
        writeSpace();
        emitValueWithExpectedType(lhs.t, rhs);
      case TField(_, f)
        if (!inAssignTarget && isOptionalField(f) && isNarrowedOptionalField(e)):
        emitNarrowedOptionalField(e);
      case TArray(receiver, index):
        // TypeScript widens an indexed Array<T> read to `T | undefined` under
        // `noUncheckedIndexedAccess`, while Haxe's typed AST keeps the declared
        // result `T`. Preserve that Haxe contract with a type-only assertion.
        // Nullable Haxe elements still normalize a missing JavaScript value to
        // `null`, and Undefinable<T> keeps its explicit `undefined` unchanged.
        // Assignment targets receive none of these read-only projections.
        emitArrayAccess(e, receiver, index);
      case TField(x,
        f) // If the receiver type is nullable in TS (`T | null`), TS does not
        // reliably narrow property accesses across statements (e.g. `this.pos`).
        // Add a non-null assertion to preserve Haxe semantics under `strict`.
        //
        // Note: skip dynamic-iterator special cases handled by the JS emitter.
        if (typeAllowsNull(x.t)
          && !(fieldAccessName(f) == "iterator"
            && genes.util.TypeUtil.isDynamicIterator(x))):
        final normalizeOptionalField = !inAssignTarget
          && !suppressOptionalFieldNullNormalization
          && optionalFieldNeedsNullNormalization(f);
        function skip(e: TypedExpr): TypedExpr
          return switch e.expr {
            case TCast(e1, null) | TMeta(_, e1): skip(e1);
            case TConst(TInt(_) | TFloat(_)) | TObjectDecl(_): TypeUtil.with(e,
                TParenthesis(e));
            case _: e;
          }
        if (normalizeOptionalField)
          write('(');
        emitChainedAccessReceiver(skip(x), !isNarrowedNonNull(x));
        emitTsFieldAccess(f);
        if (normalizeOptionalField)
          write(' ?? null)');
      case TField(x, f)
        if (TypeUtil.rawSyntaxReceiverNeedsParens(x)
          && !(fieldAccessName(f) == "iterator"
            && genes.util.TypeUtil.isDynamicIterator(x))):
        final normalizeOptionalField = !inAssignTarget
          && !suppressOptionalFieldNullNormalization
          && optionalFieldNeedsNullNormalization(f);
        if (normalizeOptionalField)
          write('(');
        emitChainedAccessReceiver(x, false);
        emitTsFieldAccess(f);
        if (normalizeOptionalField)
          write(' ?? null)');
      case TField(_, f)
        if (!inAssignTarget && !suppressOptionalFieldNullNormalization
          && optionalFieldNeedsNullNormalization(f)):
        // Optional anonymous structure fields may be absent at runtime (`undefined`)
        // but Haxe treats access as `null` in most contexts. Normalize to `null`
        // to avoid leaking `undefined` into TS types.
        write('(');
        super.emitExpr(e);
        write(' ?? null)');
      case TReturn(eo):
        switch eo {
          case null:
            write('return');
          case e1:
            final ret = currentReturnType;
            final unwrapped = unwrapExpr(e1);
            final isNull = isNullConst(unwrapped)
              || isJsUndefinedConst(unwrapped);
            if (currentReturnIsVoidLike && isNull) {
              // Haxe often uses `null` as the implicit return value for `Void`.
              // In TS, `return null` is not valid for `void` / `Promise<void>`.
              write('return');
            } else {
              write('return ');
              final bridge = boundaryPlan == null ? null : boundaryPlan.returnBridge(e);
              if (bridge != null) {
                write(ctx.typeAccessor(TypeUtil.registerType));
                write('.unsafeCast<');
                TypeEmitter.emitType(this, bridge.target);
                write('>(');
                // Preserve the source expression's own null/undefined
                // projection; the planned identity bridge is a later boundary.
                emitValueWithExpectedType(null, bridge.source);
                write(')');
              } else {
                emitValueWithExpectedType(ret, e1);
              }
            }
        }
      case TCall(fn, args) if (TypeUtil.isNativeArrayRemovalCall(fn)):
          // Array#shift/#pop returns `T | undefined` in TS. When the Haxe code
          // guarantees non-emptiness (e.g. checked `.length > 0`), allow calling
          // the returned function under `strict`.
          write('(');
          emitValue(fn);
          write('!)(');
          for (arg in join(args, write.bind(', ')))
            emitValue(arg);
          write(')');
      case TCall(callee = {expr: TField(target, f)}, params)
        if (fieldAccessName(f) == "get" && tsIsIMapType(target.t)
          && isNarrowedNonNull(e)):
        emitCall(callee, params, true);
        if (typeAllowsNull(e.t))
          write('!');
      case TFor(_, _, _):
        final wasInLoop = inLoop;
        inLoop = true;
        final lowered = requireTempPlan().loweredFor(e);
        final v = lowered.variable;
        final itExpr = lowered.iteratorExpression;
        final body = lowered.body;
        var localIt: Null<TVar> = null;
        var tempIt: Null<String> = null;
        switch lowered.iterator {
          case ExistingIterator(iteratorLocal):
            localIt = iteratorLocal;
          case TemporaryIterator(temp):
            tempIt = temp.name;
            write('$declare ${getLocalIdent(temp.name)} = ');
            emitValue(temp.initializer);
            writeNewline();
        }

        function emitIterator() {
          if (localIt != null)
            emitLocalVar(localIt);
          else
            emitLocalIdent(tempIt);
        }

        write('while (');
        emitIterator();
        write('.hasNext()) {');
        increaseIndent();
        writeNewline();
        write('${localDeclaration(v, true)} ');
        emitLocalVar(v);
        write(' = ');
        emitIterator();
        write('.next()');
        writeNewline();
        emitBlockElement(body);
        decreaseIndent();
        writeNewline();
        write('}');
        inLoop = wasInLoop;
      case TIf(cond, thenExpr, elseExpr):
        write('if ');
        emitValue(cond);
        writeSpace();
        emitExpr(TypeUtil.block(thenExpr));
        switch elseExpr {
          case null:
          case branch:
            emitPos(branch.pos);
            write(' else ');
            emitExpr(switch branch.expr {
              case TIf(_, _, _): branch;
              case _: TypeUtil.block(branch);
            });
        }
      case TTry(etry, [{v: v, expr: ecatch}]):
        write('try ');
        emitExpr(etry);
        write('catch (');
        emitLocalVar(v);
        write(') ');
        emitExpr(ecatch);
      case TTry(_):
        throw 'Unhandled try/catch, please report';
      case TFunction(f):
        final valueIifeDepth = this.valueIifeDepth;
        final inLoop = this.inLoop;
        final prevReturn = currentReturnType;
        final prevVoidLike = currentReturnIsVoidLike;
        currentReturnType = switch e.t {
          case TFun(_, ret): ret;
          default: null;
        }
        currentReturnIsVoidLike = currentReturnType != null
          && isVoidLike(currentReturnType);
        this.valueIifeDepth = 0;
        this.inLoop = false;
        final args = switch e.t {
          case TFun(args, _): args;
          default: [];
        }
        var noOptionalUntil = -1;
        var hadOptional = true;
        for (i in 0...args.length) {
          final arg = args[i];
          if (arg.opt) {
            hadOptional = true;
          } else if (hadOptional && !arg.opt) {
            noOptionalUntil = i;
            hadOptional = false;
          }
        }
        write('function (');
        for (i in joinIt(0...f.args.length, write.bind(', '))) {
          final arg = f.args[i];
          final capturedSourceType = SignatureCache.getLocalSourceType(arg.v);
          final t = capturedSourceType ?? (i < args.length ? args[i].t : arg.v.t);
          if (genes.util.TypeUtil.isRest(t))
            write('...');
          emitLocalVar(arg.v);
          final omitType = (arg.v.name == '_'
            || StringTools.startsWith(arg.v.name, '_'))
            && typeEmitsAny(t);
          if (!omitType) {
            final optional = i < args.length && args[i].opt
              && i > noOptionalUntil;
            final nullish = NullishContract.forParameter(t, optional);
            if (nullish.emitOptionalSyntax && !nullish.usesNullDefault)
              write('?');
            write(': ');
            if (capturedSourceType != null)
              TypeEmitter.emitCapturedSourceType(this, nullish.emittedType);
            else
              TypeEmitter.emitType(this, nullish.emittedType);
            rememberEmittedLocalType(arg.v, nullish.emittedType, null);
            if (nullish.usesNullDefault)
              write(' = null');
          }
        }
        // Omit explicit return annotations so TS can infer and preserve generic
        // inference. Writing `: any` here causes widespread `unknown` inference
        // under `strict` in downstream code (e.g. tink.*).
        write(') ');
        emitExpr(getFunctionBody(f));
        this.valueIifeDepth = valueIifeDepth;
        this.inLoop = inLoop;
        currentReturnType = prevReturn;
        currentReturnIsVoidLike = prevVoidLike;
      case TBinop(op = OpGt | OpGte | OpLt | OpLte, e1, e2)
        if ((typeAllowsNull(e1.t) && isNumberLike(e1.t))
          || (typeAllowsNull(e2.t) && isNumberLike(e2.t))):
        // Relational operators on nullable numbers are allowed in Haxe but
        // rejected by TS `strictNullChecks`. Cast to `number` to preserve JS
        // coercion semantics (`null > 0` is `false`, etc).
        inline function emitOperand(expr: TypedExpr) {
          if (typeAllowsNull(expr.t) && isNumberLike(expr.t)) {
            write(ctx.typeAccessor(TypeUtil.registerType));
            write('.unsafeCast<number>(');
            emitValue(expr);
            write(')');
          } else {
            emitValue(expr);
          }
        }
        emitOperand(e1);
        writeSpace();
        writeBinop(op);
        writeSpace();
        emitOperand(e2);
      case TBinop(op = OpEq | OpNotEq, e1, e2)
        if (isNullConst(e1) || isNullConst(e2)):
        emitValueWithPlainNull(e1);
        writeSpace();
        writeBinop(op);
        writeSpace();
        emitValueWithPlainNull(e2);
      case TCall({expr: TField(_, f)}, [{expr: TConst(TString(name))}])
        if (switch f {
            case FStatic(cl, cf)
              if (cl.get().module == "genes.Register"
                && cl.get().name == "Register" && cf.get().name == "global"):
              true;
            default:
              false;
          }):
          // Avoid leaking `unknown` from `Register.global()` into user modules for
          // common reflection registries.
          switch name {
            case "$hxEnums":
              write(ctx.typeAccessor(TypeUtil.registerType));
              write('.hxEnums()');
            case "$hxClasses":
              write(ctx.typeAccessor(TypeUtil.registerType));
              write('.hxClasses()');
            default:
              super.emitExpr(e);
          }
      default:
        super.emitExpr(e);
    }
  }

  /**
   * Reads the semantic plan instead of inferring control flow while printing.
   *
   * Every current lookup uses an original typed Haxe expression. A focused
   * inventory also covers the default-argument wrappers created later by
   * `getFunctionBody`: those wrappers are emitted, but none is passed to this
   * semantic query. A missing program point is therefore a planning error, not
   * permission to guess. If a future emitter-owned wrapper genuinely needs a
   * lookup, it must carry explicit source provenance before being admitted.
   */
  function isNarrowedNonNull(e: TypedExpr): Bool {
    final plan = narrowingPlan;
    #if genes.ts.narrowing_inventory
    if (plan != null) {
      switch plan.lookupProvenance(e) {
        case PlannedSourceExpression:
          haxe.macro.Context.info("[GTS-NARROW-INVENTORY] planned-source-expression",
            e.pos);
        case MissingSourceProgramPoint:
          haxe.macro.Context.info("[GTS-NARROW-INVENTORY] missing-source-program-point",
            e.pos);
        case EmitterSynthesizedExpression:
          haxe.macro.Context.info("[GTS-NARROW-INVENTORY] emitter-synthesized-expression",
            e.pos);
      }
    }
    #end
    return plan != null && plan.isKnownNonNull(e);
  }

  function isNarrowedOptionalField(e: TypedExpr): Bool {
    return isNarrowedNonNull(e);
  }

  static function tsIsIMapType(t: Type): Bool {
    return TsNarrowingPlan.mapValueType(t) != null;
  }

  static function isOptionalField(f: FieldAccess): Bool {
    final contract = nullishFieldAccessContract(f);
    return contract != null && contract.mayBeOmitted;
  }

  /**
   * Recovers the shared optional-property contract for a typed field access.
   *
   * Why: a bare `@:optional` test is not enough. Ordinary Haxe optionals need
   * `?? null`, while optional `Undefinable<T>` fields must preserve the real
   * JavaScript `undefined` promised by their public type. Keeping this lookup
   * next to access lowering prevents later expression branches from silently
   * reintroducing printer-local nullish policy.
   */
  static function nullishFieldAccessContract(f: FieldAccess): Null<NullishContract> {
    return switch f {
      case FAnon(cf) | FInstance(_, _, cf) | FStatic(_, cf):
        NullishContract.forField(cf.get());
      default:
        null;
    }
  }

  static function nullishFieldContract(e: TypedExpr): Null<NullishContract> {
    return switch unwrapExpr(e).expr {
      case TField(_, f):
        nullishFieldAccessContract(f);
      default:
        null;
    }
  }

  static function optionalFieldNeedsNullNormalization(f: FieldAccess): Bool {
    final contract = nullishFieldAccessContract(f);
    return contract != null && contract.normalizeUndefinedReadToNull;
  }

  function emitNarrowedOptionalField(e: TypedExpr) {
    switch unwrapExpr(e).expr {
      case TField(receiver, f):
        write('(');
        emitValue(receiver);
        switch f {
          case FStatic(_.get() => c, _):
            emitStaticField(c, TypeUtil.fieldName(f));
          case FEnum(_), FInstance(_), FAnon(_), FDynamic(_), FClosure(_):
            emitField(TypeUtil.fieldName(f));
        }
        write('!)');
      default:
        emitValue(e);
    }
  }

  function emitOptionalFieldAsNull(e: TypedExpr) {
    // Re-enter TS expression emission so nested receiver rewrites still apply.
    // The base JS emitter would print `record.child.label ?? null` and skip the
    // TS-only non-null receiver handling needed for strict null checks.
    emitExpr(e);
  }

  function withoutOptionalFieldNullNormalization(emit: Void->Void) {
    final previous = suppressOptionalFieldNullNormalization;
    suppressOptionalFieldNullNormalization = true;
    emit();
    suppressOptionalFieldNullNormalization = previous;
  }

  /**
   * Preserves explicit JavaScript `undefined` inside a shared raw template.
   *
   * The base emitter owns placeholder parsing and resolves every other value
   * through the active target. Only genes-ts needs this override: its ordinary
   * nullable-Haxe path can normalize `undefined` to `null`, while raw syntax is
   * an explicit host-language boundary whose spelling must remain unchanged.
   */
  override public function emitRawSyntaxTemplateValue(value: TypedExpr): Void {
    if (isJsUndefinedConst(value)) {
      // A raw syntax template argument that is explicitly JavaScript
      // `undefined` must stay `undefined`. The ordinary nullable-Haxe
      // normalization to `null` would change nested raw checks such as
      // `js.Syntax.code("({0}) === undefined", Undefinable.absent())`.
      write('undefined');
      return;
    }
    final previous = inRawSyntaxTemplate;
    inRawSyntaxTemplate = false;
    emitValue(value);
    inRawSyntaxTemplate = previous;
  }

  /**
   * Emits object literals while preserving anonymous-field type context.
   *
   * Why: Haxe treats most absent JS values as `null`, so genes-ts normally
   * rewrites `js.Syntax.code("undefined")` to `null` when the expression is
   * nullable. `genes.ts.Undefinable<T>` is the explicit exception: it means the
   * public TypeScript contract is `T | undefined`, not `T | null`.
   *
   * What/How: object-literal fields carry their expected anonymous field type on
   * the enclosing object, not always on the field expression itself. While
   * emitting each field value, record that expected type so the existing
   * undefined-normalization rule can skip Undefinable fields only.
   */
  function emitObjectDeclWithFieldTypes(e: TypedExpr,
      fields: Array<{name: String, expr: TypedExpr}>) {
    write('{');
    final objectType = currentExpectedValueType != null ? currentExpectedValueType : e.t;
    for (field in join(fields, write.bind(', '))) {
      final anonymousField = TypeUtil.anonymousField(objectType, field.name);
      emitPos(field.expr.pos);
      emitString(anonymousField == null ? field.name : TypeUtil.classFieldName(anonymousField));
      write(': ');
      emitObjectDeclFieldValue(anonymousField,
        TypeUtil.anonymousFieldType(objectType, field.name), field.expr);
    }
    write('}');
  }

  function emitObjectDeclFieldValue(field: Null<ClassField>,
      expected: Null<Type>, expr: TypedExpr): Void {
    final nullish = field == null ? null : NullishContract.forField(field);
    if (nullish != null && nullish.normalizeNullWriteToUndefined
      && mayEmitNull(expr)) {
      // `@:ts.optional` keeps Haxe source reads nullable, but the generated TS
      // object-boundary contract is omission/undefined. Normalize only while
      // emitting that marked field so ordinary Haxe optional fields still use
      // null as their source-level missing sentinel.
      write('(');
      emitValueWithExpectedType(expected, expr);
      write(' ?? undefined)');
      return;
    }
    if (expected != null
      && !typeAllowsNull(expected)
      && typeAllowsNull(expr.t)
      && !isNarrowedNonNull(expr)) {
      // Haxe is not null-safe by default and can intentionally place a nullable
      // value into a non-null anonymous field. Preserve the runtime value while
      // making that typed-AST decision explicit to strict TypeScript.
      write('(');
      emitValueWithExpectedType(expected, expr);
      write(')!');
      return;
    }
    emitValueWithExpectedType(expected, expr);
  }

  static function typeUsesTypeParameter(type: Type): Bool {
    final used = new Map<String, Bool>();
    collectUsedTypeParamKeys(type, used);
    return used.keys().hasNext();
  }

  static function mayEmitNull(expr: TypedExpr): Bool {
    return switch expr.expr {
      case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
        mayEmitNull(inner);
      case TConst(TNull):
        true;
      case TConst(_):
        false;
      case TObjectDecl(_) | TArrayDecl(_) | TFunction(_):
        false;
      default:
        typeAllowsNull(expr.t);
    }
  }

  override function emitSwitch(cond: TypedExpr,
      cases: Array<{values: Array<TypedExpr>, expr: TypedExpr}>,
      def: Null<TypedExpr>, leaf: TypedExpr->Void,
      ?leafStartsWithNewline: Bool = true) {
    write('switch ');
    emitValue(cond);
    write(' {');
    increaseIndent();
    writeNewline();
    var hasClause = false;
    // Insert separators before later clauses so the final clause cannot leave
    // eager indentation on a blank line before the closing switch brace.
    function startClause() {
      if (hasClause)
        writeNewline();
      hasClause = true;
    }
    for (c in cases) {
      startClause();
      emitPos(c.expr.pos);
      for (v in c.values) {
        emitPos(v.pos);
        switch v.expr {
          case TConst(TNull):
            write('case null: case undefined:');
          default:
            write('case ');
            emitValue(v);
            write(':');
        }
      }
      // TypeScript/JavaScript `case` clauses do not create lexical scopes by
      // themselves. Wrap each body; NamePlan models these exact child scopes so
      // sibling enum-pattern locals may reuse their source spelling safely.
      write(' {');
      increaseIndent();
      if (!leafStartsWithNewline)
        writeNewline();
      final previousDeclare = declare;
      declare = 'let';
      leaf(c.expr);
      declare = previousDeclare;
      writeNewline();
      write('break;');
      decreaseIndent();
      writeNewline();
      write('}');
    }
    switch def {
      case null:
        // When Haxe proves a switch exhaustive, it often omits a `default` case.
        // In TS mode, a missing `default` can cause inferred return types to
        // include `undefined`, breaking assignability for callbacks (e.g. `Next.ofSafe`).
        // If any branch returns, add a default that throws to keep TS happy
        // without changing the successful-path semantics.
        if (cases.exists(c -> hasReturnExpr(c.expr))) {
          startClause();
          emitPos(cond.pos);
          write('default: {');
          increaseIndent();
          writeNewline();
          write('throw ');
          emitString('unreachable');
          write(';');
          decreaseIndent();
          writeNewline();
          write('}');
        }
      case e:
        startClause();
        emitPos(e.pos);
        write('default: {');
        increaseIndent();
        if (!leafStartsWithNewline)
          writeNewline();
        leaf(e);
        decreaseIndent();
        writeNewline();
        write('}');
    }
    decreaseIndent();
    writeNewline();
    write('}');
  }

  static function hasReturnExpr(e: TypedExpr): Bool {
    var found = false;
    function visit(e: TypedExpr) {
      if (found)
        return;
      switch e.expr {
        case TReturn(_):
          found = true;
        case TFunction(_):
          // Returns in nested functions do not affect the outer switch.
        default:
          e.iter(visit);
      }
    }
    visit(e);
    return found;
  }

  static function fieldAccessName(field: FieldAccess): Null<String> {
    return switch field {
      case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf):
        TypeUtil.classFieldName(cf.get());
      case FDynamic(name): name;
      default: null;
    }
  }

  function privateMethodCall(e: TypedExpr): Null<PrivateMethodCall> {
    return switch unwrapExpr(e).expr {
      case TField(_, FInstance(_, _, _)):
        null;
      case TField(_, FStatic(owner, cf)):
        final ownerType = owner.get();
        final field = cf.get();
        if (!canLowerPrivateStaticClassField(ownerType, field)) null; else {
          owner: ownerType,
          field: field,
          receiver: null
        };
      default:
        null;
    }
  }

  function isCurrentClass(cl: ClassType): Bool {
    return currentClass != null && cl.module == currentClass.module
      && cl.name == currentClass.name;
  }

  static function canLowerPrivateMethods(cl: ClassType): Bool {
    // Keep this opt-in while Genes still supports class-shaped JS output by
    // default. Downstreams that require clean declaration surfaces can opt
    // specific private static source helpers into unexported module functions
    // without changing broad class, stdlib/js support, or extern runtime
    // shapes. Instance helper lowering needs separate accessor/generic/method
    // value coverage before it can be safely enabled.
    return haxe.macro.Context.defined('genes.ts.lower_private_helpers')
      && !cl.isExtern
      && (cl.pack.length == 0 || (cl.pack[0] != 'haxe' && cl.pack[0] != 'js'));
  }

  static function canLowerPrivateStaticGenesField(cl: ClassType,
      field: GenesField): Bool {
    return field.isStatic
      && canLowerPrivateStaticFieldMeta(cl, field.name, field.isPublic,
        field.kind.equals(Method), field.meta);
  }

  static function canLowerPrivateStaticClassField(cl: ClassType,
      field: ClassField): Bool {
    return canLowerPrivateStaticFieldMeta(cl, field.name, field.isPublic,
      field.kind.match(FMethod(_)), field.meta);
  }

  static function canLowerPrivateStaticFieldMeta(cl: ClassType, name: String,
      isPublic: Bool, isMethod: Bool, meta: Null<MetaAccess>): Bool {
    return canLowerPrivateMethods(cl)
      && !isPublic
      && name != 'main'
      && isMethod
      && meta != null
      && (meta.has(':genesLowerPrivateHelper')
        || meta.has('genesLowerPrivateHelper')
        || meta.has(':genes.lowerPrivateHelper')
        || meta.has('genes.lowerPrivateHelper'));
  }

  function emitPrivateMethodCall(call: PrivateMethodCall,
      params: Array<TypedExpr>) {
    if (isCurrentClass(call.owner)) {
      write(privateMethodHelperName(call.owner,
        TypeUtil.classFieldName(call.field)));
      switch call.receiver {
        case null:
          write('(');
          for (param in join(params, write.bind(', ')))
            emitValue(param);
          write(')');
        case receiver:
          write('.call(');
          emitValue(receiver);
          if (params.length > 0)
            write(', ');
          for (param in join(params, write.bind(', ')))
            emitValue(param);
          write(')');
      }
    } else {
      emitPrivateMethodRuntimeAccess(call);
      write('(');
      for (param in join(params, write.bind(', ')))
        emitValue(param);
      write(')');
    }
  }

  function emitPrivateMethodValue(call: PrivateMethodCall) {
    if (isCurrentClass(call.owner)) {
      write(privateMethodHelperName(call.owner,
        TypeUtil.classFieldName(call.field)));
      switch call.receiver {
        case null:
        case receiver:
          write('.bind(');
          emitValue(receiver);
          write(')');
      }
    } else {
      emitPrivateMethodRuntimeAccess(call);
    }
  }

  function emitPrivateMethodRuntimeAccess(call: PrivateMethodCall) {
    write(ctx.typeAccessor(TypeUtil.registerType));
    write('.unsafeCast<{');
    emitMemberName(TypeUtil.classFieldName(call.field));
    write(': ');
    emitType(call.field.type);
    write('}>(');
    switch call.receiver {
      case null:
        write(ctx.typeAccessor((call.owner : BaseType)));
      case receiver:
        emitValue(receiver);
    }
    write(')');
    emitField(TypeUtil.classFieldName(call.field));
  }

  static function privateMethodHelperName(cl: ClassType,
      fieldName: String): String {
    return genes.ModuleFunctionPlan.privateHelperName(cl, fieldName);
  }

  static function shouldEmitClassMethod(cl: ClassType,
      field: GenesField): Bool {
    return field.isPublic
      || field.kind.equals(Constructor)
      || !field.isStatic
      || !canLowerPrivateStaticGenesField(cl, field)
      || !canLowerPrivateMethods(cl);
  }

  static function isPrivateStaticMain(field: GenesField): Bool {
    return field.isStatic && field.name == 'main' && field.kind.equals(Method);
  }

  static function moduleFieldName(field: GenesField): String {
    final native = TypeUtil.nativeName(field.meta);
    return native != null ? native : field.name;
  }

  static function isOverriddenField(field: FieldAccess): Bool {
    final meta = switch field {
      case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf): cf.get().meta;
      default: null;
    }
    if (meta == null)
      return false;
    return meta.has(':ts.type') || meta.has(':genes.type');
  }

  static inline function isNullConst(e: TypedExpr): Bool
    return switch e.expr {
      case TConst(TNull): true;
      default: false;
    }

  static inline function isJsUndefinedConst(e: TypedExpr): Bool
    return switch unwrapExpr(e).expr {
      case TCall({
        expr: TField(_,
          FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))
      }, [{expr: TConst(TString("undefined"))}]): true;
      default: false;
    }

  function emitValueWithPlainNull(e: TypedExpr) {
    switch e.expr {
      case TConst(TNull):
        write('null');
      case _ if (TypeUtil.nullComparisonOperandNeedsParens(e)):
        write('(');
        emitValue(e);
        write(')');
      default:
        emitValue(e);
    }
  }

  override public function emitConstant(c: TConstant)
    switch (c) {
      case TNull:
        write('null');
      default:
        super.emitConstant(c);
    }

  function emitForwardArgs(f: TFunc, field: GenesField) {
    switch field.type {
      case TFun(args, _):
        for (i in 0...args.length) {
          if (i > 0)
            write(', ');
          final arg = args[i];
          if (genes.util.TypeUtil.isRest(arg.t))
            write('...');
          emitLocalVar(f.args[i].v);
        }
      default:
    }
  }

  function emitTypedFunctionArguments(f: TFunc, field: GenesField,
      emitNullDefaults = true) {
    emitTypedFunctionArgumentsWithType(f, field, null, emitNullDefaults);
  }

  function emitTypedFunctionArgumentsWithType(f: TFunc, field: GenesField,
      declaredType: Null<Type>, emitNullDefaults = true) {
    final effectiveType = declaredType != null ? declaredType : field.type;
    final cachedSig = (currentClass != null) ? SignatureCache.getSig(currentClass,
      field.isStatic, field.name) : null;
    switch effectiveType {
      case TFun(args, _):
        final cachedArgs = (cachedSig != null
          && cachedSig.args.length == args.length) ? cachedSig.args : null;
        // Handle Haxe optional argument skipping semantics (same as TypeEmitter.emitArgs).
        var noOptionalUntil = -1;
        var hadOptional = true;
        for (i in 0...args.length) {
          final arg = args[i];
          final opt = cachedArgs != null ? cachedArgs[i].opt : arg.opt;
          if (opt) {
            hadOptional = true;
          } else if (hadOptional && !opt) {
            noOptionalUntil = i;
            hadOptional = false;
          }
        }

        for (i in genes.util.IteratorUtil.joinIt(0...args.length,
          write.bind(', '))) {
          final arg = args[i];
          final cachedSourceType = cachedArgs != null ? cachedArgs[i].sourceType : null;
          final argType = cachedSourceType ?? ((i >= 0 && i < f.args.length) ? f.args[i].v.t : arg.t);
          final opt = cachedArgs != null ? cachedArgs[i].opt : arg.opt;
          if (genes.util.TypeUtil.isRest(arg.t))
            write('...');
          emitLocalVar(f.args[i].v);
          final optional = opt && i > noOptionalUntil;
          final nullish = NullishContract.forParameter(argType, optional);
          final usesNullDefault = optional
            && (cachedArgs != null ? (cachedArgs[i].allowsNull
              && !cachedArgs[i].preservesUndefined) : nullish.usesNullDefault);
          if (nullish.emitOptionalSyntax
            && (!usesNullDefault || !emitNullDefaults))
            write('?');
          write(': ');
          final cachedType = cachedArgs != null ? cachedArgs[i].tsType : null;
          final emittedArgType = emitArgTsType(field, f, i,
            nullish.emittedType, cachedType, cachedSourceType != null);
          rememberEmittedLocalType(f.args[i].v, nullish.emittedType,
            emittedArgType);
          if (usesNullDefault && emitNullDefaults)
            write(' = null');
        }
      default:
        // Fallback: keep old behavior.
        emitFunctionArguments(f);
    }
  }

  function emitCtorImplementationArguments(f: TFunc, field: GenesField) {
    // Avoid TS override checks across the prototype chain:
    // constructors are not overrides in Haxe, but Genes' runtime uses the same
    // `[Register.new]` key for initialization.
    switch field.type {
      case TFun(args, _):
        for (i in genes.util.IteratorUtil.joinIt(0...args.length,
          write.bind(', '))) {
          final arg = args[i];
          if (genes.util.TypeUtil.isRest(arg.t))
            write('...');
          emitLocalVar(f.args[i].v);
          if (!genes.util.TypeUtil.isRest(arg.t))
            write('?');
          write(': ');
          if (genes.util.TypeUtil.isRest(arg.t))
            write('any[]');
          else
            write('any');
        }
      default:
        emitFunctionArguments(f);
    }
  }

  /**
   * Emits one parameter annotation and returns its exact known TS spelling.
   *
   * Why: parameter metadata has priority over the declaration cache. Returning
   * the spelling chosen here prevents later expression emission from claiming
   * that a broad `string` parameter was actually declared as a closed literal
   * union. A `null` result means the ordinary Haxe type emitter owned a shape
   * that this narrow enum-provenance check does not need to remember.
   */
  function emitArgTsType(field: GenesField, f: TFunc, index: Int, type: Type,
      fallbackType: Null<String>, capturedSourceType = false): Null<String> {
    // TS `strict` enables `useUnknownInCatchVariables`, so catch variables are
    // `unknown`. Avoid emitting `Register.unsafeCast<any>(...)` in user modules
    // by making `haxe.Exception.caught` accept `unknown` in TS.
    if (currentClass != null
      && currentClass.module == 'haxe.Exception'
      && currentClass.name == 'Exception'
      && field.name == 'caught'
      && index == 0) {
      write('unknown');
      return 'unknown';
    }

    // haxe.Exception/ValueException are part of the JS runtime surface.
    //
    // In Haxe, `native: Any` can represent arbitrary thrown values. In TS, the
    // closest semantic match is `unknown` (safe top type), not `any`.
    if (currentClass != null) {
      if (currentClass.module == 'haxe.Exception'
        && currentClass.name == 'Exception'
        && field.kind.equals(Constructor)
        && index == 2) {
        write('unknown | null');
        return 'unknown | null';
      }
      if (currentClass.module == 'haxe.Exception'
        && currentClass.name == 'Exception'
        && field.isStatic
        && field.name == 'thrown'
        && index == 0) {
        write('unknown');
        return 'unknown';
      }
      if (currentClass.module == 'haxe.ValueException'
        && currentClass.name == 'ValueException') {
        if (field.kind.equals(Constructor) && index == 0) {
          write('unknown');
          return 'unknown';
        }
        if (field.kind.equals(Constructor) && index == 2) {
          write('unknown | null');
          return 'unknown | null';
        }
      }
    }

    // Param-level override (preferred): @:ts.type / @:genes.type on the argument var meta.
    final argMeta = f.args[index].v.meta;
    final typeOverride = switch argMeta.extract(':ts.type') {
      case [{params: [{expr: EConst(CString(typeOverride))}]}]:
        typeOverride;
      default:
        switch argMeta.extract(':genes.type') {
          case [{params: [{expr: EConst(CString(typeOverride))}]}]:
            typeOverride;
          default:
            null;
        }
    };
    if (typeOverride != null) {
      write(typeOverride);
      return typeOverride;
    }
    if (fallbackType != null) {
      write(fallbackType);
      return fallbackType;
    }
    if (capturedSourceType)
      TypeEmitter.emitCapturedSourceType(this, type);
    else
      emitType(type);
    return SignatureCache.enumAbstractLiteralUnionTsType(type);
  }

  function emitReturnTsType(field: GenesField, f: TFunc,
      declaredType: Null<Type>) {
    final returnOverride = field.meta != null ? (switch extractStringMeta(field.meta,
      ':ts.returnType') {
      case null: extractStringMeta(field.meta, ':genes.returnType');
      case v: v;
    }) : null;
    if (returnOverride != null) {
      write(returnOverride);
      return;
    }
    final cachedSig = (currentClass != null) ? SignatureCache.getSig(currentClass,
      field.isStatic, field.name) : null;
    if (cachedSig != null && cachedSig.retTsType != null) {
      write(cachedSig.retTsType);
      return;
    }
    if (cachedSig != null && cachedSig.retSourceType != null) {
      TypeEmitter.emitCapturedSourceType(this, cachedSig.retSourceType);
      return;
    }

    if (currentClass != null && currentClass.module == 'haxe.Exception'
      && currentClass.name == 'Exception') {
      if (field.isStatic && field.name == 'thrown') {
        write('unknown');
        return;
      }
      if (!field.isStatic && field.name == 'get_native') {
        write('unknown');
        return;
      }
    }
    emitType(f.t);
  }

  function emitFieldTsType(field: GenesField) {
    final nullish = NullishContract.forProperty(field.type, field.meta);
    if (field.tsType != null) {
      TypeEmitter.emitNullishProjection(this, nullish,
        () -> write(field.tsType), true);
      return;
    }

    final cachedFieldSourceType = currentClass == null ? null : SignatureCache.getFieldSourceType(currentClass,
      field.isStatic, field.name);
    if (cachedFieldSourceType != null) {
      TypeEmitter.emitNullishProjection(this, nullish,
        () -> TypeEmitter.emitCapturedSourceType(this, cachedFieldSourceType),
        true);
      return;
    }

    final cachedFieldType = currentClass == null ? null : SignatureCache.getFieldTsType(currentClass,
      field.isStatic, field.name);
    if (cachedFieldType != null) {
      TypeEmitter.emitNullishProjection(this, nullish,
        () -> write(cachedFieldType), true);
      return;
    }

    if (currentClass != null) {
      if (currentClass.module == 'haxe.Exception'
        && currentClass.name == 'Exception') {
        switch field.name {
          case 'native' | '__nativeException':
            TypeEmitter.emitNullishProjection(this, nullish,
              () -> write('unknown'));
            return;
          default:
        }
      }
      if (currentClass.module == 'haxe.ValueException'
        && currentClass.name == 'ValueException' && field.name == 'value') {
        TypeEmitter.emitNullishProjection(this, nullish,
          () -> write('unknown'));
        return;
      }
    }
    TypeEmitter.emitNullishProjection(this, nullish,
      () -> emitType(nullish.emittedType,
        field.isStatic ? null : field.params));
  }

  function emitTsInterface(cl: ClassType, params: Array<Type>, export = true) {
    final publicSurface = PublicSurface.forClass(cl);
    writeNewline();
    emitComment(cl.doc);
    emitPos(cl.pos);
    if (export)
      write('export ');
    write('interface ');
    write(TypeUtil.className(cl));
    if (params.length > 0)
      emitTypeParamDecls(params, true);
    final parents = publicSurface.interfacesFor(params);
    if (parents.length > 0) {
      write(' extends ');
      for (parent in join(parents, write.bind(', '))) {
        write(ctx.typeAccessor(parent.type.get()));
        if (parent.arguments.length > 0)
          TypeEmitter.emitParams(this, parent.copyArguments(), true);
      }
    }
    write(' {');
    increaseIndent();
    function emitMember(member: PublicMember): Void {
      for (signature in member.overloads)
        emitMember(signature);
      switch member.kind {
        case FVar(_, _):
          writeNewline();
          emitPos(member.pos);
          emitMemberName(TypeUtil.nativeName(member.meta) ?? member.name);
          final nullish = NullishContract.forProperty(member.type, member.meta);
          if (nullish.emitOptionalSyntax)
            write('?');
          write(': ');
          final typeOverride = extractStringMeta(member.meta,
            ':ts.type') ?? extractStringMeta(member.meta, ':genes.type');
          TypeEmitter.emitNullishProjection(this, nullish, () -> {
            if (typeOverride != null)
              write(typeOverride);
            else
              emitType(nullish.emittedType);
          }, typeOverride != null);
          write(';');
        case FMethod(_):
          writeNewline();
          emitPos(member.pos);
          emitMemberName(TypeUtil.nativeName(member.meta) ?? member.name);
          if (member.parameters.length > 0)
            emitTypeParamDecls([
              for (parameter in member.parameters)
                parameter.t
            ], true);
          write('(');
          emitFunctionTypeArguments(member.type);
          write('): ');
          emitFunctionReturnType(member.type);
          write(';');
      }
    }
    // Unlike classic `.d.ts`, TS implementation source keeps classified Haxe
    // accessor support methods: generated class bodies call `get_*`/`set_*`
    // directly and must structurally satisfy the emitted interface. The shared
    // model records `isCompilerGenerated`; this profile intentionally includes
    // it until accessor lowering can hide the runtime method behind a private
    // structural contract.
    for (member in publicSurface.instanceMembersFor(params))
      emitMember(member);
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();

    // Runtime marker (Genes runtime compatibility).
    if (export)
      write('export ');
    write('const ');
    write(TypeUtil.className(cl));
    write(' = function() {};');
    writeNewline();
    write(TypeUtil.className(cl));
    write('.__isInterface__ = true;');
    writeNewline();
  }

  function emitFunctionTypeArguments(type: Type) {
    switch type {
      case TFun(args, _):
        var noOptionalUntil = -1;
        var hadOptional = true;
        for (i in 0...args.length) {
          final arg = args[i];
          if (arg.opt)
            hadOptional = true;
          else if (hadOptional) {
            noOptionalUntil = i;
            hadOptional = false;
          }
        }
        for (i in joinIt(0...args.length, write.bind(', '))) {
          final arg = args[i];
          if (genes.util.TypeUtil.isRest(arg.t))
            write('...');
          emitLocalIdent(arg.name != "" ? arg.name : 'arg');
          final nullish = NullishContract.forParameter(arg.t, arg.opt && i > noOptionalUntil);
          if (nullish.emitOptionalSyntax)
            write('?');
          write(': ');
          emitType(nullish.emittedType);
        }
      default:
    }
  }

  function emitFunctionReturnType(type: Type) {
    switch type {
      case TFun(_, ret):
        emitType(ret);
      default:
        write('any');
    }
  }

  function emitTsEnum(et: EnumType, export = true, registerRuntimeType = true) {
    final discriminator = haxe.macro.Context.definedValue('genes.enum_discriminator');
    final id = et.pack.concat([et.name]).join('.');
    final enumParams = et.params != null ? et.params.map(p -> p.t) : [];
    writeNewline();
    emitComment(et.doc);
    emitPos(et.pos);

    // Emit TS union types for enums using declaration merging.
    //
    // IMPORTANT: TS does not allow `export const EnumName` to merge with
    // `export declare namespace EnumName` (duplicate identifier). A function
    // works as the runtime enum container while still allowing type namespace
    // merging.
    if (export)
      write('export ');
    write('declare namespace ');
    write(et.name);
    write(' {');
    increaseIndent();
    writeNewline();
    emitPos(et.pos);
    if (ctx.hasFeature('js.Boot.isEnum')) {
      emitPos(et.pos);
      write('export const __ename__: string;');
    }

    for (ctorName in et.names) {
      final c = et.constructs.get(ctorName);
      final ctorParams = c.params != null ? c.params.map(p -> p.t) : [];
      writeNewline();
      emitComment(c.doc);
      emitPos(c.pos);
      write('export type ');
      write(ctorName);
      TypeEmitter.emitEnumConstructorTypeParams(this, enumParams, ctorParams);
      write(' = {');
      if (discriminator != null) {
        emitString(discriminator);
        write(': ');
        emitString(ctorName);
        write(', ');
      }
      write('_hx_index: ${c.index}');
      switch c.type {
        case TFun(args, _):
          for (arg in args) {
            write(', ');
            emitIdent(arg.name);
            write(': ');
            emitType(arg.t);
          }
        default:
      }
      write(', __enum__: ');
      emitString(id);
      write('}');

      writeNewline();
      emitPos(c.pos);
      write('export const ');
      write(ctorName);
      write(': ');
      switch c.type {
        case TFun(args, ret):
          final allParams = enumParams.concat(c.params.map(p -> p.t));
          final used = new Map<String, Bool>();
          for (a in args)
            collectUsedTypeParamKeys(a.t, used);
          emitTypeParamDeclsUnusedNever(allParams, true, used, false);
          write('(');
          for (arg in join(args, write.bind(', '))) {
            emitIdent(arg.name);
            final nullish = NullishContract.forParameter(arg.t, arg.opt);
            if (nullish.emitOptionalSyntax)
              write('?');
            write(': ');
            emitType(nullish.emittedType);
          }
          write(') => ');
          emitType(ret);
        default:
          write(ctorName);
          // Nullary constructors should be usable as any instantiation of the
          // enum's type params; emit `<never, ...>` to keep TS assignment-friendly
          // without leaking `any` into user modules.
          if (enumParams.length > 0) {
            write('<');
            for (_ in join(enumParams, write.bind(', ')))
              write('never');
            write('>');
          }
      }
      write(';');
    }
    writeNewline();
    emitPos(et.pos);
    write('export type __Construct = ');
    for (ctorName in join(et.names, write.bind(' | '))) {
      write('typeof ');
      write(ctorName);
    }
    write(';');
    writeNewline();
    emitPos(et.pos);
    write('export const __constructs__: __Construct[];');

    writeNewline();
    emitPos(et.pos);
    write('export type __EmptyConstruct = ');
    final emptyCtorNames = [
      for (name in et.names)
        if (!et.constructs[name].type.match(TFun(_, _))) name
    ];
    if (emptyCtorNames.length == 0) {
      write('never');
    } else {
      for (ctorName in join(emptyCtorNames, write.bind(' | '))) {
        write('typeof ');
        write(ctorName);
      }
    }
    write(';');
    writeNewline();
    emitPos(et.pos);
    write('export const __empty_constructs__: __EmptyConstruct[];');
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();

    writeNewline();
    emitComment(et.doc);
    emitPos(et.pos);
    if (export)
      write('export ');
    write('type ');
    write(et.name);
    emitTypeParamDecls(enumParams, true);
    write(' =');
    increaseIndent();
    for (ctorName in et.names) {
      final c = et.constructs.get(ctorName);
      writeNewline();
      emitComment(c.doc);
      write('| ');
      write(et.name);
      write('.');
      emitPos(c.pos);
      write(ctorName);
      TypeEmitter.emitParams(this, enumParams, false);
    }
    decreaseIndent();
    writeNewline();

    emitPos(et.pos);
    if (export)
      write('export ');
    write('function ');
    write(et.name);
    write('() {}');
    writeNewline();
    writeNewline();
    if (registerRuntimeType
      && !haxe.macro.Context.defined('genes.ts.minimal_runtime')) {
      write(ctx.typeAccessor(TypeUtil.registerType));
      write('.setHxEnum(');
      emitString(id);
      write(', ');
      write(et.name);
      write(');');
      writeNewline();
    }

    writeNewline();
    write('Object.assign(');
    write(et.name);
    write(', {');
    increaseIndent();
    writeNewline();
    if (ctx.hasFeature('js.Boot.isEnum')) {
      write('__ename__: ');
      emitString(id);
      write(',');
      writeNewline();
    }
    for (ctorName in join(et.names, () -> {
      write(',');
      writeNewline();
    })) {
      final c = et.constructs.get(ctorName);
      emitComment(c.doc);
      emitPos(c.pos);
      write(ctorName);
      write(': ');
      switch c.type {
        case TFun(args, _):
          write('Object.assign(');
          final allParams = enumParams.concat(c.params.map(p -> p.t));
          final used = new Map<String, Bool>();
          for (a in args)
            collectUsedTypeParamKeys(a.t, used);
          emitTypeParamDeclsUnusedNever(allParams, true, used, true);
          write('(');
          for (param in join(args, write.bind(', '))) {
            emitLocalIdent(param.name);
            if (param.opt)
              write('?');
            write(': ');
            emitType(param.t);
          }
          write(') => ({_hx_index: ${c.index}, __enum__: ');
          emitString(id);
          write(', ');
          for (param in join(args, write.bind(', '))) {
            emitString(param.name);
            write(': ');
            emitLocalIdent(param.name);
          }
          if (discriminator != null) {
            write(', ');
            emitString(discriminator);
            write(': ');
            emitString(ctorName);
          }
          write('}), {_hx_name: ');
          emitString(ctorName);
          write(', __params__: [');
          for (param in join(args, write.bind(', ')))
            emitString(param.name);
          write(']})');
        default:
          write('{_hx_name: ');
          emitString(ctorName);
          write(', _hx_index: ${c.index}, __enum__: ');
          emitString(id);
          if (discriminator != null) {
            write(', ');
            emitString(discriminator);
            write(': ');
            emitString(ctorName);
          }
          write('}');
      }
    }
    decreaseIndent();
    writeNewline();
    write('});');
    writeNewline();

    writeNewline();
    write('Object.assign(');
    write(et.name);
    write(', {');
    increaseIndent();
    writeNewline();
    write('__constructs__: [');
    for (ctorName in join(et.names, write.bind(', '))) {
      #if (haxe_ver >= 4.2)
      write(et.name);
      emitField(ctorName);
      #else
      emitString(ctorName);
      #end
    }
    write('],');
    writeNewline();
    write('__empty_constructs__: [');
    final empty = [
      for (name in et.names)
        if (!et.constructs[name].type.match(TFun(_, _))) et.constructs[name]
    ];
    for (c in join(empty, write.bind(', '))) {
      write(et.name);
      emitField(c.name);
    }
    write(']');
    decreaseIndent();
    writeNewline();
    write('});');
    writeNewline();
  }

  function emitTsTypeDefinition(def: DefType, params: Array<Type>,
      export = true) {
    // Prefer TypeScript builtins for well-known JS types to avoid "stringly"
    // typedefs (e.g. `{ status: string, ... }`) and reduce `any` usage.
    if (def.module == 'js.lib.Promise') {
      switch def.name {
        case 'PromiseSettleOutcome' if (params.length == 1):
          writeNewline();
          emitComment(def.doc);
          emitPos(def.pos);
          emitTsTypeDeclarationPrefix(export);
          TypeEmitter.emitDeclarationBaseType(this, def, params, true);
          write(' = PromiseSettledResult<');
          emitType(params[0]);
          write('>');
          writeNewline();
          return;
        case 'ThenableStruct' if (params.length == 1):
          writeNewline();
          emitComment(def.doc);
          emitPos(def.pos);
          emitTsTypeDeclarationPrefix(export);
          TypeEmitter.emitDeclarationBaseType(this, def, params, true);
          write(' = PromiseLike<');
          emitType(params[0]);
          write('>');
          writeNewline();
          return;
        default:
      }
    }
    // WebIDL-generated DOM iterator typedefs in Haxe std are often `next(): Dynamic`,
    // which becomes `next(): any` in TS output. Replace the entire typedef with the
    // idiomatic TS iterator type when we can provide the correct element type.
    //
    // NOTE: These are purely type-level overrides; runtime values come from the DOM.
    if (def.module == 'js.html.HeadersIterator'
      && def.name == 'HeadersIterator') {
      writeNewline();
      emitComment(def.doc);
      emitPos(def.pos);
      emitTsTypeDeclarationPrefix(export);
      TypeEmitter.emitDeclarationBaseType(this, def, params, true);
      write(' = IterableIterator<[string, string]>');
      writeNewline();
      return;
    }
    if (def.module == 'js.html.URLSearchParamsIterator'
      && def.name == 'URLSearchParamsIterator') {
      writeNewline();
      emitComment(def.doc);
      emitPos(def.pos);
      emitTsTypeDeclarationPrefix(export);
      TypeEmitter.emitDeclarationBaseType(this, def, params, true);
      write(' = IterableIterator<[string, string]>');
      writeNewline();
      return;
    }
    if (def.module == 'js.html.FormDataIterator'
      && def.name == 'FormDataIterator') {
      writeNewline();
      emitComment(def.doc);
      emitPos(def.pos);
      emitTsTypeDeclarationPrefix(export);
      TypeEmitter.emitDeclarationBaseType(this, def, params, true);
      // TS DOM lib provides `FormDataEntryValue = File | string`.
      write(' = IterableIterator<[string, FormDataEntryValue]>');
      writeNewline();
      return;
    }
    if (def.module == 'js.lib.Object') {
      switch def.name {
        case 'ObjectPropertyDescriptor':
          writeNewline();
          emitComment(def.doc);
          emitPos(def.pos);
          emitTsTypeDeclarationPrefix(export);
          TypeEmitter.emitDeclarationBaseType(this, def, params, true);
          write(' = PropertyDescriptor');
          writeNewline();
          return;
        default:
      }
    }

    writeNewline();
    emitComment(def.doc);
    emitPos(def.pos);
    emitTsTypeDeclarationPrefix(export);
    TypeEmitter.emitDeclarationBaseType(this, def, params, true);
    write(' = ');
    final typeOverride = switch def.meta.extract(':ts.type') {
      case [{params: [{expr: EConst(CString(type))}]}]: type;
      default:
        switch def.meta.extract(':genes.type') {
          case [{params: [{expr: EConst(CString(type))}]}]: type;
          default: null;
        }
    };
    if (typeOverride != null)
      write(typeOverride);
    else {
      final capturedSourceType = SignatureCache.getTypedefSourceType(def,
        params);
      if (capturedSourceType != null)
        TypeEmitter.emitCapturedSourceType(this, capturedSourceType);
      else
        emitType(PublicSurface.forTypedef(def).aliasTypeFor(params));
    }
    writeNewline();
  }

  /** Writes one module-level type alias prefix with projected ESM visibility. */
  function emitTsTypeDeclarationPrefix(export: Bool): Void {
    if (export)
      write('export ');
    write('type ');
  }

  public function includeType(type: Type) {}

  public function typeAccessor(type: TypeAccessor)
    return ctx.typeAccessor(type);

  /** Resolves exact callable-generic identity inside the active method scope. */
  public function typeParameterName(parameter: ClassType): String {
    if (currentCallableSignature != null) {
      final planned = currentCallableSignature.nameFor(parameter);
      if (planned != null)
        return planned;
    }
    return parameter.name;
  }

  function emitType(type: Type, ?params: Array<TypeParameter>) {
    if (params != null && params.length > 0)
      TypeEmitter.emitParams(this, params.map(p -> p.t), true);
    TypeEmitter.emitType(this, type, params == null);
  }

  static function extractStringMeta(meta: Null<MetaAccess>,
      name: String): Null<String> {
    if (meta == null)
      return null;
    return switch meta.extract(name) {
      case [{params: [{expr: EConst(CString(value))}]}]: value;
      default: null;
    }
  }
}
