package genes;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.JSGenApi;
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import genes.generator.es.ModuleGenerator;

using Lambda;
using StringTools;

class Generator {
  static function generate(api: JSGenApi) {
    final modules = new Map<String, Array<Type>>();
    final output = Path.withoutExtension(Path.withoutDirectory(api.outputFile));
    for (type in api.types) {
      switch type {
        // Todo: init extern inst
        case TInst(_.get() => {module: module,
          isExtern: false}, _) | TEnum(_.get() => {module: module,
            isExtern: false}, _):
          if (modules.exists(module))
            modules.get(module).push(type);
          else
            modules.set(module, [type]);
        default:
      }
    }
    for (module => types in modules) {
      final path = module.replace('.', '/');
      final file = try Context.resolvePath(path + '.hx') catch (e:Dynamic) null;
      generateModule(api, path, file, types);
    }
    switch api.main {
      case null:
      // Todo: check for nameclash with above
      // Todo: get Main module out of cli args to find source file
      case v:
        generateModule(api, output, null, [], v);
    }
  }

  static function generateModule(api: JSGenApi, path: String, file: String,
      types: Array<Type>, ?main: TypedExpr) {
    final module = new Module(path, file, types, main);
    final outputDir = Path.directory(api.outputFile);
    function save(file: String, content: String) {
      final path = Path.join([outputDir, file]);
      final dir = Path.directory(path);
      if (!FileSystem.exists(dir))
        FileSystem.createDirectory(dir);
      File.saveContent(path, content);
    }
    ModuleGenerator.module(api, save, module);
  }

  #if macro
  public static function use() {
    Compiler.setCustomJSGenerator(Generator.generate);
  }
  #end
}
/*
  function genClass(c: ClassType) {
    genPackage(c.pack);
    api.setCurrentClass(c);
    var p = getPath(c);
    print('$p = $$hxClasses[\'$p\'] = ');
    if (c.constructor != null)
      genExpr(c.constructor.get().expr());
    else
      print("function() { }");
    newline();
    var name = p.split(".").map(api.quoteString).join(",");
    print('$p.__name__ = [$name]');
    newline();
    if (c.superClass != null) {
      var psup = getPath(c.superClass.t.get());
      print('$p.__super__ = $psup');
      newline();
      print('for(var k in $psup.prototype ) $p.prototype[k] = $psup.prototype[k]');
      newline();
    }
    for (f in c.statics.get())
      genStaticField(c, p, f);
    for (f in c.fields.get()) {
      switch (f.kind) {
        case FVar(r, _):
          if (r == AccResolve)
            continue;
        default:
      }
      genClassField(c, p, f);
    }
    print('$p.prototype.__class__ = $p');
    newline();
    if (c.interfaces.length > 0) {
      var me = this;
      var inter = c.interfaces.map(function(i) return me.getPath(i.t.get()))
        .join(",");
      print('$p.__interfaces__ = [$inter]');
      newline();
    }
  }

  function genEnum(e: EnumType) {
    genPackage(e.pack);
    var p = getPath(e);
    var names = p.split(".").map(api.quoteString).join(",");
    var constructs = e.names.map(api.quoteString).join(",");
    print('$p = $$hxClasses[\'$p\'] = { __ename__ : [$names], __constructs__ : [$constructs] }');
    newline();
    for (c in e.constructs.keys()) {
      var c = e.constructs.get(c);
      var f = field(c.name);
      print('$p$f = ');
      switch (c.type) {
        case TFun(args, _):
          var sargs = args.map(function(a) return a.name).join(",");
          print('function($sargs) { var $$x = ["${c.name}",${c.index},$sargs]; $$x.__enum__ = $p; $$x.toString = $$estr; return $$x; }');
        default:
          print("[" + api.quoteString(c.name) + "," + c.index + "]");
          newline();
          print('$p$f.toString = $$estr');
          newline();
          print('$p$f.__enum__ = $p');
      }
      newline();
    }
    var meta = api.buildMetaData(e);
    if (meta != null) {
      print('$p.__meta__ = ');
      genExpr(meta);
      newline();
    }
}*/
