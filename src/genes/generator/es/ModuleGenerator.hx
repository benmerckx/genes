package genes.generator.es;

import genes.Module;
import haxe.macro.Type;
import haxe.macro.JSGenApi;
import genes.SourceNode;
import genes.SourceNode.*;

class ModuleGenerator {
  public static function module(api: JSGenApi, module: Module) {
    final dependencies = module.dependencies;
    final imports: SourceNode = join([
      for (module => names in dependencies)
        importOf(module, names)
    ], newline);
    final source: SourceNode = [
      imports,
      newline,
      module.members.map(member ->
        switch member {
          case MClass(cl, fields): createClass(cl, fields);
          case MEnum(_): null;
        }
      )
    ];
    final generated = source.toStringWithSourceMap({
      expr: api.generateStatement,
      value: api.generateValue,
      hasFeature: api.hasFeature,
      addFeature: api.addFeature
    });
    trace(generated.code);
  }

  static function importOf(module: String, names: Array<String>): SourceNode
    return 'import {${names.join(', ')}} from "$module"';

  static function createClass(cl: ClassType, fields: Array<Field>): SourceNode
    return '';
}