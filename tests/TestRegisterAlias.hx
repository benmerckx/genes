package tests;

import tink.unit.Assert.*;

class Register {
  public static var test = 123;

  public function new() {}
}

class TestRegisterAlias {
  public function new() {}

  public function test() {
    assert(Register.test == 132);
    return assert(Std.is(new Register(), Register));
  }
}
