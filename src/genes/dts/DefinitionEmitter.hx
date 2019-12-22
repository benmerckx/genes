package genes.dts;

import haxe.io.Path;
import genes.es.ModuleEmitter;
import haxe.macro.Type;
import genes.TypeAccessor;
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
      emitImports(if (imports[0].external) path else module.toPath(path), imports);
    for (member in module.members)
      switch member {
        case MClass(cl, params, fields, _):
          emitClassDefinition(cl, params, fields);
        case MEnum(et, params):
          emitEnumDefinition(et, params);
        case MType(def, params):
          emitTypeDefinition(def, params);
        default:
      }
    endTimer();
  }

  function emitTypeDefinition(def: DefType, params: Array<Type>) {
    writeNewline();
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
    final anyParamWriter: TypeWriter = {
      write: this.write,
      emitPos: this.emitPos,
      includeType: this.includeType,
      typeAccessor: (type: TypeAccessor) -> switch type {
        case Generic(name): 'any';
        default: this.typeAccessor(type);
      }
    }
    writeNewline();
    write('export declare namespace ');
    emitPos(et.pos);
    write(et.name);
    write(' {');
    increaseIndent();
    function unique(values: Array<String>) {
      return [for (v in [for (v in values) v => true].keys()) v];
    }
    for (name => c in et.constructs) {
      final params = unique(paramNames.concat(c.params.map(p -> p.name)));
      writeNewline();
      write('export type ');
      emitPos(c.pos);
      write(name);
      if (params.length > 0) {
        write('<');
        for (param in join(params, write.bind(', ')))
          write('${param} = any');
        write('>');
      }
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
          if (params.length > 0) {
            write('<');
            for (param in join(params, write.bind(', ')))
              write('${param} = any');
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
                  TypeEmitter.emitType(anyParamWriter, param);
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

  function emitClassDefinition(cl: ClassType, params: Array<Type>,
      fields: Array<Field>) {
    writeNewline();
    emitPos(cl.pos);
    emitComment(cl.doc);
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
      switch field.kind {
        case Constructor | Method:
          switch field.type {
            case TFun(args, ret):
              writeNewline();
              if (field.doc != null) writeNewline();
              emitComment(field.doc);
              if (field.isStatic)
                write('static ');
              emitPos(field.pos);
              write(if (field.kind.equals(Constructor)) 'constructor' else field.name);
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
