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
        case MEnum(et): createEnum(et);
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
    save(module.path + '.mjs', generated.code);
  }

  static function importOf(module: String, names: Array<String>): SourceNode
    return 'import {${names.join(', ')}} from "$module"';

  /*static function rewriteConstructor(e: TypedExpr): TypedExpr {
    var hasSuper = false;
    function findSuper(e)
      switch e {
        case TConst(TSuper): hasSuper = true;
        default: e.iter(findSuper);
      }
    e.iter(findSuper);
    if (!hasSuper) return e;
    return a.map(e -> switch e {
      
    })
  }*/

  static function createClass(cl: ClassType, fields: Array<Field>): SourceNode {
    if (cl.isInterface) return '';
    final visibility = cl.isPrivate ? '' : 'export ';
    final extend = switch cl.superClass {
      case null: '';
      case {t: t}: ' extends ${t.get().name}';
    }
    return [
      'export class ${cl.name}${extend} {',
        indent([
          newline,
          join(fields.map(function (field): SourceNode
            return switch field.kind {
              case Constructor | Method:
                switch field.expr.expr {
                  case TFunction(f):
                    [
                      field.isStatic ? 'static ' : '',
                      '${field.name}(', join(f.args.map(a -> ident(a.v.name)), ', '), ') ',
                        expr(f.expr)
                    ];
                  default: throw 'assert';
                }
              case Property: '';
            }
          ), newline)
        ]),
      newline, '}', newline,
      join(fields.map(function (field): SourceNode
        return switch field.kind {
          case Property if (field.isStatic && field.expr != null): [
            '${cl.name}.${field.name}', 
            switch field.expr {
              case e: [' = ', value(e)];
            }
          ];
          default: '';
        }
      ), newline),
      newline,
      cl.init == null ? '' : [expr(cl.init), newline]
    ];
  }

  static function createEnum(et: EnumType): SourceNode {
    final visibility = et.isPrivate ? '' : 'export ';
    final id = et.pack.concat([et.name]).join('.');
    return [
      newline,
      'export const ${et.name} = {',
      indent([
        newline,
        '__ename__: "${id}",', 
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
            node(c.pos, 
              name, ': ',
              switch c.type {
                case TFun(args, ret):
                  final params = args.map(param -> param.name).join(', ');
                  final paramsQuoted = args.map(param -> '"${param.name}"').join(', ');
                  'Object.assign(($params) => ({_hx_index: ${c.index}, __enum__: "${id}", $params}), {__params__: [$paramsQuoted]})';
                default: 
                  '{_hx_index: ${c.index}, __enum__: "${id}"}';
              },
              ',',
              newline
            )
        ]
      ]),
      newline,
      '}',
      newline
    ];
  }
}

/*{ __ename__ : "helder.query.Target", __constructs__ : 
  ["Channel"]
  ,
  Channel: ($_=function(name) { return {_hx_index:0,name:name,__enum__:"helder.query.Target",toString:$estr}; },
  $_.__params__ = ["name"],$_)
}*/