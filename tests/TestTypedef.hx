package tests;

import tink.unit.Assert.*;

typedef A = {
  test: Int
}

@:asserts
class TestTypedef {
  public function new() {}

  function test(): A
    return {test: 1}

  function testB(): ExternalTypedef.B
    return {test: 1}

  public function testTypedef() {
    asserts.assert(test().test == 1);
    asserts.assert(testB().test == 1);
    return asserts.done();
  }
}
