package haxe.ds;

#if !js
extern class ObjectMap<K:{}, V> implements haxe.Constraints.IMap<K, V> {
  public function new(): Void;
  public function set(key: K, value: V): Void;
  public function get(key: K): Null<V>;
  public function exists(key: K): Bool;
  public function remove(key: K): Bool;
  public function keys(): Iterator<K>;
  public function iterator(): Iterator<V>;
  @:runtime public inline function keyValueIterator(): KeyValueIterator<K, V>
    return new haxe.iterators.MapKeyValueIterator(this);
  public function copy(): ObjectMap<K, V>;
  public function toString(): String;
  public function clear(): Void;
}
#else
class ObjectMap<K:{},
  V> extends genes.util.EsMap<K, V> implements haxe.Constraints.IMap<K, V> {
  public inline function copy(): ObjectMap<K, V> {
    var copied = new ObjectMap();
    copied.inst = new js.lib.Map(inst);
    return cast copied;
  }

  @:runtime public inline function keyValueIterator(): KeyValueIterator<K, V>
    return new haxe.iterators.MapKeyValueIterator(this);
}
#end
