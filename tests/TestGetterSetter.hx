package tests;

import tink.unit.Assert.*;

@:asserts
class TestGetterSetter {
  public var a(get, set): Int;
  @:isVar public var b(get, set): Int = 1;

  // benmerckx/genes#19
  static var inst(get, null): String;

  static function get_inst() {
    if (inst == null)
      inst = 'foo';
    return inst;
  }

  function get_b()
    return b;

  function set_b(num: Int)
    return b = num;

  function get_a()
    return 1;

  function set_a(num: Int)
    return 2;

  public function new() {}

  public function testGetter() {
    asserts.assert(inst == 'foo');
    asserts.assert(a == 1);
    asserts.assert(b == 1);
    asserts.assert(Reflect.field(this, 'a') == 1);
    return asserts.done();
  }

  public function testSetter() {
    asserts.assert((a = 0) == 2);
    asserts.assert(a == 1);
    asserts.assert((b = 0) == 0);
    asserts.assert(b == 0);
    return asserts.done();
  }
}
