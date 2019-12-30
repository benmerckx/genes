package tests;

import tink.unit.Assert.*;

@:jsRequire('../../tests/extern.js')
extern class ExternClass {
  public var test: Int;
  public function new();
}

@:jsRequire('../../tests/extern.js', 'ExtendHaxeClass')
extern class ExtendHaxeClass {
  public function new();
  public function test(): String;
  public var random: Int;
}

class HaxeClass extends ExternClass {
  public function new() {
    super();
    test++;
  }
}

@:asserts
class TestExtendExtern {
  public function new() {}

  public function testExtendExtern() {
    asserts.assert(new HaxeClass().test == 2);
    asserts.assert(new ExternClass().test == 1);
    return asserts.done();
  }

  public function testExtendDeferrredHaxeClass() {
    var extendDeferredHaxeClass = new ExtendHaxeClass();
    asserts.assert(extendDeferredHaxeClass.test() == 'ok!');
    asserts.assert(extendDeferredHaxeClass.random > 0);
    return asserts.done();
  }
}
