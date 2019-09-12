package genes;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.JSGenApi;
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.io.Path;
import genes.es.ModuleEmitter;
import genes.dts.DefinitionEmitter;
import genes.Module;

using Lambda;
using StringTools;

class Generator {
  static function generate(api: JSGenApi) {
    final reExport = !Context.defined('genes_modules');
    final toGenerate = typesPerModule(api.types);
    final output = Path.withoutExtension(Path.withoutDirectory(api.outputFile));
    final modules = new Map();
    function addModule(module: String, types: Array<Type>,
        ?main: Null<TypedExpr>) {
      if (reExport) {
        final exports = [];
        for (type in types) {
          final path = switch type {
            case TInst(_.get() => {
              pack: pack,
              name: name
            }, _) | TEnum(_.get() => {
                pack: pack,
                name: name
              }, _) | TAbstract(_.get() => {pack: pack, name: name}, _):
              pack.concat([name]).join('.');
            default: throw 'assert';
          }
          if (path == module) {
            exports.push(Type(type));
          } else {
            modules.set(path, new Module(module, [Type(type)]));
            switch type {
              case TInst(_.get().isInterface => true, _) | TType(_, _):
              default:
                if (path.indexOf('TestSuiteBase') > -1)
                  trace(type);
                exports.push(External(path));
            }
          }
        }
        modules.set(module, new Module(module, exports, main));
      } else {
        modules.set(module, new Module(module, types.map(t -> Type(t)), main));
      }
    }
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
    for (path => module in modules) {
      switch testCycles(module.module, module.module, []) {
        case []:
        case v:
          Context.warning('Circular dependency: ${v.join(' => ')}', Context.currentPos());
      }
      generateModule(api, path.split('.').join('/'), module);
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

  static function generateModule(api: JSGenApi, path: String, module: Module) {
    final generateSourceMaps = Context.defined('debug') || Context.defined('js_source_map') || Context.defined('source_map');
    final generateDefinitions = Context.defined('dts');
    final outputDir = Path.directory(api.outputFile);
    final extension = Path.extension(api.outputFile);
    final path = [Path.join([outputDir, path]), extension].join('.');
    final definition = [Path.join([outputDir, path]), 'd.ts'].join('.');
    final ctx = module.createContext(api);
    final moduleEmitter = new ModuleEmitter(ctx, Writer.fileWriter(path));
    moduleEmitter.emitModule(module);
    if (generateSourceMaps)
      moduleEmitter.emitSourceMap(path + '.map', true);
    moduleEmitter.finish();
    if (generateDefinitions) {
      final definitionEmitter = new DefinitionEmitter(ctx, Writer.fileWriter(definition));
      definitionEmitter.emitDefinition(module);
      if (generateSourceMaps)
        definitionEmitter.emitSourceMap(definition + '.map');
      definitionEmitter.finish();
    }
  }

  #if macro
  public static function use() {
    Compiler.setCustomJSGenerator(Generator.generate);
  }
  #end
}
