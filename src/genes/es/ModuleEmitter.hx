package genes.es;

import genes.Emitter;
import genes.Dependencies;
import genes.Module;
import haxe.macro.Type;
import genes.util.IteratorUtil.*;
import genes.util.TypeUtil.*;
import genes.util.Timer.timer;

using genes.util.TypeUtil;
using Lambda;

class ModuleEmitter extends ExprEmitter {
  public function emitModule(module: Module, ?extension: String) {
    final dependencies = module.codeDependencies;
    final endTimer = timer('emitModule');
    ctx.typeAccessor = dependencies.typeAccessor;
    final typed = module.members.filter(m -> m.match(MType(_, _)));
    if (typed.length == module.members.length && module.expose.length == 0)
      return endTimer();
    if (haxe.macro.Context.defined('genes.banner')) {
      write(haxe.macro.Context.definedValue('genes.banner'));
      writeNewline();
    }
    var endImportTimer = timer('emitImports');
    for (path => imports in dependencies.imports)
      emitImports(if (imports[0].external) path else module.toPath(path),
        imports, extension);
    endImportTimer();
    if (module.module != 'genes.Register' && ctx.hasFeature('js.Lib.global')) {
      writeNewline();
      write("const $global = ");
      write(ctx.typeAccessor(registerType));
      write(".$global");
      writeNewline();
    }
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
    for (export in module.expose)
      if (!export.isType)
        emitExport(export, module.toPath(export.module), extension);
    return endTimer();
  }

  function emitExport(export: ModuleExport, from: String, ?extension: String) {
    writeNewline();
    write('export {');
    write(export.name);
    write('} from ');
    #if genes.no_extension
    emitString(from);
    #else
    emitString(if (extension != null) '$from$extension' else from);
    #end
  }

  function emitImports(module: String, imports: Array<Dependency>,
      ?extension: String) {
    final named = [];
    for (def in imports)
      switch def.type {
        case DAsterisk | DDefault:
          emitImport([def], module, extension);
        default:
          named.push(def);
      }
    if (named.length > 0)
      emitImport(named, module, extension);
  }

  function emitImport(what: Array<Dependency>, where: String,
      ?extension: String) {
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
    #if genes.no_extension
    emitString(where);
    #else
    var isExternal = false;
    for (dependency in what)
      if (dependency.external) {
        isExternal = true;
        break;
      }
    emitString(if (!isExternal && extension != null) '$where$extension' else
      where);
    #end
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
            return res || checkCycles(TypeUtil.moduleTypeModule(type));
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
          emitIdent(TypeUtil.className(cl));
          emitField(field.name);
          writeNewline();
        default:
      }
    #end
  }

  function staticName(cl: ClassType, field: Field)
    return switch [cl.isExtern, field.name] {
      case [false, name = 'name' | 'length']: '$' + name;
      default: field.name;
    }

  function emitStatic(cl: ClassType, field: Field) {
    writeNewline();
    emitPos(field.pos);
    emitIdent(TypeUtil.className(cl));
    emitField(staticName(cl, field));
    write(' = ');
    emitValue(field.expr);
  }

  function emitDeferredStatic(cl: ClassType, field: Field) {
    writeNewline();
    emitPos(field.pos);
    write(ctx.typeAccessor(registerType));
    write('.createStatic(');
    emitIdent(TypeUtil.className(cl));
    write(', ');
    emitString(staticName(cl, field));
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
    write(TypeUtil.className(cl));
    write(' = function() {};');
    writeNewline();
    write(TypeUtil.className(cl));
    write('.__isInterface__ = true;');
    writeNewline();
  }

  function emitClass(checkCycles: (module: String) -> Bool, cl: ClassType,
      fields: Array<Field>, export = true) {
    writeNewline();
    emitComment(cl.doc);
    emitPos(cl.pos);
    if (export)
      write('export ');

    final id = cl.pack.concat([TypeUtil.className(cl)]).join('.');
    if (id != 'genes.Register') {
      write('const ');
      write(TypeUtil.className(cl));
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
    write(TypeUtil.className(cl));
    if (cl.superClass != null || hasConstructor(fields)) {
      write(' extends ');
      write(ctx.typeAccessor(registerType));
      write('.inherits(');
      switch cl.superClass {
        case null:
        case {t: TClassDecl(_) => t}:
          final isCyclic = checkCycles(TypeUtil.moduleTypeModule(t));
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
        case Constructor | Method
          #if (haxe_ver >= 4.2) if (!field.isAbstract) #end:
          switch field.expr {
            case null:
            case {expr: TFunction(f)} if (export || !field.isStatic):
              writeNewline();
              if (field.doc != null)
                writeNewline();
              emitComment(field.doc);
              emitPos(field.pos);
              if (field.isStatic) {
                write('static ');
                write(staticName(cl, field));
              } else if (field.kind.equals(Constructor)) {
                write('[');
                write(ctx.typeAccessor(registerType));
                write('.new]');
              } else {
                write(field.name);
              }
              write('(');
              emitFunctionArguments(f);
              write(') ');
              emitExpr(getFunctionBody(f));
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
    emitIdent(TypeUtil.className(cl));
    decreaseIndent();
    writeNewline();
    write('}');

    decreaseIndent();
    writeNewline();
    write('}');

    for (field in fields)
      switch field.kind {
        case Property:
          if (!field.getter && !field.setter && !field.isStatic) {
            writeNewline();
            emitIdent(TypeUtil.className(cl));
            write('.prototype.');
            emitPos(field.pos);
            write(field.name);
            write(' = null;');
          }
        default:
      }

    if (export)
      writeNewline();
  }

  function emitEnum(et: EnumType) {
    final discriminator = haxe.macro.Context.definedValue('genes.enum_discriminator');
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
      switch c.type {
        case TFun(args, ret):
          write('Object.assign((');
          for (param in join(args, write.bind(', ')))
            emitLocalIdent(param.name);
          write(') => ({_hx_index: ${c.index}, __enum__: "${id}", ');
          for (param in join(args, write.bind(', '))) {
            emitString(param.name);
            write(': ');
            emitLocalIdent(param.name);
          }
          if (discriminator != null) {
            write(', ');
            emitString(discriminator);
            write(': ');
            emitString(name);
          }
          write('}), {_hx_name: "${name}", __params__: [');
          for (param in join(args, write.bind(', ')))
            emitString(param.name);
          write(']})');
        default:
          write('{_hx_name: "${name}", _hx_index: ${c.index}, __enum__: "${id}"');
          if (discriminator != null) {
            write(', ');
            emitString(discriminator);
            write(': ');
            emitString(name);
          }
          write('}');
      }
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
