package tests;

import tink.unit.Assert.*;

class Assertion {
  public static final positive = true;
}

class TestImportAlias {
  public function new() {}

  public function test() {
    return assert(Assertion.positive);
  }
}
