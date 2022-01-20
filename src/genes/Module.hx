package genes;

import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr;
import helder.Set;
import genes.util.TypeUtil;
import genes.Dependencies;
import genes.util.TypeUtil;
import genes.dts.TypeEmitter;
import genes.util.Timer.timer;
import genes.TypeAccessor;

using StringTools;
using haxe.macro.TypedExprTools;

enum FieldKind {
  Constructor;
  Method;
  Property;
}

typedef Field = {
  final kind: FieldKind;
  final meta: Null<MetaAccess>;
  final name: String;
  final type: Type;
  final expr: TypedExpr;
  final pos: Position;
  final isStatic: Bool;
  #if (haxe_ver >= 4.2)
  final isAbstract: Bool;
  #end
  final isPublic: Bool;
  final params: Array<TypeParameter>;
  final doc: Null<String>;
  final setter: Bool;
  final getter: Bool;
  final tsType: Null<String>;
}

enum Member {
  MClass(type: ClassType, params: Array<Type>, fields: Array<Field>);
  MEnum(type: EnumType, params: Array<Type>);
  MType(type: DefType, params: Array<Type>);
  MMain(expr: TypedExpr);
}

typedef ModuleContext = {
  modules: Map<String, Module>,
  concrete: Array<String>
}

typedef ModuleExport = {
  pos: Position,
  name: String,
  module: String,
  isType: Bool
}

class Module {
  public final module: String;
  public final path: String;
  public final members: Array<Member> = [];
  public final expose: Array<ModuleExport> = [];
  public var typeDependencies(get, null): Dependencies;
  public var codeDependencies(get, null): Dependencies;

  final context: ModuleContext;
  final cycleCache = new Map<String, Bool>();

  public function new(context: ModuleContext, module, types: Array<Type>,
      ?main: TypedExpr, ?expose: Array<ModuleExport>) {
    this.context = context;
    this.module = module;
    if (expose != null)
      this.expose = expose;
    path = module.split('.').join('/');
    final endTimer = timer('members');
    for (type in types)
      switch type {
        case TEnum(_.get() => et, params):
          members.push(MEnum(et, params));
        case TInst(_.get() => cl, params):
          members.push(MClass(cl, params, fieldsOf(cl)));
        case TType(_.get() => tt, params):
          function addIfConcrete(t: BaseType) {
            final name = TypeUtil.baseTypeFullName(t);
            if (context.concrete.indexOf(name) > -1)
              members.push(MType(tt, params));
          }
          switch Context.followWithAbstracts(tt.type) {
            case TEnum(_.get() => t, _): addIfConcrete(t);
            case TInst(t = _.get() => {
              kind: KNormal
              #if (haxe_ver >= 4.2)
              | KModuleFields(_)
              #end
              | KGeneric | KGenericInstance(_, _) | KAbstractImpl(_)
            }, _):
              addIfConcrete(t.get());
            default: members.push(MType(tt, params));
          }
        default:
          throw 'assert';
      }
    if (main != null)
      members.push(MMain(main));
    endTimer();
  }

  public function toPath(from: String) {
    return genes.util.PathUtil.relative(path, from.replace('.', '/'));
  }

  public function isCyclic(test: String)
    return switch cycleCache.get(test) {
      case null:
        final endTimer = timer('isCyclic');
        final seen = new Set();
        seen.add(module);
        final res = testCycles(test, seen);
        cycleCache.set(test, res);
        endTimer();
        res;
      case v: v;
    }

  function testCycles(test: String, seen: Set<String>) {
    seen.add(test);
    switch context.modules[test] {
      case null:
        return false;
      case v:
        for (dependency in v.codeDependencies.imports.keys()) {
          if (seen.exists(dependency)) {
            if (dependency == module)
              return true;
            else
              continue;
          }
          if (testCycles(dependency, seen))
            return true;
        }
        return false;
    }
  }

  function get_typeDependencies() {
    if (typeDependencies != null)
      return typeDependencies;
    final endTimer = timer('typeDependencies');
    final dependencies = new Dependencies(this, false);
    final noop = function() {}
    final writer = {
      write: function(code: String) {},
      writeNewline: noop,
      increaseIndent: noop,
      decreaseIndent: noop,
      emitComment: function(comment: String) {},
      emitPos: function(pos) {},
      includeType: function(type: Type) {
        dependencies.add(TypeUtil.typeToModuleType(type));
      },
      typeAccessor: dependencies.typeAccessor
    }
    function addBaseType(type: BaseType, params: Array<Type>)
      TypeEmitter.emitBaseType(writer, type, params, true);
    function addType(type: Type)
      TypeEmitter.emitType(writer, type);
    function addParams(params: Array<Type>)
      TypeEmitter.emitParams(writer, params, true);
    for (member in members) {
      switch member {
        case MClass(cl, params, fields):
          addParams(params);
          switch cl.interfaces {
            case null | []:
            case v:
              for (i in v) {
                dependencies.add(TClassDecl(i.t));
                addBaseType(i.t.get(), i.params);
              }
          }
          switch cl.superClass {
            case null:
            case {t: t}: dependencies.add(TClassDecl(t));
          }
          for (field in fields) {
            if (field.tsType != null)
              continue;
            addParams(field.params.map(p -> p.t));
            addType(field.type);
          }
        case MEnum(et, params):
          addParams(params);
          for (c in et.constructs) {
            addParams(c.params.map(p -> p.t));
            switch c.type {
              case TFun(args, ret):
                for (arg in args) {
                  addType(arg.t);
                }
              default:
            }
          }
        case MMain(expr):
          addType(expr.t);
        case MType(def, params):
          addParams(params);
          addType(def.type);
        default:
      }
    }
    endTimer();
    return typeDependencies = dependencies;
  }

