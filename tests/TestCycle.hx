package tests;

import tink.unit.Assert.*;
import tests.TestCycle2;

@:asserts
class TestCycle extends TestBase {
  public static var testValue = TestCycle2.testValue2 - 1;

  var toTest = TestCycle2.testValue;

  public function test() {
    asserts.assert(new ExternalClass().test() == 'ok');
    var inst = TestCycle2.make();
    var inst2 = TestCycle2.make();
    var inst3 = TestCycle2.inst;
    asserts.assert(inst.random == inst2.random);
    asserts.assert(inst2.random == inst3.random);
    asserts.assert(toTest == 2);
    return asserts.done();
  }
}

class TestCycleSub extends TestBase {
  public var cycle = true;
}

class TestBase0 {}
