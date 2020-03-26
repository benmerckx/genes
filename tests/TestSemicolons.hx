package tests;

import tink.unit.Assert.*;

class TestSemicolons {
  public function new() {}

  static var href = {
    var correct = true;
    js.Syntax.code('(function() {})();');
    correct;
  }

  // benmerckx/genes#8
  public function testSemicolons() {
    return assert(href);
  }

  // benmerckx/genes#16
  public function testHxOverridesInit() {
    return assert(@:privateAccess HxOverrides.now() > 0);
  }
}
