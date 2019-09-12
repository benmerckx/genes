package genes;

import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr.Position;
import genes.util.TypeUtil;
import genes.Dependencies;
import genes.util.TypeUtil;
import genes.dts.TypeEmitter;

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
  final params: Array<TypeParameter>;
  final doc: Null<String>;
}

enum Export {
  Type(type: Type);
  External(path: String);
}

enum Member {
  MClass(type: ClassType, params: Array<Type>, fields: Array<Field>);
  MEnum(type: EnumType, params: Array<Type>);
  MType(type: DefType, params: Array<Type>);
  MExport(path: String);
  MMain(expr: TypedExpr);
}

class Module {
  public final module: String;
  public final path: String;
  public final members: Array<Member>;
  public var typeDependencies(get, null): Dependencies;
  public var codeDependencies(get, null): Dependencies;

  public function new(module, exports: Array<Export>, ?main: TypedExpr) {
    this.module = module;
    path = module.split('.').join('/');
    members = [
      for (type in exports)
        switch type {
          case Type(TEnum(_.get() => et, params)):
            MEnum(et, params);
          case Type(TInst(_.get() => cl, params)):
            MClass(cl, params, fieldsOf(cl));
          case Type(TType(_.get() => tt, params)):
            MType(tt, params);
          case External(path):
            MExport(toPath(path));
          default:
            throw 'assert';
        }
    ];
    if (main != null)
      members.push(MMain(main));
  }

  public function toPath(from: String) {
    final to = genes.util.PathUtil.relative(path, from.replace('.', '/'));
    return if (to.charAt(0) != '.') './' + to else to;
  }

  function get_typeDependencies() {
    if (typeDependencies != null)
      return typeDependencies;
    final dependencies = new Dependencies(this, false);
    final writer = {
      write: function(code: String) {},
      emitPos: function(pos) {},
      includeType: function(type: Type) {
        dependencies.add(TypeUtil.typeToModuleType(type));
      }
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
        default:
      }
    }
    return typeDependencies = dependencies;
  }

  function get_codeDependencies() {
    if (codeDependencies != null)
      return codeDependencies;
    final dependencies = new Dependencies(this);
    function addFromExpr(e: TypedExpr)
      switch e {
        case null:
        case {expr: TTypeExpr(t)}:
          dependencies.add(t);
        case {expr: TNew(c, _, el)}:
          dependencies.add(TClassDecl(c));
          for (e in el)
            addFromExpr(e);
        case {expr: TField(x, f)}
          if (TypeUtil.fieldName(f) == "iterator"): // Todo: conditions here could be refined
          dependencies.add(TypeUtil.getModuleType('HxOverrides'));
          addFromExpr(x);
        case e:
          e.iter(addFromExpr);
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
    return codeDependencies = dependencies;
  }

  static function fieldsOf(cl: ClassType) {
    final fields = [];
    switch cl.constructor {
      case null:
      case ctor:
        final e = ctor.get().expr();
        fields.push({
          kind: Constructor,
          type: e.t,
          expr: e,
          pos: e.pos,
          name: 'constructor',
          isStatic: false,
          params: [],
          doc: null
        });
    }
    for (field in cl.fields.get()) {
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
        params: field.params,
        doc: field.doc
      });
    }
    for (field in cl.statics.get())
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
        doc: field.doc
      });
    return fields;
  }

  public function createContext(api: haxe.macro.JSGenApi): genes.Context
    return {
      expr: api.generateStatement,
      value: api.generateValue,
      hasFeature: api.hasFeature,
      addFeature: api.addFeature,
      typeAccessor: (type: ModuleType) -> switch type {
        case TAbstract(_.get() => {name: name}) | TClassDecl(_.get() =>
          {name: name}) | TEnumDecl(_.get() =>
            {name: name}) | TTypeDecl(_.get() => {name: name}): return name;
      }
    }
}
