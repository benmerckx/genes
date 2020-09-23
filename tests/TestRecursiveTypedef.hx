package tests;

import tink.unit.Assert.*;

typedef Link<T> = {
  v: T,
  ?next: Link<T>
}

@:asserts
class TestRecursiveTypedef {
  public function new() {}

  function link<T>(v: T, ?next: Link<T>): Link<T>
    return {v: v, next: next}

  public function testTypedef() {
    final a = link(1);
    final b = link(2, a);
    asserts.assert(b.next == a);
    asserts.assert(a.next == null);
    return asserts.done();
  }
}
