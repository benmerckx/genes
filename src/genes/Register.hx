package genes;

import js.lib.Object;
import js.Syntax;
import haxe.DynamicAccess;

class Register {
  static final globals: DynamicAccess<Any> = {}

  @:keep public static function global(name) {
    if (!globals.exists(name))
      globals[name] = {}
    return globals[name];
  }

  @:keep public static function createStatic<T>(obj: {}, name: String,
      get: () -> T) {
    var value: T;
    inline function init() {
      if (get != null) {
        value = get();
        get = null;
      }
    }
    Object.defineProperty(obj, name, {
      enumerable: true,
      get: () -> {
        init();
        return value;
      },
      set: v -> {
        init();
        value = v;
        return value;
      }
    });
  }

  @:keep public static function createClass(create) {
    Syntax.code('
      return function() {
        Object.setPrototypeOf(this.constructor.prototype, create().prototype)
        this.new.apply(this, arguments)
      }
    ');
  }

  @:keep public static function __cast(a, b) {
    return @:privateAccess js.Boot.__cast(a, b);
  }
}
