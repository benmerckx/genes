package genes.dts;

import genes.SourceMapGenerator;
import haxe.macro.Type;
import genes.util.IteratorUtil.*;

using haxe.macro.Tools;

// From: https://github.com/nadako/hxtsdgen/blob/0d903cad7e5ca054d450eb58cd4b253b9da5773c/src/hxtsdgen/TypeRenderer.hx#L10

typedef TypeWriter = {
  function write(code: String): Void;
  function emitPos(pos: SourcePosition): Void;
  function includeType(type: Type): Void;
}

class TypeEmitter {
  public static function emitBaseType(writer: TypeWriter, type: BaseType,
      params: Array<Type>) {
    final write = writer.write, emitPos = writer.emitPos;
    emitPos(type.pos);
    write(type.name);
    emitParams(writer, params);
  }

  public static function emitParams(writer: TypeWriter, params: Array<Type>) {
    final write = writer.write;
    if (params.length > 0) {
      write('<');
      for (param in join(params, write.bind(', ')))
        emitType(writer, param);
      write('>');
    }
  }

  public static function emitType(writer: TypeWriter, type: Type) {
    final write = writer.write, emitPos = writer.emitPos,
    includeType = writer.includeType;
    switch type {
      case TInst(ref = _.get() => cl, params):
        switch [cl, params] {
          case [{pack: [], name: 'String'}, _]:
            emitPos(cl.pos);
            write('string');
          case [{pack: [], name: "Array"}, [elemT]]:
            emitPos(cl.pos);
            emitType(writer, elemT);
            write('[]');
          case [{name: name, kind: KTypeParameter(_)}, _]:
            emitPos(cl.pos);
            write(name);
          default:
            includeType(TInst(ref, params));
            emitBaseType(writer, cl, params);
        }
      case TAbstract(_.get() => ab, params):
        switch [ab, params] {
          case [{pack: [], name: "Int" | "Float"}, _]:
            emitPos(ab.pos);
            write('number');
          case [{pack: [], name: "Bool"}, _]:
            emitPos(ab.pos);
            write('boolean');
          case [{pack: [], name: "Void"}, _]:
            emitPos(ab.pos);
            write('void');
          case [{pack: [], name: "Null"}, [realT]]: // Haxe 4.x
            // TODO: generate `| null` union unless it comes from an optional field?
            emitPos(ab.pos);
            emitType(writer, realT);
          case [{pack: ["haxe", "extern"], name: "EitherType"}, [aT, bT]]:
            emitType(writer, aT);
            emitPos(ab.pos);
            write(' | ');
            emitType(writer, bT);
          default:
            // TODO: do we want to handle more `type Name = Underlying` cases?
            if (ab.meta.has(":coreType")) {
              emitPos(ab.pos);
              write('any');
            } else {
              emitType(writer, ab.type.applyTypeParameters(ab.params, params));
            }
        }
      case TAnonymous(_.get() => anon):
        write('{');
        for (field in join(anon.fields, write.bind(', '))) {
          emitPos(field.pos);
          write(field.name);
          if (field.meta.has(':optional'))
            write('?');
          write(': ');
          emitType(writer, field.type);
        }
        write('}');
      case TType(_.get() => dt, params):
        switch [dt, params] {
          case [{pack: [], name: "Null"}, [realT]]: // Haxe 3.x
            // TODO: generate `| null` union unless it comes from an optional field?
            emitType(writer, realT);
          default:
            emitType(writer, dt.type.applyTypeParameters(dt.params, params));
        }

      case TFun(args, ret):
        write('((');
        emitArgs(writer, args);
        write(') => ');
        emitType(writer, ret);
        write(')');
      case TDynamic(null):
        write('any');
      case TDynamic(elemT):
        write('{[key: string]: ');
        emitType(writer, elemT);
        write('}');
      case TEnum(ref = _.get() => et, params):
        includeType(TEnum(ref, params));
        emitBaseType(writer, et, params);
      default:
        write('any');
    }
  }

  static function emitArgs(writer: TypeWriter, args: Array<{
    name: String,
    opt: Bool,
    t: Type
  }>) {
    final write = writer.write;
    // here we handle haxe's crazy argument skipping:
    // we allow trailing optional args, but if there's non-optional
    // args after the optional ones, we consider them non-optional for TS
    var noOptionalUntil = 0;
    var hadOptional = true;
    for (i in 0...args.length) {
      var arg = args[i];
      if (arg.opt) {
        hadOptional = true;
      } else if (hadOptional && !arg.opt) {
        noOptionalUntil = i;
        hadOptional = false;
      }
    }

    for (i in joinIt(0...args.length, write.bind(', '))) {
      var arg = args[i];
      write(if (arg.name != "") arg.name else 'arg$i');
      if (arg.opt && i > noOptionalUntil)
        write("?");
      write(': ');
      emitType(writer, arg.t);
    }
  }
}
