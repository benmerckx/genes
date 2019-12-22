package genes;

import haxe.macro.Type;
import genes.Module;
import genes.TypeAccessor;
import genes.SourceMapGenerator;

enum DependencyType {
  DName;
  DDefault;
}

typedef Dependency = {
  type: DependencyType,
  name: String,
  external: Bool,
  ?alias: String,
  ?pos: SourcePosition
}

private typedef ModuleName = String;

class Dependencies {
  public final imports: Map<ModuleName, Array<Dependency>> = [];

  final module: Module;
  final runtime: Bool;
  final names: Array<{name: String, module: String}>;
  final aliases = new Map<String, String>();
  final aliasCount = new Map<String, Int>();

  public function new(module: Module, runtime = true) {
    this.module = module;
    this.runtime = runtime;
    this.names = [
      for (member in module.members)
        if (member.match(MType(_, _) | MClass(_, _, _) | MEnum(_, _)))
          switch member {
            case MClass({
              name: name,
              module: module
            }, _, _) | MEnum({
                name: name,
                module: module
              }, _) | MType({name: name, module: module}, _):
              {name: name, module: module}
            default:
              throw 'assert';
          }
    ];
  }

  public function push(module: String, dependency: Dependency) {
    final key = module + '.' + dependency.name;
    switch aliases[key] {
      case null:
        for (named in names)
          if (named.module != module && named.name == dependency.name) {
            aliases[key] = named.name + '__' +
              (aliasCount[named.name] = switch aliasCount[named.name] {
              case null: 1;
              case v: v + 1;
            });
            dependency.alias = aliases[key];
            break;
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
      names.push({name: dependency.name, module: module});
    } else {
      imports.set(module, [dependency]);
      names.push({name: dependency.name, module: module});
    }
  }

  public function add(type: ModuleType) {
    switch type {
      case TClassDecl(_.get() => {isInterface: true}) if (runtime):
      case TClassDecl((_.get() : BaseType) => base) | TEnumDecl((_.get() : BaseType) => base) | TTypeDecl((_.get() : BaseType) => base):
        // check meta
        var path = base.module;
        var dependency: Dependency = {
          type: DName,
          name: base.name,
          external: false,
          pos: base.pos
        }
        if (base.isExtern) {
          final name = switch base.meta.extract(':native') {
            case [{params: [{expr: EConst(CString(name))}]}]:
              name;
            default: base.name;
          }
          switch base.meta.extract(':jsRequire') {
            case [{params: [{expr: EConst(CString(m))}]}]:
              path = m;
              dependency = {type: DDefault, name: name, external: true}
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

  public function typeAccessor(type: TypeAccessor)
    return switch type {
      case Generic(name) | Abstract(name): name;
      case Concrete(module, name):
        final deps = imports.get(module);
        if (deps != null)
          for (i in deps)
            if (i.name == name)
              return if (i.alias != null) i.alias else i.name;
        return name;
    }
}
