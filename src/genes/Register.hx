package genes;

import js.lib.Object;
import js.Syntax;

class Register {
  @:keep @:native("$global")
  public static final _global = js.Syntax.code('typeof window != "undefined" ? window : typeof global != "undefined" ? global : typeof self != "undefined" ? self : undefined');

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

  @:keep public static function iterator<T>(a: Array<T>): Void->Iterator<T> {
    return if (!untyped Array.isArray(a))
      js.Syntax.code('typeof a.iterator === "function" ? a.iterator.bind(a) : a.iterator') else
      mkIter.bind(a);
  }

  @:keep public static function getIterator<T>(a: Array<T>): Iterator<T> {
    return if (!untyped Array.isArray(a)) js.Syntax.code('a.iterator()') else
      mkIter(a);
  }

  @:keep static function mkIter<T>(a: Array<T>): Iterator<T> {
    return new ArrayIterator(a);
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

private class ArrayIterator<T> {
  final array: Array<T>;
  var current: Int = 0;

  public function new(array: Array<T>) {
    this.array = array;
  }

  public function hasNext() {
    return current < array.length;
  }

  public function next() {
    return array[current++];
  }
}
