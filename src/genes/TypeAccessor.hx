package genes;

import haxe.macro.Type;

enum TypeAccessorImpl {
  Concrete(module: String, path: String);
  Generic(name: String);
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
        name: name
      }) | TEnumDecl(_.get() => {
          module: module,
          name: name
        }) | TTypeDecl(_.get() => {module: module, name: name}):
        Concrete(module, name);
    }
  }

  @:from public static function fromBaseType(type: BaseType): TypeAccessor {
    return switch (cast type : ClassType) {
      case {kind: null}:
        Concrete(type.module, type.name);
      case {kind: KTypeParameter([])}:
        Generic(type.name);
      default:
        Concrete(type.module, type.name);
    }
  }
}
