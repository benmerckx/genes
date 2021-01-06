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
    final typed = module.members.filter(m -> m.match(MType(_, _)));
    if (typed.length == module.members.length)
      return endTimer();
    var endImportTimer = timer('emitImports');
    for (path => imports in dependencies.imports)
      emitImports(if (imports[0].external) path else module.toPath(path),
        imports);
    endImportTimer();
    for (member in module.members)
      switch member {
        case MClass(cl, _, fields) if (cl.isInterface):
          emitInterface(cl);
        case MClass(cl, _, fields):
          final endClassTimer = timer('emitClass');
          emitClass(module.isCyclic, cl, fields);
          endClassTimer();
          var endStaticsTimer = timer('emitStatics');
          emitStatics(module.isCyclic, cl, fields);
          endStaticsTimer();
          emitInit(cl);
        case MEnum(et, _):
          var endEnumTimer = timer('emitEnums');
          emitEnum(et);
          endEnumTimer();
        case MMain(e):
          writeNewline();
          emitExpr(e);
        default:
      }
    return endTimer();
  }

  function emitImports(module: String, imports: Array<Dependency>) {
    final named = [];
    for (def in imports)
      switch def.type {
        case DAsterisk | DDefault:
          emitImport([def], module);
        default:
          named.push(def);
      }
    if (named.length > 0)
      emitImport(named, module);
  }

  function emitImport(what: Array<Dependency>, where: String) {
    write('import');
    writeSpace();
    switch what {
      case [def = {type: DependencyType.DAsterisk}]:
        emitPos(def.pos);
        write('* as ' + if (def.alias != null) def.alias else def.name);
      case [def = {type: DependencyType.DDefault}]:
        emitPos(def.pos);
        write(if (def.alias != null) def.alias else def.name);
      case defs:
        write('{');
        for (def in join(defs, write.bind(', '))) {
          emitPos(def.pos);
          write(def.name
            + if (def.alias != null && def.alias != def.name)
              ' as ${def.alias}' else '');
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
        case {kind: Property, isStatic: true, expr: expr} if (expr != null):
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

    #if (haxe_ver >= 4.2)
    if (!cl.kind.match(KModuleFields(_)))
      return;
    writeNewline();
    for (field in fields)
      switch field {
        case {isStatic: true, isPublic: true}:
          write('export const ');
          emitIdent(field.name);
          write(' = ');
          emitIdent(cl.name);
          emitField(field.name);
          writeNewline();
        default:
      }
    #end
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
      write(';');
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

  function emitInterface(cl: ClassType) {
    writeNewline();
    write('export const ');
    write(cl.name);
    write(' = {}');
    writeNewline();
  }

  function emitClass(checkCycles: (module: String) -> Bool, cl: ClassType,
      fields: Array<Field>, export = true) {
    writeNewline();
    emitComment(cl.doc);
    emitPos(cl.pos);
    if (export)
      write('export ');

    final id = cl.pack.concat([cl.name]).join('.');
    if (id != 'genes.Register') {
      write('const ');
      write(cl.name);
      write(' = ');
      writeGlobalVar("$hxClasses");
      write('[');
      emitString(id);
      write(']');
      write(' = ');
      writeNewline();
    }

    emitPos(cl.pos);
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
              if (field.doc != null)
                writeNewline();
              emitComment(field.doc);
              emitPos(field.pos);
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
        case Property:
          if (field.getter) {
            writeNewline();
            emitPos(field.pos);
            if (field.isStatic)
              write('static ');
            write('get ');
            write(field.name);
            write('() {');
            increaseIndent();
            writeNewline();
            write('return this.get_');
            write(field.name);
            write('()');
            decreaseIndent();
            writeNewline();
            write('}');
          }
          if (field.setter) {
            writeNewline();
            emitPos(field.pos);
            if (field.isStatic)
              write('static ');
            write('set ');
            write(field.name);
            write('(v) {');
            increaseIndent();
            writeNewline();
            write('this.set_');
            write(field.name);
            write('(v)');
            decreaseIndent();
            writeNewline();
            write('}');
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

    switch cl.interfaces {
      case []:
      case v:
        writeNewline();
        write('static get __interfaces__() {');
        increaseIndent();
        writeNewline();
        write('return [');
        for (i in join(v, write.bind(', ')))
          write(ctx.typeAccessor(i.t.get()));
        write(']');
        decreaseIndent();
        writeNewline();
        write('}');
    }

    switch cl.superClass {
      case null:
      case {t: TClassDecl(_) => t}:
        writeNewline();
        write('static get __super__() {');
        increaseIndent();
        writeNewline();
        write('return ');
        write(ctx.typeAccessor(t));
        decreaseIndent();
        writeNewline();
        write('}');
    }

    writeNewline();
    write('get __class__() {');
    increaseIndent();
    writeNewline();
    write('return ');
    emitIdent(cl.name);
    decreaseIndent();
    writeNewline();
    write('}');

    decreaseIndent();
    writeNewline();
    write('}');

    if (export)
      writeNewline();
  }

  function emitEnum(et: EnumType) {
    final id = et.pack.concat([et.name]).join('.');
    writeNewline();
    emitComment(et.doc);
    emitPos(et.pos);
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
    writeNewline();
    for (name in join(et.names, () -> {
      write(',');
      writeNewline();
    })) {
      final c = et.constructs.get(name);
      emitComment(c.doc);
      emitPos(c.pos);
      write(name);
      write(': ');
      write(switch c.type {
        case TFun(args, ret):
          final params = args.map(param -> param.name).join(', ');
          final paramsQuoted = args.map(param -> '"${param.name}"').join(', ');
          'Object.assign(($params) => ({_hx_index: ${c.index}, __enum__: "${id}", $params}), {_hx_name: "${name}", __params__: [$paramsQuoted]})';
        default:
          '{_hx_name: "${name}", _hx_index: ${c.index}, __enum__: "${id}"}';
      });
    }
    decreaseIndent();
    writeNewline();
    write('}');
    writeNewline();

    write(et.name);
    write('.__constructs__ = [');
    for (c in join(et.names, write.bind(', '))) {
      #if (haxe_ver >= 4.2)
      write(et.name);
      emitField(c);
      #else
      emitString(c);
      #end
    }
    write(']');
    writeNewline();

    write(et.name);
    write('.__empty_constructs__ = [');
    final empty = [
      for (name in et.names)
        if (!et.constructs[name].type.match(TFun(_, _))) et.constructs[name]
    ];
    for (c in join(empty, write.bind(', '))) {
      write(et.name);
      emitField(c.name);
    }
    write(']');
    writeNewline();
  }
}
