package haxe.ds;

#if !js
extern class StringMap<T> implements haxe.Constraints.IMap<String, T> {
  public function new(): Void;
  public function set(key: String, value: T): Void;
  public function get(key: String): Null<T>;
  public function exists(key: String): Bool;
  public function remove(key: String): Bool;
  public function keys(): Iterator<String>;
  public function iterator(): Iterator<T>;
  @:runtime public inline function keyValueIterator(): KeyValueIterator<String,
    T>
    return new haxe.iterators.MapKeyValueIterator(this);
  public function copy(): StringMap<T>;
  public function toString(): String;
}
#else
@:native('Map')
extern class StringMap<T> implements haxe.Constraints.IMap<String, T> {
  public function new();
  var inst(get, never): js.lib.Map<String, T>;
  inline function get_inst(): js.lib.Map<String, T>
    return cast this;
  @:arrayAccess public function set(key: String, value: T): Void;
  @:arrayAccess public function get(key: String): Null<T>;
  public inline function remove(key: String): Bool
    return inst.delete(key);
  public inline function exists(key: String): Bool
    return inst.has(key);
  public inline function keys(): Iterator<String>
    return genes.util.IteratorAdapter.create(inst.keys());
  public inline function iterator(): Iterator<T>
    return genes.util.IteratorAdapter.create(inst.values());
  public inline function keyValueIterator(): KeyValueIterator<String, T>
    return (untyped Array.from)(inst.entries()).map(entry -> {
      value: entry[0],
      key: entry[1]
    }).iterator();
  public inline function copy(): StringMap<T>
    return js.Syntax.code('new Map({0})', this);
  public inline function toString(): String {
    return "{" + [for (key in keys()) '$key => ${get(key)}'].join(', ') + "}";
  }
}
#end
