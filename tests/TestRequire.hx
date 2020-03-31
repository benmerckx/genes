package tests;

import js.node.Assert;
import js.node.Path;
import tink.unit.Assert.*;

class TestRequire {
  public function new() {}

  public function testMethod() {
    Assert.ok(true);
    return assert(true);
  }

  public function testWildcardMethod() {
    return assert(Path.posix.join('a', 'b') == 'a/b');
  }

  public function testSelfcall() {
    Assert.assert(true);
    return assert(true);
  }
}
