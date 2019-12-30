package genes;

import js.lib.Object;
import js.Syntax;

class Register {
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
      function res() {
        if (res.__init__) res.__init__()
        this.new.apply(this, arguments)
      }
      res.__init__ = () => {
        var proto = create()
        Object.setPrototypeOf(res.prototype, proto.prototype)
        const superClass = Object.getPrototypeOf(proto)
        if (superClass.__init__) superClass.__init__()
        res.__init__ = undefined
      }
      return res
    ');
  }
}
