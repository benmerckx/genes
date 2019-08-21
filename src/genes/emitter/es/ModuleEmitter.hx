package genes.emitter.es;

import genes.Emitter;
import genes.Module;
import haxe.macro.Type;

class ModuleEmitter extends ExprEmitter {
  public function emitModule(module: Module) {
    for (module => imports in module.dependencies)
      emitImports(module, imports);
    for (member in module.members)
      switch member {
        case MClass(cl, _, fields):
          emitClass(cl, fields);
        case MEnum(et, _):
          emitEnum(et);
        case MMain(e):
          emitExpr(e);
        default:
      }
    writer.close();
    sourceMap.write();
  }

  function emitImports(module: String, imports: Array<Dependency>) {
    for (def in imports.filter(d -> d.type.equals(DDefault)))
      emitImport([def], module);
    final named = imports.filter(d -> d.type.equals(DName));
    if (named.length > 0)
      emitImport(named, module);
  }

  function emitImport(what: Array<Dependency>, where: String) {
    write('import');
    writeSpace();
    switch what {
      case [def = {type: DependencyType.DDefault}]:
        write(if (def.alias != null) def.alias else def.name);
      case defs:
        write('{');
        write(defs.map(def -> def.name + if (def.alias != null) ' as ${def.alias}' else '')
          .join(', '));
        write('}');
    }
    writeSpace();
    write('from');
    writeSpace();
    emitString(where);
    writeNewline();
  }

  function emitClass(cl: ClassType, fields: Array<Field>) {
    if (cl.isInterface)
      return;
    emitPos(cl.pos);
    writeNewline();
    write('export class ');
    write(cl.name);
    write(switch cl.superClass {
      case null: '';
      case {t: t}: ' extends ${t.get().name}';
    });
    write(' {');
    increaseIndent();
    writeNewline();
    for (field in fields)
      switch field.kind {
        case Constructor | Method:
          switch field.expr.expr {
            case TFunction(f):
              emitPos(field.pos);
              if (field.isStatic)
                write('static ');
              write(field.name);
              write('(');
              for (arg in join(f.args, write.bind(', ')))
                emitIdent(arg.v.name);
              write(') ');
              emitExpr(f.expr);
              writeNewline();
            default: throw 'assert';
          }
        default:
      }
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();
    for (field in fields)
      switch field.kind {
        case Property if (field.isStatic && field.expr != null):
          writeNewline();
          emitPos(field.pos);
          emitIdent(cl.name);
          emitField(field.name);
          write(' = ');
          switch field.expr {
            case e: emitValue(e);
          }
        default:
      }
    if (cl.init != null) {
      emitExpr(cl.init);
      writeNewline();
    }
  }

  function emitEnum(et: EnumType) {
    final id = et.pack.concat([et.name]).join('.');
    emitPos(et.pos);
    writeNewline();
    write('export const ');
    write(et.name);
    write(' = ');
    writeNewline();
    writehxEnums();
    write('[');
    emitString(et.name);
    write(']');
    write(' = ');
    writeNewline();
    write('{');
    increaseIndent();
    writeNewline();
    if (ctx.hasFeature('js.Boot.isEnum')) {
      write('__ename__: "${id}",');
      writeNewline();
    }
    write('__constructs__: [');
    for (c in joinIt(et.constructs.keys(), write.bind(', ')))
      emitString(c);
    write('],');
    writeNewline();
    for (name => c in joinIt(et.constructs.keyValueIterator(), () -> {
      write(',');
      writeNewline();
    })) {
      emitPos(c.pos);
      write(name);
      write(': ');
      write(switch c.type {
        case TFun(args, ret):
          final params = args.map(param -> param.name).join(', ');
          final paramsQuoted = args.map(param -> '"${param.name}"').join(', ');
          'Object.assign(($params) => ({_hx_index: ${c.index}, __enum__: "${id}", $params}), {__params__: [$paramsQuoted]})';
        default:
          '{_hx_index: ${c.index}, __enum__: "${id}"}';
      });
    }
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();
  }
}
