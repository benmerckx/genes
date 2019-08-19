package haxe.ds;

#if !js
extern class IntMap<T> implements haxe.Constraints.IMap<Int, T> {
  public function new(): Void;
  public function set(key: Int, value: T): Void;
  public function get(key: Int): Null<T>;
  public function exists(key: Int): Bool;
  public function remove(key: Int): Bool;
  public function keys(): Iterator<Int>;
  public function iterator(): Iterator<T>;
  @:runtime public inline function keyValueIterator(): KeyValueIterator<Int, T>
    return new haxe.iterators.MapKeyValueIterator(this);
  public function copy(): IntMap<T>;
  public function toString(): String;
}
#else
@:native('Map')
extern class IntMap<T> implements haxe.Constraints.IMap<Int, T> {
  public function new();
  var inst(get, never): js.lib.Map<Int, T>;
  inline function get_inst(): js.lib.Map<Int, T>
    return cast this;
  @:arrayAccess public function set(key: Int, value: T): Void;
  @:arrayAccess public function get(key: Int): Null<T>;
  public inline function remove(key: Int): Bool
    return inst.delete(key);
  public inline function exists(key: Int): Bool
    return inst.has(key);
  public inline function keys(): Iterator<Int>
    return genes.util.IteratorAdapter.create(inst.keys());
  public inline function iterator(): Iterator<T>
    return genes.util.IteratorAdapter.create(inst.values());
  public inline function keyValueIterator(): KeyValueIterator<Int, T>
    return (untyped Array.from)(inst.entries()).map(entry -> {
      value: entry[0],
      key: entry[1]
    }).iterator();
  public inline function copy(): IntMap<T>
    return js.Syntax.code('new Map({0})', this);
  public inline function toString(): String {
    return "{" + [for (key in keys()) '$key => ${get(key)}'].join(', ') + "}";
  }
}
#end
