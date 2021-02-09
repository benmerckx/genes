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
    final pos = Context.currentPos();

    return switch expr.expr {
      case EFunction(_, {args: [arg], expr: body}):
        final name = arg.name;
        final type = Context.getType(name);
        final current = Context.getLocalClass().get().module;
        final to = TypeUtil.moduleTypeName(TypeUtil.typeToModuleType(type));
        final path = PathUtil.relative(current.replace('.', '/'),
          to.replace('.', '/'));
        final ret = Context.typeExpr(body).t.toComplexType();
        final setup = macro @:pos(pos) js.Syntax.code($v{'var $name = module.$name'});
        macro(js.Syntax.code('import({0})', $v{path})
          .then(genes.Genes.ignore($v{name}, function(module) {
            $setup;
            $body;
          })) : js.lib.Promise<$ret>);

      case EFunction(_, {args: args, expr: body}):
        // TODO: should be more intelligent not to generate duplicated `import` calls if referring to the same js modules (e.g. when using Haxe module sub-types)
        final ret = Context.typeExpr(body).t.toComplexType();

        final names = [];
        final setups = [];
        final imports = [];

        for (i => arg in args) {
          final name = arg.name;
          final type = Context.getType(name);
          final current = Context.getLocalClass().get().module;
          final to = TypeUtil.moduleTypeName(TypeUtil.typeToModuleType(type));
          final path = PathUtil.relative(current.replace('.', '/'),
            to.replace('.', '/'));
          names.push(macro @:pos(pos) $v{name});
          imports.push(macro @:pos(pos) js.Syntax.code('import({0})',
            $v{path}));
          setups.push(macro @:pos(pos) js.Syntax.code($v{'var $name = modules[$i].$name'}));
        }
        final importExprs = macro @:pos(pos) $a{imports};
        macro(js.lib.Promise.all($importExprs)
          .then(genes.Genes.ignoreMultiple($a{names}, function(modules) {
            @:mergeBlock $b{setups};
            $body;
          })) : js.lib.Promise<$ret>);

      default:
        Context.error('Cannot import', expr.pos);
    }
  }

  public static function ignore<T>(name: String, res: T)
    return res;

  public static function ignoreMultiple<T>(name: Array<String>, res: T)
    return res;
}
