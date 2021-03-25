package tests;

@:asserts
class TestException {
  public function new() {}

  // https://github.com/benmerckx/genes/issues/40
  public function exception() {
    final e = new haxe.Exception('foo');
    asserts.assert(e.message == 'foo');
    asserts.assert((cast e).message == 'foo'); // native access
    return asserts.done();
  }
}
