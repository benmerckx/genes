package genes;

import haxe.macro.Type;
import genes.Module;

enum DependencyType {
  DName;
  DDefault;
}

typedef Dependency = {
  type: DependencyType,
  name: String,
  ?alias: String
}

private typedef ModuleName = String;

class Dependencies {
  public final imports = new Map<ModuleName, Array<Dependency>>();

  final module: Module;
  final runtime: Bool;
  final aliases = new Map<String, String>();
  final aliasCount = new Map<String, Int>();

  public function new(module: Module, runtime = true) {
    this.module = module;
    this.runtime = runtime;
  }

  public function push(module: String, dependency: Dependency) {
    final key = module + '.' + dependency.name;
    switch aliases[key] {
      case null:
        for (member in this.module.members)
          switch member {
            case MClass({name: name}, _, _) | MEnum({name: name}, _):
              if (name == dependency.name) {
                aliases[key] = name + '__' +
                  (aliasCount[name] = switch aliasCount[name] {
                  case null: 1;
                  case v: v + 1;
                });
                dependency.alias = aliases[key];
                break;
              }
            default:
          }
      case v:
        dependency.alias = v;
    }
    if (imports.exists(module)) {
      final deps = imports.get(module);
      for (i in deps)
        if (i.name == dependency.name && i.alias == dependency.alias)
          return;
      deps.push(dependency);
    } else {
      imports.set(module, [dependency]);
    }
  }

  public function add(type: ModuleType) {
    switch type {
      case TClassDecl(_.get() => {isInterface: true}) if (runtime):
      case TClassDecl((_.get() : BaseType) => base) | TEnumDecl((_.get() : BaseType) => base):
        // check meta
        var path = module.toPath(base.module);
        var dependency: Dependency = {type: DName, name: base.name}
        if (base.isExtern) {
          final name = switch base.meta.extract(':native') {
            case [{params: [{expr: EConst(CString(name))}]}]:
              name;
            default: base.name;
          }
          switch base.meta.extract(':jsRequire') {
            case [{params: [{expr: EConst(CString(m))}]}]:
              path = m;
              dependency = {type: DDefault, name: name}
            default:
              return;
          }
        } else if (base.module == module.module) {
          return;
        }
        push(path, dependency);
      default:
    }
  }

  public function typeAccessor(type: ModuleType)
    switch type {
      case TAbstract(_.get() => cl = {meta: meta, name: name}):
        return switch meta.has(':coreType') {
          case true: '"$$hxCoreType__$name"';
          case false: throw 'assert';
        }
      case TClassDecl(_.get() => {
        module: m,
        name: name
      }) | TEnumDecl(_.get() => {module: m, name: name}):
        // check alias in this module
        final path = module.toPath(m);
        final deps = imports.get(path);
        if (deps != null)
          for (i in deps)
            if (i.name == name)
              return if (i.alias != null) i.alias else i.name;
        return name;
      case TTypeDecl(_.get() => {name: name}):
        return name; // Todo: does this even happen?
    }
}
