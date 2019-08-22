package genes.emitter.dts;

import haxe.io.Path;
import genes.emitter.es.ModuleEmitter;
import haxe.macro.Type;
import genes.Module;

using haxe.macro.Tools;

class DefinitionEmitter extends ModuleEmitter {
  public function emitDefinition(module: Module) {
    for (module => imports in module.dependencies)
      emitImports(module, imports);
    for (member in module.members)
      switch member {
        case MClass(cl, params, fields):
          emitClassDefinition(cl, params, fields);
        /*case MType(def, params):
          emitTypeDefinition(def, params); */
        default:
      }
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
        for (int in interfaces) {
          write(' implements ');
          emitBaseType(int.t.get(), int.params);
        }
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
              emitPos(field.pos);
              write('(');
              for (arg in join(args, write.bind(', '))) {
                emitIdent(arg.name);
                if (arg.opt)
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

  function emitBaseType(type: BaseType, params: Array<Type>) {
    // Todo: emit positions
    write(formatName(type, params));
  }

  function emitType(type: Type) {
    // Todo: emit positions
    write(renderType(type));
  }

  // Source: https://github.com/nadako/hxtsdgen/blob/0d903cad7e5ca054d450eb58cd4b253b9da5773c/src/hxtsdgen/TypeRenderer.hx#L10
  public static function renderType(t: Type, paren = false): String {
    inline function wrap(s)
      return if (paren) '($s)' else s;

    return switch (t) {
      case TInst(_.get() => cl, params):
        switch [cl, params] {
          case [{pack: [], name: "String"}, _]:
            "string";

          case [{pack: [], name: "Array"}, [elemT]]:
            renderType(elemT, true) + "[]";

          case [{name: name, kind: KTypeParameter(_)}, _]:
            name;

          default:
            formatName(cl, params);
        }

      case TAbstract(_.get() => ab, params):
        switch [ab, params] {
          case [{pack: [], name: "Int" | "Float"}, _]:
            "number";

          case [{pack: [], name: "Bool"}, _]:
            "boolean";

          case [{pack: [], name: "Void"}, _]:
            "void";

          case [{pack: [], name: "Null"}, [realT]]: // Haxe 4.x
            // TODO: generate `| null` union unless it comes from an optional field?
            renderType(realT, paren);

          case [{pack: ["haxe", "extern"], name: "EitherType"}, [aT, bT]]:
            '${renderType(aT, true)} | ${renderType(bT, true)}';

          default:
            // TODO: do we want to handle more `type Name = Underlying` cases?
            if (ab.meta.has(":coreType")) {
              'any';
            } else {
              renderType(ab.type.applyTypeParameters(ab.params, params), paren);
            }
        }

      case TAnonymous(_.get() => anon):
        var fields = [];
        for (field in anon.fields) {
          var opt = if (field.meta.has(":optional")) "?" else "";
          fields.push('${field.name}$opt: ${renderType(field.type)}');
        }
        '{${fields.join(", ")}}';

      case TType(_.get() => dt, params):
        switch [dt, params] {
          case [{pack: [], name: "Null"}, [realT]]: // Haxe 3.x
            // TODO: generate `| null` union unless it comes from an optional field?
            renderType(realT, paren);

          default:
            switch (dt.type) {
              case TAnonymous(_) if (dt.meta.has(":expose")):
                formatName(dt, params);
              default:
                renderType(dt.type.applyTypeParameters(dt.params, params), paren);
            }
        }

      case TFun(args, ret):
        wrap('(${renderArgs(args)}) => ${renderType(ret)}');

      case TDynamic(null):
        'any';

      case TDynamic(elemT):
        '{ [key: string]: ${renderType(elemT)} }';

      case TEnum(_.get() => et, params):
        formatName(et, params);

      default:
        'any';
    }
  }

  static function renderArgs(args: Array<{
    name: String,
    opt: Bool,
    t: Type
  }>): String {
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

    var tsArgs = [];
    for (i in 0...args.length) {
      var arg = args[i];
      var name = if (arg.name != "") arg.name else 'arg$i';
      var opt = if (arg.opt && i > noOptionalUntil) "?" else "";
      tsArgs.push('$name$opt: ${renderType(arg.t)}');
    }
    return tsArgs.join(", ");
  }

  static function formatName(t: {
    pack: Array<String>,
    name: String,
    meta: MetaAccess
  }, params: Array<Type>) {
    final applied = if (params.length > 0)
      '<${params.map(renderType.bind(_, true)).join(', ')}>'
    else
      '';
    return t.name + applied;
  }
}
