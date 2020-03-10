package tests;

@:asserts
class TestBind {
  public function new() {}

  function test(a, b)
    return a + b;

  dynamic function foo(): String
    return 'foo';

  static function notNull(f: () -> String)
    return f != null;

  static function run(f: () -> String)
    return if (f != null) f() else 'null';

  // benmerckx/genes#10
  public function testInstanceMethodBind() {
    asserts.assert(notNull(foo));
    asserts.assert(run(foo) == 'foo');
    foo = null;
    asserts.assert(!notNull(foo));
    asserts.assert(run(foo) == 'null');
    foo = () -> 'foo';
    return asserts.done();
  }

  public function testInstanceMethodBindFromFieldAccess() {
    function exec(o: {test: TestBind}) {
      asserts.assert(notNull(o.test.foo));
      asserts.assert(run(o.test.foo) == 'foo');
      o.test.foo = null;
      asserts.assert(!notNull(o.test.foo));
      asserts.assert(run(o.test.foo) == 'null');
      return asserts.done();
    }

    return exec({test: this});
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
