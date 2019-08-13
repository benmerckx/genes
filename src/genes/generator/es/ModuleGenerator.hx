package genes.generator.es;

import genes.Module;
import haxe.macro.Type;
import haxe.macro.JSGenApi;
import genes.SourceNode;
import genes.SourceNode.*;
import genes.generator.es.ExprGenerator.*;

class ModuleGenerator {
  public static function module(api: JSGenApi, save: (path: String, content: String) -> Void, module: Module) {
    final dependencies = module.dependencies;
    final imports: SourceNode = join([
      for (module => names in dependencies)
        importOf(module, names)
    ], newline);
    final members = module.members.map(member ->
      switch member {
        case MClass(cl, fields): createClass(cl, fields);
        case MEnum(_): null;
        case MMain(e): expr(e);
      }
    );
    final source: SourceNode = [
      imports,
      newline,
      newline,
      members
    ];
    final generated = source.toStringWithSourceMap({
      expr: api.generateStatement,
      value: api.generateValue,
      hasFeature: api.hasFeature,
      addFeature: api.addFeature
    });
    save(module.path + '.js', generated.code);
  }

  static function importOf(module: String, names: Array<String>): SourceNode
    return 'import {${names.join(', ')}} from "$module"';

  static function createClass(cl: ClassType, fields: Array<Field>): SourceNode {
    if (cl.isInterface) return '';
    final visibility = cl.isPrivate ? '' : 'export';
    final extend = switch cl.superClass {
      case null: '';
      case {t: t}: ' extends ${t.get().name}';
    }
    return [
      '$visibility class ${cl.name}${extend} {',
        indent([
          newline,
          join(fields.map(function (field): SourceNode
            return switch field.kind {
              case Constructor | Method:
                switch field.expr.expr {
                  case TFunction(f):
                    [
                      field.isStatic ? 'static ' : '',
                      '${field.name} (', join(f.args.map(a -> ident(a.v.name)), ', '), ') ',
                        expr(f.expr)
                    ];
                  default: throw 'assert';
                }
              case Property: [
                field.isStatic ? 'static ' : '',
                '${field.name}', 
                switch field.expr {
                  case null: [];
                  case e: [' = ', value(e)];
                }
              ];
            }
          ), newline)
        ]),
      newline, '}', newline,
      cl.init == null ? '' : [expr(cl.init), newline]
    ];
  }
}