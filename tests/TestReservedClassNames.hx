package tests;

import tests.ExternalClass;

class Reserved extends Object {}

// Some bundlers (parcel) will mess up extending know global class names
// like Object

@:asserts
class TestReservedClassNames {
  public function new() {}

  public function testExtendsObject() {
    asserts.assert(Std.is(new Reserved(), Object));
    return asserts.done();
  }
}
