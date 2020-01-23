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

  @:keep public static function extend(superClass) {
    Syntax.code('
      function res() {
        this.new.apply(this, arguments)
      }
      Object.setPrototypeOf(res.prototype, superClass.prototype)
      return res
    ');
  }

  @:keep public static function inherits(resolve, defer = false) {
    Syntax.code('
      function res() {
        if (defer && resolve && res.__init__) res.__init__()
        this.new.apply(this, arguments)
      }
      if (!defer) {
        if (resolve && resolve.__init__) {
          defer = true
          res.__init__ = () => {
            resolve.__init__()
            Object.setPrototypeOf(res.prototype, resolve.prototype)
            res.__init__ = undefined
          } 
        } else if (resolve) {
          Object.setPrototypeOf(res.prototype, resolve.prototype)
        }
      } else {
        res.__init__ = () => {
          const superClass = resolve()
          if (superClass.__init__) superClass.__init__()
          Object.setPrototypeOf(res.prototype, superClass.prototype)
          res.__init__ = undefined
        } 
      }
      return res
    ');
  }
}
