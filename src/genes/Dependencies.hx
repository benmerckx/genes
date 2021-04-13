package genes;

import genes.util.TypeUtil;
import haxe.macro.Type;
import genes.Module;
import genes.TypeAccessor;
import genes.SourceMapGenerator;

enum DependencyType {
  DName;
  DDefault;
  DAsterisk;
}

typedef Dependency = {
  type: DependencyType,
  name: String,
  external: Bool,
  path: String,
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
        if (member.match(MType(_,
          _) | MClass(_, _, _) | MEnum(_, _))) switch member {
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
    inline function alias(key: String, name: String) {
      return aliases[key] = name
        + '__'
        + (aliasCount[name] = switch aliasCount[name] {
          case null: 1;
          case v: v + 1;
        });
    }
    switch aliases[key] {
      case null:
        switch dependency.name {
          case 'Object':
            dependency.alias = alias(key, dependency.name);
          default:
            for (named in names)
              if (named.module != module && named.name == dependency.name) {
                dependency.alias = alias(key, named.name);
                break;
              }
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

  public static function makeDependency(base: BaseType): Dependency {
    if (base.isExtern) {
      switch base.meta.extract(':jsRequire') {
        case [{params: [{expr: EConst(CString(path))}]}]:
          final cl: ClassType = cast base;
          final isWildcard = switch [cl.fields.get(), cl.statics.get()] {
            case [fields, statics]:
              cl.kind.equals(KNormal)
              && !cl.isInterface
              && cl.superClass == null
              && cl.constructor == null
              && fields.length == 0
              && statics.filter(st -> st.meta.has(':selfCall')).length == 0;
          }
          return {
            type: if (isWildcard) DAsterisk else DDefault,
            name: base.name,
            path: path,
            external: true,
            pos: base.pos
          }
        case [{params: [{expr: EConst(CString(path))}, {expr: EConst(CString('default'))}]}]:
          return {
            type: DDefault,
            name: base.name,
            path: path,
            external: true,
            pos: base.pos
          }
        case [{params: [{expr: EConst(CString(path))}, {expr: EConst(CString(name))}]}]:
          final native = switch base.meta.extract(':native') {
            case [{params: [{expr: EConst(CString(native))}]}]:
              native;
            default: null;
          }
          // If we have a native name with a dot path we need a default import
          if (native != null && native.indexOf('.') > -1) {
            return {
              type: DDefault,
              name: native.split('.')[0],
              path: path,
              external: true,
              pos: base.pos
            }
          }
          // benmerckx/genes#7
          if (name.indexOf('.') > -1) {
            return {
              type: DName,
              name: name.split('.')[0],
              path: path,
              external: true,
              pos: base.pos
            }
          }
          return {
            type: DName,
            name: name,
            path: path,
            external: true,
            pos: base.pos
          }
        default:
          return null;
      }
    }
    return {
      type: DName,
      name: base.name,
      external: false,
      path: base.module,
      pos: base.pos
    }
  }

  public function add(type: ModuleType) {
    switch type {
      case TClassDecl((_.get() : BaseType) => base) |
        TEnumDecl((_.get() : BaseType) => base) |
        TTypeDecl((_.get() : BaseType) => base):
        final dependency = makeDependency(base);
        if (dependency == null)
          return;
        if (dependency.path != module.module)
          push(dependency.path, dependency);
        switch type {
          case TTypeDecl(_.get() => t)
            if (module.getMember(dependency.name) == null):
            // import X in Y;
            final x = TypeUtil.typeToBaseType(t.type);
            if (x == null)
              return;
            final y = makeDependency(x);
            y.alias = dependency.name;
            push(y.path, y);
          default:
        }
      default:
    }
  }

  public function typeAccessor(type: TypeAccessor)
    return switch type {
      case Abstract(name): name;
      case Concrete(module, name, native):
        if (native != null && native.indexOf('.') > -1)
          return native;
        final deps = imports.get(module);
        if (deps != null)
          for (i in deps)
            if (i.name == name)
              return if (i.alias != null) i.alias else i.name;
        return name;
    }
}
