package tests;

import tink.unit.Assert.*;

@:asserts
class TestMap {
  public function new() {}

  public function testStringMap() {
    final map = new Map<String, Bool>();
    map.set('test', true);
    asserts.assert(map.get('test'));
    asserts.assert(map.copy()['test']);
    asserts.assert([for (k in map.keys()) k][0] == 'test');
    asserts.assert([for (v in map) v][0]);
    asserts.assert([for (k => v in map) v][0]);
    asserts.assert(map['test']);
    return asserts.done();
  }

  public function testIntMap() {
    final map = new Map<Int, Bool>();
    map.set(1, true);
    asserts.assert(map.get(1));
    asserts.assert(map.copy()[1]);
    asserts.assert([for (k in map.keys()) k][0] == 1);
    asserts.assert([for (v in map) v][0]);
    asserts.assert([for (k => v in map) v][0]);
    asserts.assert(map[1]);
    return asserts.done();
  }

  public function testObjectMap() {
    final key = {}
    final map = new Map<{}, Bool>();
    map.set(key, true);
    asserts.assert(map.get(key));
    asserts.assert(map.copy()[key]);
    asserts.assert([for (k in map.keys()) k][0] == key);
    asserts.assert([for (v in map) v][0]);
    asserts.assert([for (k => v in map) v][0]);
    asserts.assert(map[key]);
    return asserts.done();
  }
}
