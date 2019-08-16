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
    T> {
    return new haxe.iterators.MapKeyValueIterator(this);
  }
  public function copy(): StringMap<T>;
  public function toString(): String;
}
#else
@:native("Map")
extern class StringMap<T> implements haxe.Constraints.IMap<String, T> {
  public function new();
  public function set(key: String, value: T): Void;
  @:arrayAccess public inline function get(key: String): Null<T>
    return (untyped this).get(key);
  public inline function remove(key: String): Bool
    return (untyped this).delete(key);
  public inline function exists(key: String): Bool
    return (untyped this).has(key);
  public inline function keys(): Iterator<String>
    return genes.util.IteratorAdapter.create(cast(untyped this).keys());
  public inline function iterator(): Iterator<T>
    return genes.util.IteratorAdapter.create(cast(untyped this).values());
  public inline function keyValueIterator(): KeyValueIterator<String, T>
    return new haxe.iterators.MapKeyValueIterator(this);
  public inline function copy(): StringMap<T>
    return js.Syntax.code('new Map(this)');
  public inline function toString(): String {
    return "{" + [for (key in keys()) '$key => ${get(key)}'].join(', ') + "}";
  }
}
#end
