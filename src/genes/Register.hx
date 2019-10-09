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

  @:keep public static function createClass(create, assign) {
    Syntax.code('
      var res = Object.defineProperties(
        function() {
          if (this.constructor === res.class)
            return new (Function.prototype.bind.apply(
              res.class,
              [null].concat(arguments)
            ))()
          Object.setPrototypeOf(this.constructor.prototype, res.class.prototype)
          this.new.apply(this, arguments)
        },
        {
          class: {
            get() {
              var created = create()
              return assign(Object.assign(created, res, {class: created}))
            }
          }
        }
      )
      return res
    ');
  }
}
