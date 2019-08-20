package genes.generator.dts;

import haxe.io.Path;
import genes.Module;
import haxe.macro.Type;
import haxe.macro.JSGenApi;
import genes.SourceNode;
import genes.SourceNode.*;
import genes.generator.es.ExprGenerator.*;

class DefinitionGenerator {
  public static function module(api: JSGenApi,
      save: (path: String, content: String) -> Void, module: Module) {
    final dependencies: Map<String, String> = new Map();
    var types: Array<SourceNode> = [];

    trace(module.path);
    // trace(haxe.macro.Context.getModule(module.path.split('/').join('.')));
  }
}
