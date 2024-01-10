package tests;

import tink.unit.Assert.*;

// benmerckx/genes#72
class TestClass {
  public static function iterator() {
    var array: Array<Int> = [42];
    return array.iterator();
  }
}

class TestIterators {
  public function new() {}

  public function testDynamicIterator() {
    final array: Iterable<Int> = [1, 2, 3];
    return assert([for (n in array) n].join('') == '123');
  }

  public function testGetIteratorOnDynamicArray() {
    final x: Dynamic = [0];
    return assert(x.iterator().next() == 0);
  }

  public function testGetIteratorName() {
    return assert(TestClass.iterator().next() == 42);
  }
}
