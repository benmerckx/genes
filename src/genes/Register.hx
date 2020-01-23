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

  @:keep public static function inherits(resolve) {
    Syntax.code('
      function res() {
        if (resolve && res.__init__) res.__init__()
        this.new.apply(this, arguments)
      }
      if (resolve)
        res.__init__ = () => {
          const superClass = resolve()
          if (superClass.__init__) superClass.__init__()
          Object.setPrototypeOf(res.prototype, superClass.prototype)
          res.__init__ = undefined
        }
      return res
    ');
  }
}
