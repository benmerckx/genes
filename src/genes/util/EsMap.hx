package genes.util;

import js.lib.Map;

class EsMap<K, V> {
  var inst: Map<K, V>;

  public inline function new()
    inst = new Map();

  public inline function set(key: K, value: V): Void
    inst.set(key, value);

  public inline function get(key: K): Null<V>
    return inst.get(key);

  public inline function remove(key: K): Bool
    return inst.delete(key);

  public inline function exists(key: K): Bool
    return inst.has(key);

  public inline function keys(): Iterator<K>
    return adaptIterator(inst.keys());

  public inline function iterator(): Iterator<V>
    return adaptIterator(inst.values());

  public inline function toString(): String {
    return "{" + [for (key in keys()) '$key => ${get(key)}'].join(', ') + "}";
  }

  static function adaptIterator<T>(from: js.lib.Iterator<T>): Iterator<T> {
    var value: T;
    var done: Bool;
    function queue() {
      var data = from.next();
      value = data.value;
      done = data.done;
    }
    return {
      hasNext: () -> {
        if (done == null)
          queue();
        return !done;
      },
      next: () -> {
        if (done == null)
          queue();
        var pending = value;
        queue();
        return pending;
      }
    }
  }

  public function clear() {
    inst.clear();
  }
}
