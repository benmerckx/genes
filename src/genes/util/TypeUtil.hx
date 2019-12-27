package genes.util;

import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;

using haxe.macro.TypedExprTools;

class TypeUtil {
  public static function typeToModuleType(type: Type): ModuleType
    return switch type {
      case TEnum(r, _): TEnumDecl(r);
      case TInst(r, _): TClassDecl(r);
      case TType(r, _): TTypeDecl(r);
      case TAbstract(r, _): TAbstract(r);
      case _: null;
    }

  public static function toBaseType(type: Type) {
    return switch type {
      case TEnum((_.get() : BaseType) => base,
        _) | TInst((_.get() : BaseType) => base, _) | TType((_.get() : BaseType) => base, _) | TAbstract((_.get() : BaseType) => base, _):
        base;
      default:
        throw 'Could not convert $type to BaseType';
    }
  }

  public static function getModuleType(module: String)
    return typeToModuleType(haxe.macro.Context.getType(module));

  public static function baseTypeName(type: BaseType) {
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

  public static function isDynamicIterator(ctx: genes.Context,
      e: TypedExpr): Bool
    return switch e.expr {
      case TField(x, f) if (fieldName(f) == "iterator" && ctx.hasFeature('HxOverrides.iter')):
        switch haxe.macro.Context.followWithAbstracts(x.t) {
          case TInst(_.get() => {name: 'Array'}, _) | TInst(_.get() => {kind: KTypeParameter(_)}, _) | TAnonymous(_) | TDynamic(_) | TMono(_):
            true;
          case _:
            false;
        }
      case _:
        false;
    }

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

  public static function moduleTypeName(module: ModuleType) {
    return switch module {
      case TClassDecl(_.get() => {module: module}): module;
      case TEnumDecl(_.get() => {module: module}): module;
      case TTypeDecl(_.get() => {module: module}): module;
      default: '';
    }
  }

  public static function typesInExpr(e: TypedExpr): Array<ModuleType> {
    return switch e {
      case null: [];
      case {
        expr: TCall(call = {
          expr: TField(_, FStatic(_.get() => {module: 'genes.Genes'}, _.get() => {name: 'ignore'}))
        }, [{expr: TConst(TString(name))}, func])
      }:
        typesInExpr(call).concat(typesInExpr(func).filter(type -> {
          return switch type {
            case TClassDecl(_.get() => {name: typeName}):
              typeName != name;
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
      case {expr: TField(x, f)}
        if (fieldName(f) == "iterator"): // Todo: conditions here could be refined
        [getModuleType('HxOverrides')].concat(typesInExpr(x));
      case e:
        var res = [];
        e.iter(e -> {
          res = res.concat(typesInExpr(e));
        });
        res;
    }
  }

  public static function iterType(type: Type, it: (type: Type) -> Void) {
    it(type);
    switch type {
      case TAnonymous(_.get() => a):
        for (field in a.fields)
          if (field.type != type)
            iterType(field.type, it);
      case TEnum(_, params) | TInst(_, params):
        for (t in params)
          if (t != type)
            iterType(t, it);
      case TType(_, params) | TAbstract(_, params):
        final next = Context.followWithAbstracts(type);
        if (!Context.unify(next, type))
          iterType(next, it);
        else
          it(next);
        for (t in params)
          if (t != type)
            iterType(t, it);
      case TFun(args, ret):
        for (arg in args)
          if (arg.t != type)
            iterType(arg.t, it);
        if (ret != type)
          iterType(ret, it);
      default:
    }
  }
}
