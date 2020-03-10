package tests;

@:asserts
class TestBind {
  public function new() {}

  function test(a, b)
    return a + b;

  dynamic function foo(): String
    return 'foo';

  static function log(f: () -> String)
    return f != null;

  // benmerckx/genes#10
  public function testInstanceMethodBind() {
    asserts.assert(log(foo));
    foo = null;
    asserts.assert(!log(foo));
    return asserts.done();
  }

  public function testBind() {
    function test(a, b)
      return a + b;
    final t = new TestBind();
    asserts.assert(test.bind(1)(2) == 3);
    asserts.assert(t.test.bind(_, 1)(2) == 3);
    asserts.assert((test(1, 1) == 2 ? test : t.test).bind(_, 1)(2) == 3);
    asserts.assert((Reflect.field(t, 'test') : Int->Int->Int).bind(1)(2) == 3);
    return asserts.done();
  }
}
