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
    asserts.assert(Promise != cast js.lib.Promise);
    asserts.assert(Event != cast js.html.Event);
    return asserts.done();
  }
}

// name clash with js.lib.Promise
class Promise {}

// name clash with js.html.Event
class Event {}
