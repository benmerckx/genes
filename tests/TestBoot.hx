package tests;

@:asserts
class TestBoot {
  public function new() {}

  public function testSafCast() {
    var a: Dynamic = new TestBoot();
    asserts.assert((cast(a, TestBoot)) == a);
    return asserts.done();
  }
}
