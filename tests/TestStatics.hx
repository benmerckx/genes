package tests;

import tink.unit.Assert.*;

class TestStatics {
  public function new() {}

  public function testReservedName() {
    return assert(TestStatics.name() == 'my-name');
  }

  public function testReservedLength() {
    return assert(TestStatics.length == 5);
  }

  static var length = 5;

  static function name() {
    return 'my-name';
  }
}