  function get_codeDependencies() {
    if (codeDependencies != null)
      return codeDependencies;
    final endTimer = timer('codeDependencies');
    final dependencies = new Dependencies(this);
    function addFromExpr(e: TypedExpr) {
      for (type in TypeUtil.typesInExpr(e))
        dependencies.add(type);
    }
    for (member in members) {
      switch member {
        case MClass(cl, _, fields):
          switch cl.interfaces {
            case null | []:
            case v:
              for (i in v)
                dependencies.add(TClassDecl(i.t));
          }
          switch cl.superClass {
            case null:
            case {t: t}: dependencies.add(TClassDecl(t));
          }
          for (field in fields)
            addFromExpr(field.expr);
          addFromExpr(cl.init);
        case MMain(expr):
          addFromExpr(expr);
        default:
      }
    }
    if (module != 'genes.Register')
      dependencies.add(TypeUtil.registerType);
    endTimer();
    return codeDependencies = dependencies;
  }

  public function getMember(name: String) {
    for (member in members)
      switch member {
        case MClass({name: n}, _) | MEnum({name: n}, _) | MType({name: n}, _)
          if (n == name):
          return member;
        default:
      }
    return null;
  }

  static function hasExternSuper(s: ClassType)
    return switch s.superClass {
      case null: s.isExtern;
      case {t: _.get() => v}: hasExternSuper(v);
    }

  static function fieldsOf(cl: ClassType) {
    final fields: Array<Field> = [];
    final classDisableNativeAccessors = haxe.macro.Context.defined('genes.disable_native_accessors')
      || cl.meta.has(':genes.disableNativeAccessors');
    switch cl.constructor {
      case null:
      case ctor:
        final e = ctor.get().expr();
        fields.push({
          kind: Constructor,
          type: e.t,
          meta: null,
          expr: e,
          pos: e.pos,
          name: 'new',
          isStatic: false,
          #if (haxe_ver >= 4.2)
          isAbstract: false,
          #end
          isPublic: ctor.get().isPublic,
          params: [],
          doc: null,
          getter: false,
          setter: false,
          tsType: null
        });
    }
    for (field in cl.fields.get()) {
      final isVar = field.meta.has(':isVar');
      final disableNativeAccessors = field.meta.has(':genes.disableNativeAccessors')
        || classDisableNativeAccessors;
      fields.push({
        kind: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        meta: field.meta,
        name: field.name,
        type: field.type,
        expr: field.expr(),
        pos: field.pos,
        isStatic: false,
        #if (haxe_ver >= 4.2)
        isAbstract: field.isAbstract,
        #end
        isPublic: field.isPublic,
        params: field.params,
        doc: field.doc,
        getter: !disableNativeAccessors && !isVar
        && field.kind.match(FVar(AccCall, AccCall | AccNever)),
        setter: !disableNativeAccessors && !isVar
        && field.kind.match(FVar(AccCall | AccNever, AccCall)),
        tsType: switch field.meta.extract(':genes.type') {
          case [{params: [{expr: EConst(CString(type))}]}]: type;
          default: null;
        }
      });
    }
    for (field in cl.statics.get()) {
      final isVar = field.meta.has(':isVar');
      final disableNativeAccessors = field.meta.has(':genes.disableNativeAccessors')
        || classDisableNativeAccessors;
      fields.push({
        kind: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        meta: field.meta,
        name: field.name,
        type: field.type,
        expr: field.expr(),
        pos: field.pos,
        isStatic: true,
        #if (haxe_ver >= 4.2)
        isAbstract: false,
        #end
        isPublic: field.isPublic,
        params: {
          final params = switch cl.kind {
            case KAbstractImpl(_.get().params => params): params;
            default: [];
          }
          for (param in field.params) {
            if (params.filter(p -> p.name == param.name).length > 0)
              continue;
            params.push(param);
          }
          params;
        },
        doc: field.doc,
        getter: !disableNativeAccessors && !isVar
        && field.kind.match(FVar(AccCall, AccCall | AccNever)),
        setter: !disableNativeAccessors && !isVar
        && field.kind.match(FVar(AccCall | AccNever, AccCall)),
        tsType: switch field.meta.extract(':genes.type') {
          case [{params: [{expr: EConst(CString(type))}]}]: type;
          default: null;
        }
      });
    }
    return fields;
  }

  public function createContext(api: haxe.macro.JSGenApi): genes.Context {
    final typeAccessor = (type: TypeAccessor) -> switch type {
      case Abstract(name) | Concrete(_, name, _): name;
    }
    final context: genes.Context = {
      expr: api.generateStatement,
      value: api.generateValue,
      hasFeature: api.hasFeature,
      addFeature: api.addFeature,
      typeAccessor: typeAccessor
    }
    api.setTypeAccessor(type -> context.typeAccessor(type));
    return context;
  }
}
