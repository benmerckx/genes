package tests;

@:asserts
class TestDefaultValue {
  public function new() {}

  @:exclude
  public function issue54() {
    asserts.assert(foo(1) == 1);
    asserts.assert(foo() == 42);
    asserts.assert(foo(null) == 42);
    return asserts.done();
  }

  function foo(v = 42) {
    return v;
  }
}
