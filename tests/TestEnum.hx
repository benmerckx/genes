package tests;

import tink.unit.Assert.*;

enum Gen<A, B> {
  Single:Gen<String, Int>;
  Multi(a: A, b: B):Gen<Bool, B>;
  More<T>(a : A, b : B, c : T) : Gen<T, T>;
}

class TestEnum {
  public function new() {}

  public function test()
    return assert(Gen.Single == Gen.Single);
}
