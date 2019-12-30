package tests;

import tink.unit.Assert.*;
import tests.TestCycle;

class TestBase extends TestBase0 {
  public var random = 1 + Math.ceil(Math.random() * 100);

  public function new() {}
}

class TestCycle2 extends TestCycleSub {
  public static var inst = new TestCycle2();
  public static var testValue = TestCycle.testValue + 1;
  public static var testValue2 = 2;

  var toTest = TestCycle.testValue;

  public function test()
    return assert(toTest == 1);

  public static function make()
    return TestCycle2.inst;
}
