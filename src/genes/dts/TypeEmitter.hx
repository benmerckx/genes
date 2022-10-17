package genes.dts;

import genes.SourceMapGenerator;
import haxe.macro.Type;
import genes.util.IteratorUtil.*;
import genes.util.TypeUtil;

using haxe.macro.Tools;

// From: https://github.com/nadako/hxtsdgen/blob/0d903cad7e5ca054d450eb58cd4b253b9da5773c/src/hxtsdgen/TypeRenderer.hx#L10

typedef TypeWriter = {
  function write(code: String): Void;
  function writeNewline(): Void;
  function emitComment(comment: String): Void;
  function increaseIndent(): Void;
  function decreaseIndent(): Void;
  function emitPos(pos: SourcePosition): Void;
  function includeType(type: Type): Void;
  function typeAccessor(type: TypeAccessor): String;
}

class TypeEmitter {
  public static function emitBaseType(writer: TypeWriter, type: BaseType,
      params: Array<Type>, withConstraints = false) {
    final write = writer.write, emitPos = writer.emitPos;
    emitPos(type.pos);
    write(writer.typeAccessor(type));
    emitParams(writer, params, withConstraints);
  }

  public static function emitParams(writer: TypeWriter, params: Array<Type>,
      withConstraints = false) {
    final write = writer.write;
    if (params.length > 0) {
      write('<');
      for (param in join(params, write.bind(', '))) {
        emitType(writer, param);
        if (withConstraints)
          switch param {
            case TInst(_.get() => {kind: KTypeParameter(constraints)}, _):
              if (constraints.length > 0) {
                write(' extends ');
                for (c in join(constraints, write.bind(' & ')))
                  emitType(writer, c);
              }
            default:
          }
      }
      write('>');
    }
  }

  public static function emitType(writer: TypeWriter, type: Type,
      wrap = true) {
    final write = writer.write, emitPos = writer.emitPos,
    includeType = writer.includeType;
    switch type {
      case TInst(_.get().meta => meta, _) if (meta.has(':genes.type')):
        switch meta.extract(':genes.type') {
          case [{params: [{expr: EConst(CString(type))}]}]: write(type);
          default: throw '@:genes.type needs an expression';
        }
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
            // TODO: do not generate `null |` union if it comes from an optional field?
            emitPos(ab.pos);
            write('null | ');
            emitType(writer, realT);
          case [{pack: ["haxe", "extern"] | ['haxe'], name: "Rest"}, [t]]:
            emitPos(ab.pos);
            emitType(writer, t);
            write('[]');
          case [{pack: ["haxe", "extern"], name: "EitherType"}, [aT, bT]]:
            emitPos(ab.pos);
            emitType(writer, aT);
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
        writer.increaseIndent();
        for (field in join(anon.fields, write.bind(', '))) {
          writer.writeNewline();
          emitPos(field.pos);
          if (field.doc != null)
            writer.emitComment(field.doc);
          write(field.name);
          if (field.meta.has(':optional'))
            write('?');
          write(': ');
          if (field.params.length > 0) {
            write('<');
            for (param in join(field.params, write.bind(', ')))
              emitType(writer, param.t);
            write('>');
          }
          emitType(writer, field.type, false);
        }
        writer.decreaseIndent();
        writer.writeNewline();
        write('}');
      case TType(_.get() => dt, params):
        switch [dt, params] {
          case [{pack: [], name: "Null"}, [realT]]: // Haxe 3.x
            // TODO: do not generate `null |` union if it comes from an optional field?
            write('null | ');
            emitType(writer, realT);
          default:
            switch dt.type {
              case TInst(_.get() => {isExtern: true}, _):
                emitType(writer,
                  dt.type.applyTypeParameters(dt.params, params));
              case TAbstract(t = _.get() => {
                pack: ["haxe", "extern"],
                name: "EitherType"
              }, x) if (x.length == params.length):
                emitType(writer, TAbstract(t, params));
              default:
                includeType(type);
                emitBaseType(writer, dt, params);
            }
        }
      case TFun(args, ret):
        if (wrap)
          write('(');
        write('(');
        emitArgs(writer, args);
        write(') => ');
        emitType(writer, ret);
        if (wrap)
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
      if (TypeUtil.isRest(arg.t))
        write('...');
      write(if (arg.name != "") arg.name else 'arg$i');
      if (arg.opt && i > noOptionalUntil)
        write("?");
      write(': ');
      emitType(writer, arg.t);
    }
  }
}
