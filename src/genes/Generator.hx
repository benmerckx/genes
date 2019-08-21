package genes;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.JSGenApi;
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.io.Path;
import genes.emitter.es.ModuleEmitter;
import genes.emitter.dts.DefinitionEmitter;

using Lambda;
using StringTools;

class Generator {
  static function generate(api: JSGenApi) {
    final toGenerate = typesPerModule(api.types);
    final output = Path.withoutExtension(Path.withoutDirectory(api.outputFile));
    final modules = new Map();
    function addModule(module: String, types: Array<Type>,
        ?main: Null<TypedExpr>)
      modules.set(module, new Module(module, types, main));
    switch api.main {
      case null:
      case v:
        addModule(output, switch toGenerate.get(output) {
          case null: [];
          case v: v;
        }, v);
    }
    for (module => types in toGenerate)
      if (module != output)
        addModule(module, types);
    for (module in modules)
      generateModule(api, module);
    return modules;
  }

  static function typesPerModule(types: Array<Type>) {
    final modules = new Map<String, Array<Type>>();
    for (type in types) {
      switch type {
        // Todo: init extern inst
        case TInst(_.get() => {
          module: module,
          isExtern: false
        }, _) | TEnum(_.get() => {
            module: module,
            isExtern: false
          }, _) | TType(_.get() => {
            module: module,
            isExtern: false
          }, _):
          if (modules.exists(module))
            modules.get(module).push(type);
          else
            modules.set(module, [type]);
        default:
      }
    }
    return modules;
  }

  static function generateModule(api: JSGenApi, module: Module) {
    final outputDir = Path.directory(api.outputFile);
    final extension = Path.extension(api.outputFile);
    final path = [Path.join([outputDir, module.path]), extension].join('.');
    final ctx = module.createContext(api);
    final moduleEmitter = new ModuleEmitter(ctx, Writer.fileWriter(path), new SourceMapGenerator(path + '.map'));
    moduleEmitter.emitModule(module);
  }

  #if macro
  public static function use() {
    Compiler.setCustomJSGenerator(Generator.generate);
  }
  #end
}
