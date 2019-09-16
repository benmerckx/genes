package tests;

import tink.unit.Assert.*;
import tests.TestCycle2;

class TestCycle extends TestBase {
  public static var testValue = TestCycle2.testValue2 - 1;

  var toTest = TestCycle2.testValue;

  public function test()
    return assert(toTest == 2);
}
