package tests;

@:asserts
class TestTypeNameClash {
  public function new() {}

  public function testNameClash() {
    asserts.assert((tests.foo.MyClass : Class<Dynamic>) != (tests.bar.MyClass : Class<Dynamic>));
    asserts.assert(new tests.foo.MyClass().toString() == 'foo');
    asserts.assert(new tests.bar.MyClass().toString() == 'bar');
    return asserts.done();
  }
}
