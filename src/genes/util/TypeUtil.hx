package genes.util;

import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;

using haxe.macro.TypeTools;
using haxe.macro.TypedExprTools;

class TypeUtil {
  public static final registerType = getModuleType('genes.Register');
  public static final bootType = getModuleType('js.Boot');

  public static function typeToModuleType(type: Type): ModuleType
    return switch type {
      case TEnum(r, _): TEnumDecl(r);
      case TInst(r, _): TClassDecl(r);
      case TType(r, _): TTypeDecl(r);
      case TAbstract(r, _): TAbstract(r);
      case _: null;
    }

  public static function typeToBaseType(type: Type): BaseType
    return switch type {
      case TEnum((_.get() : BaseType) => base, _): base;
      case TInst((_.get() : BaseType) => base, _): base;
      case TType((_.get() : BaseType) => base, _): base;
      case TAbstract((_.get() : BaseType) => base, _): base;
      case _: null;
    }

  public static function getModuleType(module: String)
    return typeToModuleType(Context.getType(module));

  public static function baseTypeFullName(type: BaseType) {
    return type.module + '.' + type.name;
  }

  public static function block(e: TypedExpr): TypedExpr
    return switch e.expr {
      case TBlock(_): e;
      case _: {expr: TBlock([e]), t: e.t, pos: e.pos}
    }

  public static function addObjectdeclParens(e: TypedExpr): TypedExpr {
    function loop(e: TypedExpr): TypedExpr
      return switch (e.expr) {
        case TCast(e1, null), TMeta(_, e1): loop(e1);
        case TObjectDecl(_): with(e, TParenthesis(e));
        case _: e;
      }
    return loop(e);
  }

  public static function fieldName(f: FieldAccess): String
    return switch f {
      case FAnon(f), FInstance(_, _, f), FStatic(_, f), FClosure(_, f):
        f.get().name;
      case FEnum(_, f): f.name;
      case FDynamic(n): n;
    }

  // https://github.com/HaxeFoundation/haxe/blob/682b8e3407cf04bb0b81275d6543cc9c45e00e89/src/generators/genjs.ml#L251
  static function isDynamicType(type: Type): Bool {
    return switch Context.followWithAbstracts(type) {
      case TInst(_.get() => {name: 'Array', pack: []}, _) |
        TInst(_.get() => {kind: KTypeParameter(_)}, _) | TAnonymous(_) |
        TDynamic(_) | TMono(_):
        true;
      case _:
        false;
    }
  }

  public static function isDynamicIterator(x: TypedExpr): Bool
    return isDynamicType(x.t);

  public static function posInfo(fields: Array<{name: String, expr: TypedExpr}>)
    return switch [fields[0], fields[1]] {
      case [
        {name: 'fileName', expr: {expr: TConst(TString(file))}},
        {name: 'lineNumber', expr: {expr: TConst(TInt(line))}}
      ]:
        {file: file, line: line}
      case _: null;
    }

  public static function with(e: TypedExpr, ?edef: TypedExprDef, ?t: Type) {
    return {
      expr: edef == null ? e.expr : edef,
      pos: e.pos,
      t: t == null ? e.t : t
    }
  }

  public static function isRest(type: Type) {
    return switch type {
      case TType(_.get() => {module: 'haxe.extern.Rest', name: 'Rest'}, _) |
        TAbstract(_.get() => {module: 'haxe.Rest', name: 'Rest'}, _):
        true;
      default:
        false;
    }
  }

  public static function moduleTypeModule(module: ModuleType) {
    return switch module {
      case TClassDecl(_.get() => {module: module}): module;
      case TEnumDecl(_.get() => {module: module}): module;
      case TTypeDecl(_.get() => {module: module}): module;
      default: '';
    }
  }

  public static function moduleTypeName(module: ModuleType) {
    return switch module {
      case TClassDecl(_.get() => cl): className(cl);
      case TEnumDecl(_.get() => {name: name}): name;
      case TTypeDecl(_.get() => {name: name}): name;
      default: '';
    }
  }

  public static function baseTypeName(base: BaseType) {
    if (Reflect.hasField(base, 'kind'))
      return className(cast base);
    return base.name;
  }

  public static function typeName(module: Type) {
    return switch module {
      case TInst(_.get() => cl, _): className(cl);
      default: typeToBaseType(module).name;
    }
  }

  public static function className(cl: ClassType) {
    return switch cl {
      case {kind: KAbstractImpl(_.get() => a), meta: meta}
        if (!meta.has(':native')):
        a.name;
      default: cl.name;
    }
  }

  public static function typesInExpr(e: TypedExpr): Array<ModuleType> {
    return switch e {
      case null: [];
      case {
        expr: TCall(call = {
          expr: TField(_,
            FStatic(_.get() => {module: 'genes.Genes'},
              _.get() => {name: 'ignore'}))
        }, [{expr: TArrayDecl(texprs)}, func])
      }:
        final names = [
          for (texpr in texprs)
            switch texpr {
              case {expr: TConst(TString(name))}:
                name;
              case _:
                continue; // TODO: should error
            }
        ];
        typesInExpr(call).concat(typesInExpr(func).filter(type -> {
          return switch type {
            case TClassDecl(TInst(_, []).toString() => name) |
              TEnumDecl(TEnum(_, []).toString() => name):
              names.indexOf(name) < 0;
            default: true;
          }
        }));
      case {expr: TTypeExpr(t)}:
        [t];
      case {expr: TNew(c, _, el)}:
        var res = [TClassDecl(c)];
        for (e in el)
          res = res.concat(typesInExpr(e));
        res;
      case {expr: TCast(e, null)}:
        typesInExpr(e);
      case {expr: TCast(e, t)}:
        typesInExpr(e)
          .concat([t, bootType]); // include js.Boot for js.Boot.__cast()
      case e:
        var res = [];
        e.iter(e -> {
          res = res.concat(typesInExpr(e));
        });
        res;
    }
  }
}
