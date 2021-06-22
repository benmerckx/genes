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

  public function testGlobalType() {
    asserts.assert(Object != cast js.lib.Object); // class Object is defined in another module
    asserts.assert(Promise != cast js.lib.Promise); // class Promise is defined in current module
    return asserts.done();
  }
}

class Promise {}
