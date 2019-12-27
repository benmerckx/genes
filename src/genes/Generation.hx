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
import genes.util.TypeUtil;
import genes.dts.TypeEmitter;

using Lambda;
using StringTools;

@:allow(genes.Module)
class Generation {
  final api: JSGenApi;
  final modules: Map<String, Module> = new Map();
  final used: Set<String> = new Set();

  public function new(api: JSGenApi) {
    this.api = api;
    createModules();
  }

  function createModules() {
    final output = Path.withoutExtension(Path.withoutDirectory(api.outputFile));
    final toGenerate = typesPerModule(api.types);
    function addModule(path: String, types: Array<Type>,
        ?main: Null<TypedExpr>) {
      for (type in api.types)
        switch type {
          case TEnum((_.get() : BaseType) => t, _) | TInst((_.get() : BaseType) => t, _):
            used.add(TypeUtil.baseTypeName(t));
          default:
        }
      final module = new Module(this, path, types, main);
      modules.set(path, module);
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
  }

  public function typeIsUsed(type: Type) {
    return try {
      TypeUtil.iterType(type, (sub: Type) -> {
        trace(haxe.macro.TypeTools.toString(sub));
        switch sub {
          case TInst(_.get() => t, _) if (!t.kind.match(KNormal)):
          case TEnum((_.get() : BaseType) => t, _) | TInst((_.get() : BaseType) => t, _):
            final name = TypeUtil.baseTypeName(t);
            if (!used.exists(name))
              throw false;
          case v:
        }
      });
      true;
    } catch (used:Bool) {
      used;
    }
  }

  public function generate() {
    final concrete = [];
    for (type in api.types)
      switch type {
        case TEnum((_.get() : BaseType) => t, _) | TInst((_.get() : BaseType) => t, _):
          concrete.push(TypeUtil.baseTypeName(t));
        default:
      }
    final context = {
      concrete: concrete,
      modules: modules
    }

    for (module in modules)
      generateModule(module);
  }

  function generateModule(module: Module) {
    final outputDir = Path.directory(api.outputFile);
    final extension = Path.extension(api.outputFile);
    final path = [Path.join([outputDir, module.path]), extension].join('.');
    final definition = [Path.join([outputDir, module.path]), 'd.ts'].join('.');
    final ctx = module.createContext(api);
    final moduleEmitter = new ModuleEmitter(ctx, Writer.bufferedFileWriter(path));
    moduleEmitter.emitModule(module);
    #if (debug || js_source_map)
    moduleEmitter.emitSourceMap(path + '.map', true);
    #end
    moduleEmitter.finish();
    #if dts
    final definitionEmitter = new DefinitionEmitter(ctx, Writer.bufferedFileWriter(definition));
    definitionEmitter.emitDefinition(module);
    #if (debug || js_source_map)
    definitionEmitter.emitSourceMap(definition + '.map');
    #end
    definitionEmitter.finish();
    #end
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
          }, _) | TType(_.get() => {module: module}, _):
          if (modules.exists(module))
            modules.get(module).push(type);
          else
            modules.set(module, [type]);
        default:
      }
    }
    return modules;
  }
}
