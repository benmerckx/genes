package tests;

interface MyInterface {}

class MyInstance implements MyInterface {
  public function new() {}
}

@:asserts
class TestBoot {
  public function new() {}

  public function testSafeCast() {
    var a: Dynamic = new TestBoot();
    asserts.assert((cast(a, TestBoot)) == a);
    return asserts.done();
  }

  public function testInterfaceCast() {
    var instance = new MyInstance();
    asserts.assert((cast(instance, MyInterface)) == instance);
    return asserts.done();
  }
}
