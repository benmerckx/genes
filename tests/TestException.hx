package tests;

@:asserts
class TestException {
  public function new() {}

  @:include
  // https://github.com/benmerckx/genes/issues/40
  public function exception() {
    var error = null;
    try
      throw new haxe.Exception('foo')
    catch (e) {
      asserts.assert(e.message == 'foo');
      asserts.assert((cast e).message == 'foo'); // native access
    }
    return asserts.done();
  }
}
