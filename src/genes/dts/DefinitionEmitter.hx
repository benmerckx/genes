package genes.dts;

import haxe.io.Path;
import genes.es.ModuleEmitter;
import haxe.macro.Type;
import genes.Module;
import genes.util.TypeUtil;
import genes.util.IteratorUtil.*;
import genes.dts.TypeEmitter;
import haxe.macro.Context;
import genes.util.Timer.timer;

class DefinitionEmitter extends ModuleEmitter {
  public function emitDefinition(module: Module) {
    final dependencies = module.typeDependencies;
    final endTimer = timer('emitDefinition');
    ctx.typeAccessor = dependencies.typeAccessor;
    for (path => imports in dependencies.imports)
      emitImports(if (imports[0].external) path else module.toPath(path),
        imports);
    for (member in module.members)
      switch member {
        #if (haxe_ver >= 4.2)
        case MClass(cl = {kind: KModuleFields(_)}, _, fields):
          emitModuleStatics(cl, fields);
        #end
        case MClass(cl, params, fields):
          emitClassDefinition(cl, params, fields);
        case MEnum(et, params):
          emitEnumDefinition(et, params);
        case MType(def, params):
          emitTypeDefinition(def, params);
        default:
      }
    for (type in module.expose) {
      final base = TypeUtil.typeToBaseType(type);
      emitExport(type, module.toPath(base.module));
    }
    endTimer();
  }

  function emitTypeDefinition(def: DefType, params: Array<Type>) {
    writeNewline();
    emitPos(def.pos);
    write('export type ');
    emitBaseType(def, params);
    write(' = ');
    emitType(def.type);
    writeNewline();
  }

  function emitEnumDefinition(et: EnumType, params: Array<Type>) {
    final id = et.pack.concat([et.name]).join('.');
    final paramNames = params.map(t -> switch t {
      case TInst(_.get().name => name, _): name;
      default: throw 'assert';
    });
    writeNewline();
    emitPos(et.pos);
    write('export declare namespace ');
    write(et.name);
    write(' {');
    increaseIndent();
    for (name => c in et.constructs) {
      writeNewline();
      emitPos(c.pos);
      write('export type ');
      write(name);
      emitParams(params);
      write(' = ');
      write('{_hx_index: ${c.index}');
      switch c.type {
        case TFun(args, ret):
          for (arg in args) {
            write(', ');
            emitIdent(arg.name);
            write(': ');
            switch arg.t {
              case TInst(_.get() => {name: name, kind: KTypeParameter([])}, []):
                if (paramNames.indexOf(name) > -1) write(name) else
                  write('any');
              default:
                emitType(arg.t);
            }
          }
        default:
      }
      write(', __enum__: "${id}"}');
      writeNewline();
      write('export const ');
      write(name);
      write(': ');
      switch c.type {
        case TFun(args, ret):
          final params = paramNames.concat(c.params.map(p -> p.name));
          if (params.length > 0) {
            write('<');
            for (param in join(params, write.bind(', ')))
              write(param);
            write('>');
          }
          write('(');
          for (arg in join(args, write.bind(', '))) {
            emitIdent(arg.name);
            write(': ');
            emitType(arg.t);
          }
          write(') => ');
          emitType(ret);
        case TEnum(_, params):
          write(name);
          if (params.length > 0) {
            write('<');
            for (param in join(params, write.bind(', ')))
              switch param {
                case TInst(_.get() => {
                  name: name,
                  kind: KTypeParameter([])
                }, []):
                  write('any');
                default:
                  emitType(param);
              }
            write('>');
          }
        default:
      }
    }
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();
    writeNewline();
    emitComment(et.doc);
    write('export declare type ');
    emitBaseType(et, params);
    write(' = ');
    increaseIndent();
    for (name => c in et.constructs) {
      writeNewline();
      emitComment(c.doc);
      write('| ');
      write(et.name);
      write('.');
      emitPos(c.pos);
      write(name);
      emitParams(params);
    }
    decreaseIndent();
    writeNewline();
  }

  function emitModuleStatics(cl: ClassType, fields: Array<Field>) {
    writeNewline();
    emitPos(cl.pos);
    for (field in fields)
      switch field {
        case {isStatic: true, isPublic: true}:
          emitPos(field.pos);
          write('export const ');
          emitIdent(field.name);
          write(': ');
          emitType(field.type);
          writeNewline();
        default:
      }
  }

  function emitClassDefinition(cl: ClassType, params: Array<Type>,
      fields: Array<Field>) {
    writeNewline();
    emitComment(cl.doc);
    emitPos(cl.pos);
    write('export declare ');
    write(if (cl.isInterface) 'interface' else 'class');
    writeSpace();
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
    for (field in fields) {
      if (field.isPublic)
        switch field.kind {
          case Constructor | Method:
            switch field.type {
              case TFun(args, ret):
                writeNewline();
                if (field.doc != null)
                  writeNewline();
                emitComment(field.doc);
                if (field.isStatic)
                  write('static ');
                emitPos(field.pos);
                write(if (field.kind.equals(Constructor)) 'constructor' else
                  field.name);
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
            if (field.doc != null)
              writeNewline();
            emitComment(field.doc);
            if (field.isStatic)
              write('static ');
            if (field.getter && !field.setter)
              write('readonly ');
            write(field.name);
            write(': ');
            emitType(field.type);
        }
    }
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();
  }

  public function includeType(type: Type) {}

  public function typeAccessor(type: TypeAccessor)
    return ctx.typeAccessor(type);

  function emitBaseType(type: BaseType, params: Array<Type>) {
    TypeEmitter.emitBaseType(this, type, params);
  }

  function emitType(type: Type) {
    TypeEmitter.emitType(this, type);
  }

  function emitParams(params: Array<Type>) {
    TypeEmitter.emitParams(this, params);
  }
}
