package genes.generator.es;

import haxe.io.Path;
import genes.Module;
import haxe.macro.Type;
import haxe.macro.JSGenApi;
import genes.SourceNode;
import genes.SourceNode.*;
import genes.generator.es.ExprGenerator.*;

class ModuleGenerator {
  public static function module(api: JSGenApi,
      save: (path: String, content: String) -> Void, module: Module) {
    final dependencies = module.dependencies;
    final imports: SourceNode = join([
      for (module => imports in dependencies)
        importOf(module, imports)
    ], newline);
    final members: SourceNode = module.members.map(member -> switch member {
      case MClass(cl, _, fields): createClass(cl, fields);
      case MEnum(et, _): createEnum(et);
      case MMain(e): expr(e);
      default: SourceNode.EMPTY;
    });
    if (members.isEmpty())
      return;
    final source: SourceNode = [imports, newline, newline, members];
    final extension = Path.extension(api.outputFile);
    final output = if (extension == '') module.path else
      [module.path, extension].join('.');
    final generated = source.toStringWithSourceMap(output, {
      expr: api.generateStatement,
      value: api.generateValue,
      hasFeature: api.hasFeature,
      addFeature: api.addFeature,
      typeAccessor: module.typeAccessor
    });
    save(output, generated.code + '\n\n//# sourceMappingURL=$output.map');
    save('$output.map', haxe.Json.stringify(generated.map));
  }

  static function importOf(module: String,
      imports: Array<Dependency>): SourceNode {
    inline function require(what: String): SourceNode
      return 'import $what from "$module"';
    final named = imports.filter(d -> d.type.equals(DName));
    return join(imports.filter(d -> d.type.equals(DDefault))
      .map(d -> require(if (d.alias != null) d.alias else d.name)).concat([
      if (named.length > 0)
        require('{' +
            named.map(d -> d.name + if (d.alias != null) ' as ${d.alias}' else '')
              .join(', ') + '}')
      else
        SourceNode.EMPTY
    ]), newline);
  }

  static function createClass(cl: ClassType,
      fields: Array<Field>): SourceNode {
    if (cl.isInterface)
      return SourceNode.EMPTY;
    final visibility = cl.isPrivate ? '' : 'export ';
    final extend = switch cl.superClass {
      case null: '';
      case {t: t}: ' extends ${t.get().name}';
    }
    return node(cl.pos, [
      'export class ${cl.name}${extend} {',
      indent([
        newline,
        join(fields.map(function(field): SourceNode return switch field.kind {
          case Constructor | Method:
            switch field.expr.expr {
              case TFunction(f):
                node(field.pos, [
                  field.isStatic ? 'static ' : '',
                  '${field.name}(',
                  join(f.args.map(a -> ident(a.v.name)), ', '),
                  ') ',
                  expr(f.expr)
                ]);
              default: throw 'assert';
            }
          case Property: '';
        }),
          newline)
      ]),
      newline,
      '}',
      newline,
      join(fields.map(function(field): SourceNode return switch field.kind {
        case Property if (field.isStatic && field.expr != null):
          node(field.pos, [
            '${cl.name}.${field.name}',
            switch field.expr {
              case e:
                [' = ', value(e)];
            }
          ]);
        default: '';
      }), newline),
      newline,
      cl.init == null ? '' : [expr(cl.init), newline]
    ]);
  }

  static function createEnum(et: EnumType): SourceNode {
    final visibility = et.isPrivate ? '' : 'export ';
    final id = et.pack.concat([et.name]).join('.');
    return node(et.pos, [
      newline,
      'export const ${et.name} = \n${hxEnums}["${et.name}"] = \n{',
      indent([
        newline,
        read(ctx -> if (ctx.hasFeature('js.Boot.isEnum')) '__ename__: "${id}",' else ''),
        newline,
        '__constructs__: [',
        join([
          for (c in et.constructs.keys())
            '"$c"'
        ], ', '),
        '],',
        newline,
        [
          for (name => c in et.constructs)
            node(c.pos, name, ': ', switch c.type {
              case TFun(args, ret):
                final params = args.map(param -> param.name).join(', ');
                final paramsQuoted = args.map(param -> '"${param.name}"')
                  .join(', ');
                'Object.assign(($params) => ({_hx_index: ${c.index}, __enum__: "${id}", $params}), {__params__: [$paramsQuoted]})';
              default:
                '{_hx_index: ${c.index}, __enum__: "${id}"}';
            }, ',', newline)
        ]
      ]),
      newline,
      '}',
      newline
    ]);
  }
}
