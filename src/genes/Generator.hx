package genes;

import haxe.macro.JSGenApi;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.io.Path;
import genes.es.ModuleEmitter;
import genes.dts.DefinitionEmitter;
import genes.util.TypeUtil;
import genes.Module;

using Lambda;
using StringTools;

class Generator {
  @:persistent static var generation = 0;

  static function generate(api: JSGenApi) {
    final toGenerate = typesPerModule(api.types);
    final output = Path.withoutExtension(Path.withoutDirectory(api.outputFile));
    final extension = Path.extension(api.outputFile);
    Genes.outExtension = extension.length > 0 ? '.$extension' : extension;
    final modules = new Map();
    final expose: Map<String, ModuleExport> = new Map();
    final concrete = [];
    function export(export: ModuleExport) {
      if (expose.exists(export.name)) {
        final duplicate = expose.get(export.name);
        Context.warning('Trying to @:expose ${export.name} ...', export.pos);
        Context.error('... but there\'s already an export by that name',
          duplicate.pos);
      }
      expose.set(export.name, export);
    }
    for (type in api.types) {
      switch type {
        #if (haxe_ver >= 4.2)
        case TInst(_.get() => {
          kind: KModuleFields(_),
          module: module,
          statics: _.get() => fields
        }, _):
          for (field in fields) {
            if (field.meta.has(':expose'))
              export({
                name: field.name,
                pos: field.pos,
                isType: false,
                module: module
              });
          }
        #end
        default:
          final base = TypeUtil.typeToBaseType(type);
          if (base.meta.has(':expose'))
            export({
              name: base.name,
              pos: base.pos,
              isType: type.match(TType(_, _)),
              module: base.module
            });
      }
      switch type {
        case TEnum((_.get() : BaseType) => t, _) |
          TInst((_.get() : BaseType) => t, _):
          concrete.push(TypeUtil.baseTypeFullName(t));
        default:
      }
    }
    final context = {
      concrete: concrete,
      modules: modules
    }
    function addModule(module: String, types: Array<Type>,
        ?main: Null<TypedExpr>, ?expose: Array<ModuleExport>)
      modules.set(module, new Module(context, module, types, main, expose));

    addModule(output, switch toGenerate.get(output) {
      case null: [];
      case v: v;
    }, api.main, [for (t in expose) t]);

    for (module => types in toGenerate) {
      if (module.toLowerCase() == output.toLowerCase())
        Context.error('Genes: Module name "${module}" is the same as the output file name "${output}".',
          Context.currentPos());
      addModule(module, types);
    }
    for (module in modules) {
      if (needsGen(module))
        generateModule(api, module);
    }
  }

  static function needsGen(module: Module) {
    if (module.expose.length > 0)
      return true;
    for (member in module.members) {
      switch member {
        case MClass({meta: meta}, _, _) | MEnum({meta: meta}, _) |
          MType({meta: meta}, _):
          switch meta.extract(':genes.generate') {
            case [{params: [{expr: EConst(CInt(gen))}]}]:
              return true;
            default:
          }
        case MMain(_):
          return true;
      }
    }
    return false;
  }

  static function typesPerModule(types: Array<Type>) {
    final modules = new Map<String, Array<Type>>();
    for (type in types) {
      switch type {
        case TInst(_.get() => {
          module: module,
          isExtern: true,
          init: init
        }, _) if (init != null):
          #if (genes.extern_init_warning)
          Context.warning('Extern __init__ methods are not supported in genes. See https://github.com/benmerckx/genes/issues/13.',
            init.pos);
          #end
        case TInst(_.get() => {
          module: module,
          isExtern: false
        }, _) | TEnum(_.get() => {
          module: module,
          isExtern: false
        }, _) | TType(_.get() => {
          module: module
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
    final path = Path.join([outputDir, module.path]) + Genes.outExtension;
    final definition = [Path.join([outputDir, module.path]), 'd.ts'].join('.');
    final ctx = module.createContext(api);
    final moduleEmitter = new ModuleEmitter(ctx,
      Writer.bufferedFileWriter(path));
    moduleEmitter.emitModule(module, Genes.outExtension);
    #if (debug || js_source_map)
    moduleEmitter.emitSourceMap(path + '.map', true);
    #end
    moduleEmitter.finish();
    #if dts
    final definitionEmitter = new DefinitionEmitter(ctx,
      Writer.bufferedFileWriter(definition));
    definitionEmitter.emitDefinition(module);
    #if (debug || js_source_map)
    definitionEmitter.emitSourceMap(definition + '.map', true);
    #end
    definitionEmitter.finish();
    #end
  }

  #if macro
  public static function use() {
    #if !genes.disable
    if (Context.defined('js')) {
      Compiler.include('genes.Register');
      Context.onGenerate(types -> {
        generation++;
        final pos = Context.currentPos();
        for (type in types) {
          switch type {
            case TEnum((_.get() : BaseType) => base, _) |
              TInst((_.get() : BaseType) => base, _) |
              TType((_.get() : BaseType) => base, _):
              base.meta.add(':genes.generate', [
                {
                  expr: ExprDef.EConst(CInt(Std.string(generation))),
                  pos: pos
                }
              ], pos);
            default:
          }
        }
      });
      Compiler.setCustomJSGenerator(Generator.generate);
    }
    #end
  }
  #end
}
