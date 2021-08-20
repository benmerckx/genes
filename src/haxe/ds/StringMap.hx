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
  public function clear(): Void;
}
#else
class StringMap<T> extends genes.util.EsMap<String, T> implements haxe.Constraints.IMap<String, T> {
  public inline function copy(): StringMap<T> {
    var copied = new StringMap();
    copied.inst = new js.lib.Map(inst);
    return cast copied;
  }

  @:runtime public inline function keyValueIterator(): KeyValueIterator<String,
    T>
    return new haxe.iterators.MapKeyValueIterator(this);
}
#end
