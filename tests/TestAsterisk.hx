package tests;

using tink.CoreApi;

@:asserts
class TestAsterisk {
  public function new() {}

  public function enumAbstract() {
    asserts.assert((Dummy.A : Int) == 1);
    asserts.assert((Dummy.B : Int) == 2);
    return asserts.done();
  }
}

@:jsRequire('../../tests/enum.js')
private extern enum abstract Dummy(Int) to Int {
  final A;
  final B;
}
