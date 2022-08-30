package tests;

import tink.unit.Assert.*;

class TestOperators {
  public function new() {}

  // benmerckx/genes#66
  public function testNullCoalescing() {
    return assert((null ?? 0 ?? 1) == 0);
  }
}
