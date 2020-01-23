package genes.es;

import genes.Emitter;
import genes.Dependencies;
import genes.Module;
import haxe.macro.Type;
import genes.util.IteratorUtil.*;
import genes.util.TypeUtil.*;
import haxe.macro.Context;
import genes.util.Timer.timer;

using genes.util.TypeUtil;
using Lambda;

class ModuleEmitter extends ExprEmitter {
  public function emitModule(module: Module) {
    final dependencies = module.codeDependencies;
    final endTimer = timer('emitModule');
    ctx.typeAccessor = dependencies.typeAccessor;
    final typed = module.members.filter(m -> m.match(MType(_, _) | MClass({isInterface: true}, _, _)));
    if (typed.length == module.members.length)
      return endTimer();
    for (path => imports in dependencies.imports)
      emitImports(if (imports[0].external) path else module.toPath(path), imports);
    for (member in module.members)
      switch member {
        case MClass(cl, _, fields) if (!cl.isInterface):
          emitClass(module.isCyclic, cl, fields);
          emitStatics(module.isCyclic, cl, fields);
          emitInit(cl);
        case MEnum(et, _):
          emitEnum(et);
        case MMain(e):
          emitExpr(e);
        default:
      }
    return endTimer();
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
        emitPos(def.pos);
        write(if (def.alias != null) def.alias else def.name);
      case defs:
        write('{');
        for (def in join(defs, write.bind(', '))) {
          emitPos(def.pos);
          write(def.name + if (def.alias != null) ' as ${def.alias}' else '');
        }
        write('}');
    }
    writeSpace();
    write('from');
    writeSpace();
    emitString(where);
    writeNewline();
  }

  function emitStatics(checkCycles: (module: String) -> Bool, cl: ClassType,
      fields: Array<Field>) {
    writeNewline();
    for (field in fields)
      switch field {
        case {kind: Property, isStatic: true, expr: expr}
          if (expr != null):
          final types = TypeUtil.typesInExpr(expr);
          final isCyclic = types.fold((type, res) -> {
            return res || checkCycles(TypeUtil.moduleTypeName(type));
          }, false);
          if (isCyclic)
            emitDeferredStatic(cl, field);
          else
            emitStatic(cl, field);
        default:
      }
  }

  function emitStatic(cl: ClassType, field: Field) {
    writeNewline();
    emitPos(field.pos);
    emitIdent(cl.name);
    emitField(field.name);
    write(' = ');
    emitValue(field.expr);
  }

  function emitDeferredStatic(cl: ClassType, field: Field) {
    writeNewline();
    emitPos(field.pos);
    write(ctx.typeAccessor(registerType));
    write('.createStatic(');
    emitIdent(cl.name);
    write(', ');
    emitString(field.name);
    write(', function () { return ');
    emitValue(field.expr);
    write(' })');
  }

  function emitInit(cl: ClassType) {
    if (cl.init != null) {
      writeNewline();
      emitPos(cl.pos);
      emitExpr(cl.init);
      writeNewline();
    }
  }

  static function hasExternSuper(s: ClassType)
    return switch s.superClass {
      case null: s.isExtern;
      case {t: _.get() => v}: hasExternSuper(v);
    }

  static function hasConstructor(fields: Array<Field>) {
    for (field in fields)
      if (field.kind.equals(Constructor))
        return true;
    return false;
  }

  function emitClass(checkCycles: (module: String) -> Bool, cl: ClassType,
      fields: Array<Field>, export = true) {
    emitPos(cl.pos);
    writeNewline();
    emitComment(cl.doc);
    if (export)
      write('export ');
    write('class ');
    write(cl.name);
    if (cl.superClass != null || hasConstructor(fields)) {
      write(' extends ');
      write(ctx.typeAccessor(registerType));
      write('.inherits(');
      switch cl.superClass {
        case null:
        case {t: TClassDecl(_) => t}:
          final isCyclic = checkCycles(TypeUtil.moduleTypeName(t));
          if (isCyclic)
            write('() => ');
          write(ctx.typeAccessor(t));
          if (isCyclic)
            write(', true');
      }
      write(')');
    }
    extendsExtern = switch cl.superClass {
      case null: None;
      case {t: t = _.get() => {isExtern: true}}:
        Some(cl.superClass.t.get());
      default: None;
    }
    write(' {');
    increaseIndent();
    for (field in fields)
      switch field.kind {
        case Constructor | Method:
          switch field.expr.expr {
            case TFunction(f) if (export || !field.isStatic):
              writeNewline();
              emitPos(field.pos);
              if (field.doc != null)
                writeNewline();
              emitComment(field.doc);
              if (field.isStatic)
                write('static ');
              write(field.name);
              write('(');
              for (arg in join(f.args, write.bind(', '))) {
                emitLocalIdent(arg.v.name);
                if (arg.value != null) {
                  write(' = ');
                  emitValue(arg.value);
                }
              }
              write(') ');
              emitExpr(f.expr);
            default:
          }
        default:
      }

    writeNewline();
    write('static get __name__() {');
    increaseIndent();
    writeNewline();
    write('return ');
    emitString(cl.pack.concat([cl.name]).join('.'));
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();

    write('get __class__() {');
    increaseIndent();
    writeNewline();
    write('return ');
    emitIdent(cl.name);
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();

    decreaseIndent();
    writeNewline();
    write('}');
    if (export)
      writeNewline();
  }

  function emitEnum(et: EnumType) {
    final id = et.pack.concat([et.name]).join('.');
    emitPos(et.pos);
    writeNewline();
    emitComment(et.doc);
    write('export const ');
    write(et.name);
    write(' = ');
    writeNewline();
    writeGlobalVar("$hxEnums");
    write('[');
    emitString(id);
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
    for (c in join(et.names, write.bind(', ')))
      emitString(c);
    write('],');
    writeNewline();
    for (name in join(et.names, () -> {
      write(',');
      writeNewline();
    })) {
      final c = et.constructs.get(name);
      emitPos(c.pos);
      emitComment(c.doc);
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
    write(et.name);
    write('.__empty_constructs__ = [');
    final empty = [
      for (name in et.names)
        if (!et.constructs[name].type.match(TFun(_, _)))
          et.constructs[name]
    ];
    for (c in join(empty, write.bind(', '))) {
      write(et.name);
      write('[');
      emitString(c.name);
      write(']');
    }
    write(']');
    writeNewline();
  }
}
