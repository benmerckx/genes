package genes;

import haxe.macro.Type;

using StringTools;
using haxe.macro.TypedExprTools;

enum FieldType {
	Constructor;
  Property;
  Method;
  StaticProperty;
  StaticMethod;
}

typedef Field = {
  final type: FieldType;
  final expr: TypedExpr;
}

enum Member {
  MClass(type: ClassType, fields: Array<Field>);
  MEnum(type: EnumType);
}

class Module {
  public final path: String;
  public final members: Array<Member>;
  public var dependencies(get, null): Map<String, Array<String>>;

  public function new(path, types: Array<Type>) {
    this.path = path;
    this.members = [
      for (type in types)
        switch type {
          case TEnum(_.get() => et, _): MEnum(et);
          case TInst(_.get() => cl, _): MClass(cl, fieldsOf(cl));
          default: throw 'assert';
        }
    ];
  }

  function toPath(module: String) {
    final parts = module.split('.');
    final dirs = path.split('/');
    return switch dirs.length {
      case 1: './' + parts.join('/');
      case v: [for(i in 0 ... v - 1) '..'].concat(parts).join('/');
    }
  }

  function get_dependencies() {
    if (dependencies != null) return dependencies;
    dependencies = new Map();
    final prefix =
      [for(i in 0 ... path.split('/').length - 1) '..'].concat(['']).join('/');
    function add(type: ModuleType)
      switch type {
        case TClassDecl((_.get(): BaseType) => base) 
          | TEnumDecl((_.get(): BaseType) => base):
          final path = toPath(base.module);
          if (dependencies.exists(path)) {
            final names = dependencies.get(path);
            if (names.indexOf(base.name) == -1) names.push(base.name);
          } else {
            dependencies.set(path, [base.name]);
          }
        default:
      }
    function addFromExpr(e: TypedExpr) 
      switch e {
        case null:
        case {expr: TTypeExpr(t)}: add(t);
        case {expr: TNew(c, _, el)}: add(TClassDecl(c));
        case e: e.iter(addFromExpr);
      }
    for (member in members) {
      switch member {
        case MClass(cl, fields):
          switch cl.interfaces {
            case null | []:
            case v: for (i in v) add(TClassDecl(i.t));
          }
          switch cl.superClass {
            case null:
            case {t: t}: add(TClassDecl(t));
          }
          for (field in fields)
            addFromExpr(field.expr);
          addFromExpr(cl.init);
        default: 
      }
    }
    return dependencies;
  }

  static function fieldsOf(cl: ClassType) {
    final fields = [];
    switch cl.constructor {
      case null:
      case ctor:
        fields.push({
          type: Constructor,
          expr: ctor.get().expr()
        });
    }
    for (field in cl.fields.get())
      fields.push({
        type: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        expr: field.expr()
      });
    for (field in cl.statics.get())
      fields.push({
        type: switch field.kind {
          case FVar(_, _): StaticProperty;
          case FMethod(_): StaticMethod;
        },
        expr: field.expr()
      });
    return fields;
  }
}