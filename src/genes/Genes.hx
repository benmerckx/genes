package genes;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import genes.util.PathUtil;
import genes.util.TypeUtil;

using haxe.macro.TypeTools;
using Lambda;

private typedef ImportedModule = {
  name: String,
  importExpr: Expr,
  types: Array<{
    name: String,
    fullname: String,
    type: haxe.macro.Type
  }>
}
#end

class Genes {
  @:persistent public static var outExtension: String = '.js';

  macro public static function dynamicImport<T, R>(expr: ExprOf<T->
    R>): ExprOf<js.lib.Promise<R>> {
    final pos = Context.currentPos();

    return switch expr.expr {
      case EFunction(_, {args: args, expr: body}):
        final current = Context.getLocalClass().get().module;
        final ret = switch Context.typeExpr(body).t.toComplexType() {
          case null: (macro:Dynamic);
          case v: v;
        }

        final modules: Array<ImportedModule> = [];

        for (arg in args) {
          final type = Context.followWithAbstracts(Context.getType(arg.name));
          final fullname = type.toString();
          final name = fullname.split('.').pop();
          final module = TypeUtil.moduleTypeModule(TypeUtil.typeToModuleType(type));

          switch modules.find(m -> m.name == module) {
            case null:
              modules.push({
                name: module,
                importExpr: {
                  final path = PathUtil.relative(current.replace('.', '/'),
                    module.replace('.', '/'))
                  #if !genes.no_extension
                  + outExtension
                  #end
                  ;
                  macro js.Syntax.code('import({0})', $v{path});
                },
                types: [
                  {
                    name: name,
                    fullname: fullname,
                    type: type
                  }
                ]
              });
            case module:
              module.types.push({name: name, fullname: fullname, type: type});
          }
        }

        final e = switch modules {
          case [module]:
            final setup = [
              for (sub in module.types)
                macro js.Syntax.code($v{'var ${sub.name} = module.${sub.name}'})
            ];

            final list = [for (sub in module.types) macro $v{sub.fullname}];

            final handler = macro genes.Genes.ignore($a{list},
              function(module) {
                @:mergeBlock $b{setup};
                $body;
              });

            macro ${module.importExpr}.then($handler);

          default:
            final setup = [];
            final ignores = [];

            for (i in 0...modules.length) {
              for (sub in modules[i].types) {
                setup.push(macro js.Syntax.code($v{'var ${sub.name} = modules[$i].${sub.name}'}));
                ignores.push(macro $v{sub.fullname});
              }
            }

            final imports = macro $a{modules.map(module -> module.importExpr)};
            macro js.lib.Promise.all($imports)
              .then(genes.Genes.ignore($a{ignores}, function(modules) {
                @:mergeBlock $b{setup};
                $body;
              }));
        }

        macro($e : js.lib.Promise<$ret>);

      default:
        Context.error('Cannot import', expr.pos);
    }
  }

  public static function ignore<T>(names: Array<String>, res: T)
    return res;
}
