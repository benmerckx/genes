package tests;

import tink.unit.Assert.*;

class TestBase {
  public function new() {}
}

class TestCycle2 extends TestBase {
  public static var testValue = TestCycle.testValue + 1;
  public static var testValue2 = 2;

  var toTest = TestCycle.testValue;

  public function test()
    return assert(toTest == 1);
}
