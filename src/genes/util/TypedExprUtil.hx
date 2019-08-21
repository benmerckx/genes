package genes.util;

import haxe.macro.Expr.Position;
import haxe.macro.Type;

class TypedExprUtil {
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

  public static function isDynamicIterator(ctx: genes.Context, e: TypedExpr): Bool
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
}
