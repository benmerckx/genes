package genes;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.JSGenApi;
import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.io.Path;
import genes.es.ModuleEmitter;
import genes.dts.DefinitionEmitter;
import genes.util.Timer.timer;

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
    function testCycles(initial: String, test: String, seen: Array<String>) {
      seen = seen.concat([test]);
      final dependencies = switch modules[test] {
        case null: [];
        case v: [for (k in v.codeDependencies.imports.keys()) k];
      }
      for (dependency in dependencies) {
        if (seen.indexOf(dependency) > -1) {
          if (dependency == initial)
            return [test, dependency];
          else
            continue;
        }
        final cycles = testCycles(initial, dependency, seen);
        if (cycles.length > 0) {
          return cycles;
        }
      }
      return [];
    }
    for (module in modules) {
      /** // Todo: move detection to module and only defer if a cycle is detected
        final endTimer = timer('cycles');
        switch testCycles(module.module, module.module, []) {
          case []:
          case v:
            Context.warning('Circular dependency: ${v.join(' => ')}', Context.currentPos());
        }
        endTimer();
      **/
      generateModule(api, module);
    }
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
          }, _) /*| TType(_.get() => {
            module: module,
            isExtern: false
          }, _)*/:
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
    final definition = [Path.join([outputDir, module.path]), 'd.ts'].join('.');
    final ctx = module.createContext(api);
    final moduleEmitter = new ModuleEmitter(ctx, Writer.fileWriter(path));
    moduleEmitter.emitModule(module);
    #if (debug || js_source_map)
    moduleEmitter.emitSourceMap(path + '.map', true);
    #end
    moduleEmitter.finish();
    #if dts
    final definitionEmitter = new DefinitionEmitter(ctx, Writer.fileWriter(definition));
    definitionEmitter.emitDefinition(module);
    #if (debug || js_source_map)
    definitionEmitter.emitSourceMap(definition + '.map');
    #end
    definitionEmitter.finish();
    #end
  }

  #if macro
  public static function use() {
    Compiler.setCustomJSGenerator(Generator.generate);
  }
  #end
}
