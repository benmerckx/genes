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
  public function clear(): Void;
}
#else
class IntMap<T> extends genes.util.EsMap<Int, T> implements haxe.Constraints.IMap<Int, T> {
  public inline function copy(): IntMap<T> {
    var copied = new IntMap();
    copied.inst = new js.lib.Map(inst);
    return cast copied;
  }

  @:runtime public inline function keyValueIterator(): KeyValueIterator<Int, T>
    return new haxe.iterators.MapKeyValueIterator(this);
}
#end
