package tests;

import tink.unit.Assert.*;

class TestIterators {
  public function new() {}

  public function testDynamicIterator() {
    final array: Iterable<Int> = [1, 2, 3];
    return assert([for (n in array) n].join('') == '123');
  }
}
