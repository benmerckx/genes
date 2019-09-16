package genes.util;

import js.Syntax;

class DeferClass {
  @:keep public static function deferStatic(obj, name, get) {
    Syntax.code('
      Object.defineProperty(obj, name, {
        configurable: true,
        enumerable: true, 
        get() {
          const value = get()
          Object.defineProperty(obj, name, {
            enumerable: true,
            writeable: true,
            value
          })
          return value
        },
        set(value) {
          Object.defineProperty(obj, name, {
            enumerable: true,
            writeable: true,
            value
          })
          return value
        }
      })
    ');
  }

  @:keep public static function deferClass(create, assign, statics) {
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
      // do statics
      return res
    ');
  }
}
