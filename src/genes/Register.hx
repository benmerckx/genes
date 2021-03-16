package genes;

import js.lib.Object;
import js.Syntax;

class Register {
  @:keep @:native("$global")
  public static final _global = js.Syntax.code('globalThis');

  static final globals = {}

  @:keep public static function global(name) {
    return untyped globals[name] ? globals[name] : globals[name] = {};
  }

  @:keep public static function createStatic<T>(obj: {}, name: String,
      get: () -> T) {
    var value: T = null;
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
      }
    });
  }

  @:keep public static function iter<T>(a: Array<T>): Iterator<T> {
    return untyped if (!Array.isArray(a)) js.Syntax.code('a.iterator()') else
      untyped {
      cur: 0,
      arr: a,
      hasNext: function() {
        return __this__.cur < __this__.arr.length;
      },
      next: function() {
        return __this__.arr[__this__.cur++];
      }
    }
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

  static var fid = 0;

  @:keep public static function bind(o: Dynamic, m: Dynamic) {
    if (m == null)
      return null;
    if (m.__id__ == null)
      m.__id__ = fid++;
    var f = null;
    if (o.hx__closures__ == null)
      o.hx__closures__ = {}
    else
      f = o.hx__closures__[m.__id__];
    if (f == null) {
      f = m.bind(o);
      o.hx__closures__[m.__id__] = f;
    }
    return f;
  }
}
