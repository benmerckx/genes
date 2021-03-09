package tests;

import tink.unit.Assert.*;

class TestRest {
  public function new() {}

  public function testMethodRest() {
    final values = someRest('a', 'b');
    return assert(values[0] == 'a' && values[1] == 'b');
  }

  public function testFunctionRest() {
    function someRest(...values: String) {
      return values.toArray();
    }
    final values = someRest('a', 'b');
    return assert(values[0] == 'a' && values[1] == 'b');
  }

  function someRest(...values: String) {
    return values.toArray();
  }
}
