package tests;

import tink.unit.Assert.*;

// benmerckx/genes#72

class TestClass {
  public static function testIterator(a: String) {
    return iterator(a);
  }

  public static function iterator(a: String) {
    return a;
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

  public function testIteratorName() {
    return assert(TestClass.testIterator('ok') == 'ok');
  }

  public function testDynamicIteratorExpr() {
    final a: Dynamic = {
      iterator: 0
    }
    return assert(a.iterator == 0);
  }

  public function testDynamicArrayIterator() {
    final a: Dynamic = [0];
    return assert(a.iterator().next() == 0);
  }

  public function testDynamicArrayIteratorProperty() {
    final a: Dynamic = [0];
    final x = a.iterator;
    return assert(x().next() == 0);
  }
}
