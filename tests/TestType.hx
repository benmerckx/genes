package tests;

import tink.unit.Assert.*;

class TestType {
  public function new() {}

  public function testClassName() {
    return assert(Type.getClassName(Type.getClass(this)) == 'tests.TestType');
  }
}
