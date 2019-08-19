package genes;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.JSGenApi;
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import genes.generator.es.ModuleGenerator;

using Lambda;
using StringTools;

class Generator {
  static function generate(api: JSGenApi) {
    final modules = new Map<String, Array<Type>>();
    final output = Path.withoutExtension(Path.withoutDirectory(api.outputFile));
    for (type in api.types) {
      switch type {
        // Todo: init extern inst
        case TInst(_.get() => {
          module: module,
          isExtern: false
        }, _) | TEnum(_.get() => {
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
    for (module => types in modules) {
      final path = module.replace('.', '/');
      final file = try Context.resolvePath(path + '.hx') catch (e:Dynamic) null;
      generateModule(api, path, file, types);
    }
    switch api.main {
      case null:
      // Todo: check for nameclash with above
      // Todo: get Main module out of cli args to find source file
      case v:
        generateModule(api, output, null, [], v);
    }
  }

  static function generateModule(api: JSGenApi, path: String, file: String,
      types: Array<Type>, ?main: TypedExpr) {
    final module = new Module(path, file, types, main);
    final outputDir = Path.directory(api.outputFile);
    function save(file: String, content: String) {
      final path = Path.join([outputDir, file]);
      final dir = Path.directory(path);
      if (!FileSystem.exists(dir))
        FileSystem.createDirectory(dir);
      File.saveContent(path, content);
    }
    ModuleGenerator.module(api, save, module);
  }

  #if macro
  public static function use() {
    Compiler.setCustomJSGenerator(Generator.generate);
  }
  #end
}
