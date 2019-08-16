package tests;

import js.node.Assert;
import tink.unit.Assert.*;

class TestRequire {
  public function new() {}

  public function testMethod() {
    Assert.ok(true);
    return assert(true);
  }

  public function testSelfcall() {
    Assert.assert(true);
    return assert(true);
  }
}
