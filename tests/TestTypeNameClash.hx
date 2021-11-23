package tests;

@:asserts
class TestTypeNameClash {
  public function new() {}

  public function testNameClash() {
    asserts.assert((tests.foo.MyClass : Class<Dynamic>) != (tests.bar.MyClass : Class<Dynamic>));
    asserts.assert(new tests.foo.MyClass().toString() == 'foo');
    asserts.assert(new tests.bar.MyClass().toString() == 'bar');
    asserts.assert(new ExternMyClass().toString() == 'baz');
    return asserts.done();
  }
}

@:jsRequire('../../tests/extern.js', 'MyClass')
private extern class ExternMyClass {
  function new();
  function toString(): String;
}
