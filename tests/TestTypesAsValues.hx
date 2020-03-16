package tests;

import tink.unit.Assert.*;

private interface MyInterface {}

private class MyClass implements MyInterface implements ExternalInterface {
  public function new() {}
}

// See benmerckx/genes#15

@:asserts
class TestTypesAsValues {
  public function new() {}

  public function testInterfaces() {
    asserts.assert(MyInterface != null);
    asserts.assert(ExternalInterface != null);
    asserts.assert(Std.is(new MyClass(), MyInterface));
    asserts.assert(Std.is(new MyClass(), ExternalInterface));
    return asserts.done();
  }

  public function testAbstract() {
    asserts.assert(Std.is(true, Bool));
    asserts.assert(Std.is(1, Int));
    asserts.assert(Std.is(1.0, Float));
    asserts.assert(Std.is('test', String));
    asserts.assert(Std.is([], Array));
    asserts.assert(Bool != null);
    asserts.assert(Int != null);
    asserts.assert(Float != null);
    asserts.assert(String != null);
    asserts.assert(Array != null);
    return asserts.done();
  }
}
