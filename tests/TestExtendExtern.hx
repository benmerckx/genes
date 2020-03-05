package tests;

import tink.unit.Assert.*;

@:jsRequire('../../tests/extern.js', 'default')
extern class ExternClass {
  public var test: Int;
  public function new(num: Int);
}

@:jsRequire('../../tests/extern.js', 'ExtendHaxeClass')
extern class ExtendHaxeClass {
  public function new();
  public function test(): String;
  public var random: Int;
}

class HaxeClass extends ExternClass {
  public function new() {
    test = 1;
    super(2);
    test++;
  }
}

@:jsRequire('../../tests/extern.js', 'Dropdown')
extern class Dropdown {
  public function new();
}

@:jsRequire('../../tests/extern.js', 'Dropdown.Header')
extern class DropdownHeader {
  public var test: Int;
  public function new(num: Int);
}

@:jsRequire('../../tests/extern.js', 'Dropdown.Menu')
extern class DropdownMenu {
  public var test: Int;
  public function new(num: Int);
}

@:asserts
class TestExtendExtern {
  public function new() {}

  public function testExtendExtern() {
    asserts.assert(new HaxeClass().test == 3);
    asserts.assert(new ExternClass(1).test == 1);
    return asserts.done();
  }

  public function testExtendDeferrredHaxeClass() {
    var extendDeferredHaxeClass = new ExtendHaxeClass();
    asserts.assert(extendDeferredHaxeClass.test() == 'ok!');
    asserts.assert(extendDeferredHaxeClass.random > 0);
    return asserts.done();
  }

  // benmerckx/genes#7
  public function testFieldAccess() {
    var d = new Dropdown();
    var d1 = new DropdownMenu(1);
    var d2 = new DropdownHeader(2);
    asserts.assert(Std.is(d, Dropdown));
    asserts.assert(d1.test == 1);
    asserts.assert(d2.test == 2);
    return asserts.done();
  }
}
