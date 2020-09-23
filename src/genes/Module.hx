package genes;

import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr.Position;
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
  final name: String;
  final type: Type;
  final expr: TypedExpr;
  final pos: Position;
  final isStatic: Bool;
  final isPublic: Bool;
  final params: Array<TypeParameter>;
  final doc: Null<String>;
  final setter: Bool;
  final getter: Bool;
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

class Module {
  public final module: String;
  public final path: String;
  public final members: Array<Member> = [];
  public var typeDependencies(get, null): Dependencies;
  public var codeDependencies(get, null): Dependencies;

  final context: ModuleContext;
  final cycleCache = new Map<String, Bool>();

  public function new(context: ModuleContext, module, types: Array<Type>,
      ?main: TypedExpr) {
    this.context = context;
    this.module = module;
    path = module.split('.').join('/');
    final endTimer = timer('members');
    for (type in types)
      switch type {
        case TEnum(_.get() => et, params):
          members.push(MEnum(et, params));
        case TInst(_.get() => cl, params):
          members.push(MClass(cl, params, fieldsOf(cl)));
        case TType(_.get() => tt, params):
          switch Context.followWithAbstracts(tt.type) {
            case TEnum((_.get() : BaseType) => t, _) |
              TInst((_.get() : BaseType) => t, _):
              final name = TypeUtil.baseTypeName(t);
              if (context.concrete.indexOf(name) > -1) members.push(MType(tt,
                params));
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
    final writer = {
      write: function(code: String) {},
      emitPos: function(pos) {},
      includeType: function(type: Type) {
        switch Context.followWithAbstracts(type) {
          case TEnum((_.get() : BaseType) => t, _) |
            TInst((_.get() : BaseType) => t, _):
            final name = TypeUtil.baseTypeName(t);
            if (context.concrete.indexOf(name) > -1)
              dependencies.add(TypeUtil.typeToModuleType(type));
          default:
            dependencies.add(TypeUtil.typeToModuleType(type));
        }
      },
      typeAccessor: dependencies.typeAccessor
    }
    function addBaseType(type: BaseType, params: Array<Type>)
      TypeEmitter.emitBaseType(writer, type, params);
    function addType(type: Type)
      TypeEmitter.emitType(writer, type);
    for (member in members) {
      switch member {
        case MClass(cl, _, fields):
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
          for (field in fields)
            addType(field.type);
        case MEnum(et, _):
          for (c in et.constructs) {
            switch c.type {
              case TFun(args, ret):
                for (arg in args)
                  addType(arg.t);
              default:
            }
          }
        case MMain(expr):
          addType(expr.t);
        case MType(def, _):
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
      dependencies.push('genes.Register', {
        type: DName,
        name: 'Register',
        path: 'genes.Register',
        external: false
      });
    endTimer();
    return codeDependencies = dependencies;
  }

  static function hasExternSuper(s: ClassType)
    return switch s.superClass {
      case null: s.isExtern;
      case {t: _.get() => v}: hasExternSuper(v);
    }

  static function fieldsOf(cl: ClassType) {
    final fields: Array<Field> = [];
    switch cl.constructor {
      case null:
      case ctor:
        final e = ctor.get().expr();
        fields.push({
          kind: Constructor,
          type: e.t,
          expr: e,
          pos: e.pos,
          name: 'new',
          isStatic: false,
          isPublic: ctor.get().isPublic,
          params: [],
          doc: null,
          getter: false,
          setter: false
        });
    }
    for (field in cl.fields.get()) {
      final isVar = field.meta.has(':isVar');
      fields.push({
        kind: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        name: field.name,
        type: field.type,
        expr: field.expr(),
        pos: field.pos,
        isStatic: false,
        isPublic: field.isPublic,
        params: field.params,
        doc: field.doc,
        getter: !isVar && field.kind.match(FVar(AccCall, AccCall | AccNever)),
        setter: !isVar && field.kind.match(FVar(AccCall | AccNever, AccCall))
      });
    }
    for (field in cl.statics.get()) {
      final isVar = field.meta.has(':isVar');
      fields.push({
        kind: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        name: field.name,
        type: field.type,
        expr: field.expr(),
        pos: field.pos,
        isStatic: true,
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
        getter: !isVar && field.kind.match(FVar(AccCall, AccCall | AccNever)),
        setter: !isVar && field.kind.match(FVar(AccCall | AccNever, AccCall))
      });
    }
    return fields;
  }

  public function createContext(api: haxe.macro.JSGenApi): genes.Context {
    final typeAccessor = (type: TypeAccessor) -> switch type {
      case Abstract(name) | Concrete(_, name, _): name;
    }
    api.setTypeAccessor(type -> typeAccessor(type));
    return {
      expr: api.generateStatement,
      value: api.generateValue,
      hasFeature: api.hasFeature,
      addFeature: api.addFeature,
      typeAccessor: typeAccessor
    }
  }
}
