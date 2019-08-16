package tests;

import tink.unit.Assert.*;

class TestMap {
  public function new() {}

  public function testStringMap() {
    final map = new Map<String, Bool>();
    map.set('test', true);
    return assert(map.get('test'));
  }
}
