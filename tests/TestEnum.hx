package tests;

import tink.unit.Assert.*;

enum Gen<A, B> {
  Single:Gen<A, B>;
  Multi(a: A, b: B):Gen<Bool, B>;
  More<T>(a : A, b : B, c : T) : Gen<T, T>;
}

@:asserts
class TestEnum {
  public function new() {}

  function test()
    return assert(true);
}
