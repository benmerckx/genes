package tests;

import tink.unit.Assert.*;
import tests.TestCycle2;

@:asserts
class TestCycle extends TestBase {
  public static var testValue = TestCycle2.testValue2 - 1;

  var toTest = TestCycle2.testValue;

  @:include public function test() {
    var cl: Class<TestCycle2> = TestCycle2;
    var inst = TestCycle2.make();
    var inst2 = TestCycle2.make();
    var inst3 = TestCycle2.inst;
    asserts.assert(Std.is(inst, cl));
    asserts.assert(inst.random == inst2.random);
    asserts.assert(inst2.random == inst3.random);
    asserts.assert(toTest == 2);
    return asserts.done();
  }
}
