package genes;

import haxe.macro.Context;
import haxe.macro.Type;

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
  final isStatic: Bool;
}

enum Member {
  MClass(type: ClassType, fields: Array<Field>);
  MEnum(type: EnumType);
  MMain(expr: TypedExpr);
}

class Module {
  public final path: String;
  public final file: Null<String>;
  public final members: Array<Member>;
  public var dependencies(get, null): Map<String, Array<String>>;

  public function new(path, file, types: Array<Type>, ?main: TypedExpr) {
    this.path = path;
    this.file = file;
    members = [
      for (type in types)
        switch type {
          case TEnum(_.get() => et, _): MEnum(et);
          case TInst(_.get() => cl, _): MClass(cl, fieldsOf(cl));
          default: throw 'assert';
        }
    ];
    if (main != null) members.push(MMain(main));
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
    function add(type: ModuleType)
      switch type {
        case TClassDecl(_.get() => {isExtern: true}):
        case TClassDecl(_.get() => {isInterface: true}):
        case TClassDecl((_.get(): BaseType) => base) 
          | TEnumDecl((_.get(): BaseType) => base):
          if (base.module.replace('.', '/') == path) return;
          final modulePath = toPath(base.module);
          if (dependencies.exists(modulePath)) {
            final names = dependencies.get(modulePath);
            if (names.indexOf(base.name) == -1) names.push(base.name);
          } else {
            dependencies.set(modulePath, [base.name]);
          }
        default:
      }
    function addFromExpr(e: TypedExpr) 
      switch e {
        case null:
        case {expr: TTypeExpr(t)}: add(t);
        case {expr: TNew(c, _, el)}: 
          add(TClassDecl(c));
          for (e in el) e.iter(addFromExpr);
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
        case MMain(expr):
          addFromExpr(expr);
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
        final e = ctor.get().expr();
        fields.push({
          kind: Constructor,
          type: e.t,
          expr: e,
          name: 'constructor',
          isStatic: false
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
        isStatic: false
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
        isStatic: true
      });
    return fields;
  }
}