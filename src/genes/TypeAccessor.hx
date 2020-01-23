package genes;

import haxe.macro.Type;

enum TypeAccessorImpl {
  Concrete(module: String, path: String, native: Null<String>);
  Abstract(name: String);
}

abstract TypeAccessor(TypeAccessorImpl) from TypeAccessorImpl {
  @:from public static function fromModuleType(type: ModuleType): TypeAccessor {
    return switch type {
      case TAbstract(_.get() => cl = {meta: meta, name: name}):
        switch meta.has(':coreType') {
          // Todo: I believe haxe was to cancel use of Abstract types as value
          case true: Abstract('"$$hxCoreType__$name"');
          case false: throw 'assert';
        }
      case TClassDecl(_.get() => {
        module: module,
        name: name,
        meta: meta
      }) | TEnumDecl(_.get() => {
          module: module,
          name: name,
          meta: meta
        }) | TTypeDecl(_.get() => {module: module, name: name, meta: meta}):
        final native = switch meta.extract(':native') {
          case [{params: [{expr: EConst(CString(name))}]}]:
            name;
          default: null;
        }
        Concrete(module, name, native);
    }
  }

  @:from public static function fromBaseType(type: BaseType): TypeAccessor {
    final native = switch type.meta.extract(':native') {
      case [{params: [{expr: EConst(CString(name))}]}]:
        name;
      default: null;
    }
    return Concrete(type.module, type.name, native);
  }
}
