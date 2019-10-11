package genes;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import genes.util.PathUtil;
import genes.util.TypeUtil;

using haxe.macro.TypeTools;
#end

class Genes {
  macro public static function dynamicImport<T, R>(expr: ExprOf<T->
    R>): ExprOf<js.lib.Promise<R>> {
    return switch expr.expr {
      case EFunction(_, {args: [arg], expr: body}):
        final name = arg.name;
        final type = Context.getType(name);
        final current = Context.getLocalClass().get().module;
        final to = TypeUtil.moduleTypeName(TypeUtil.typeToModuleType(type));
        final path = PathUtil.relative(current.replace('.', '/'), to.replace('.', '/'));
        final ret = Context.typeExpr(body).t.toComplexType();
        macro(js.Syntax.code('import({0})', $v{path})
          .then(genes.Genes.ignore($v{name}, function(module) {
          js.Syntax.code('var $name = module.$name');
          $body;
        })) : js.lib.Promise<$ret>);
      default:
        Context.error('Cannot import', expr.pos);
    }
  }

  public static function ignore<T>(name: String, res: T)
    return res;
}
