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
}
#else
@:native('Map')
extern class ObjectMap<K:{}, V> implements haxe.Constraints.IMap<K, V> {
  public function new();
  var inst(get, never): js.lib.Map<K, V>;
  inline function get_inst(): js.lib.Map<K, V>
    return cast this;
  @:arrayAccess public function set(key: K, value: V): Void;
  @:arrayAccess public function get(key: K): Null<V>;
  public inline function remove(key: K): Bool
    return inst.delete(key);
  public inline function exists(key: K): Bool
    return inst.has(key);
  public inline function keys(): Iterator<K>
    return genes.util.IteratorAdapter.create(inst.keys());
  public inline function iterator(): Iterator<V>
    return genes.util.IteratorAdapter.create(inst.values());
  public inline function keyValueIterator(): KeyValueIterator<K, V>
    return (untyped Array.from)(inst.entries()).map(entry -> {
      value: entry[0],
      key: entry[1]
    }).iterator();
  public inline function copy(): ObjectMap<K, V>
    return js.Syntax.code('new Map({0})', this);
  public inline function toString(): String {
    return "{" + [for (key in keys()) '$key => ${get(key)}'].join(', ') + "}";
  }
}
#end
