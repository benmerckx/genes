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
}

enum Member {
  MClass(type: ClassType, params: Array<Type>, fields: Array<Field>);
  MEnum(type: EnumType, params: Array<Type>);
  MType(type: DefType, params: Array<Type>);
  MMain(expr: TypedExpr);
}

class Module {
  public final module: String;
  public final path: String;
  public final members: Array<Member>;

  public function new(module, types: Array<Type>, ?main: TypedExpr) {
    this.module = module;
    path = module.split('.').join('/');
    members = [
      for (type in types)
        switch type {
          case TEnum(_.get() => et, params):
            MEnum(et, params);
          case TInst(_.get() => cl, params):
            MClass(cl, params, fieldsOf(cl));
          case TType(_.get() => tt, params):
            MType(tt, params);
          default:
            throw 'assert';
        }
    ];
    if (main != null)
      members.push(MMain(main));
  }

  public function toPath(from: String) {
    final parts = from.split('.');
    final dirs = module.split('.');
    return switch dirs.length {
      case 1: './' + parts.join('/');
      case v:
        [for (i in 0...v - 1) '..'].concat(parts).join('/');
    }
  }

  public function typeDependencies() {
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
              for (i in v)
                addBaseType(i.t.get(), i.params);
          }
          switch cl.superClass {
            case null:
            case {t: t}: dependencies.add(TClassDecl(t));
          }
          for (field in fields)
            if (field.expr != null)
              addType(field.expr.t);
        case MMain(expr):
          addType(expr.t);
        default:
      }
    }
    return dependencies;
  }

  public function codeDependencies() {
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
          pos: e.pos,
          name: 'constructor',
          isStatic: false,
          params: []
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
        params: field.params
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
        params: field.params
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
