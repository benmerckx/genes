package genes.dts;

import haxe.io.Path;
import genes.es.ModuleEmitter;
import haxe.macro.Type;
import genes.Module;
import genes.util.TypeUtil;
import genes.util.IteratorUtil.*;
import genes.dts.TypeEmitter;

class DefinitionEmitter extends ModuleEmitter {
  public function emitDefinition(module: Module) {
    final dependencies = module.typeDependencies();
    ctx.typeAccessor = dependencies.typeAccessor;
    for (module => imports in dependencies.imports)
      emitImports(module, imports);
    for (member in module.members)
      switch member {
        case MClass(cl, params, fields):
          emitClassDefinition(cl, params, fields);
        case MEnum(et, params):
          emitEnumDefinition(et, params);
        /*case MType(def, params):
          emitTypeDefinition(def, params); */
        default:
      }
  }

  function emitEnumDefinition(et: EnumType, params: Array<Type>) {
    final id = et.pack.concat([et.name]).join('.');
    writeNewline();
    write('export declare type ');
    emitPos(et.pos);
    emitBaseType(et, params);
    emitPos(et.pos);
    write(' = ');
    increaseIndent();
    for (name => c in et.constructs) {
      writeNewline();
      write('| ');
      emitPos(c.pos);
      write('{_hx_index: ${c.index}');
      switch c.type {
        case TFun(args, ret):
          for (arg in args) {
            write(', ');
            emitIdent(arg.name);
            write(': ');
            emitType(arg.t);
          }
        default:
      }
      write(', __enum__: "${id}"}');
      write('  // ' + name);
    }
    decreaseIndent();
    writeNewline();
  }

  /*function emitTypeDefinition(def: DefType, params: Array<Type>) {
    emitPos(def.pos);
    writeNewline();
    write('export declare type ');
    emitBaseType(def, params);
  }*/
  function emitClassDefinition(cl: ClassType, params: Array<Type>,
      fields: Array<Field>) {
    writeNewline();
    write('export declare ');
    write(if (cl.isInterface) 'interface' else 'class');
    writeSpace();
    emitPos(cl.pos);
    emitBaseType(cl, params);
    emitPos(cl.pos);
    switch cl.superClass {
      case null:
      case {t: t, params: params}:
        write(' extends ');
        emitBaseType(t.get(), params);
    }
    switch cl.interfaces {
      case null | []:
      case interfaces:
        if (cl.isInterface)
          write(' extends ');
        else
          write(' implements ');
        for (int in join(interfaces, write.bind(', ')))
          emitBaseType(int.t.get(), int.params);
    }
    write(' {');
    increaseIndent();
    for (field in fields)
      switch field.kind {
        case Constructor | Method:
          switch field.type {
            case TFun(args, ret):
              writeNewline();
              if (field.isStatic)
                write('static ');
              emitPos(field.pos);
              write(field.name);
              if (field.params.length > 0) {
                write('<');
                for (param in join(field.params, write.bind(', ')))
                  write(param.name);
                write('>');
              }
              write('(');
              var optionalPos = args.length;
              for (i in 0...args.length) {
                final fromEnd = args.length - 1 - i;
                if (args[fromEnd].opt)
                  optionalPos = fromEnd;
                else
                  break;
              }
              for (i in joinIt(0...args.length, write.bind(', '))) {
                final arg = args[i];
                emitIdent(arg.name);
                if (arg.opt && i >= optionalPos)
                  write('?');
                write(': ');
                emitType(arg.t);
              }
              write(')');
              if (!field.kind.match(Constructor)) {
                write(': ');
                emitType(ret);
              }
            default: throw 'assert';
          }
        case Property:
          writeNewline();
          emitPos(field.pos);
          if (field.isStatic)
            write('static ');
          write(field.name);
          write(': ');
          emitType(field.type);
      }
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();
  }

  public function includeType(type: Type) {}

  function emitBaseType(type: BaseType, params: Array<Type>) {
    TypeEmitter.emitBaseType(this, type, params);
  }

  function emitType(type: Type) {
    TypeEmitter.emitType(this, type);
  }
}