package tests;

import tink.unit.Assert.*;

// benmerckx/genes#8
class TestSemicolons {
  public function new() {}

  static var href = {
    var correct = true;
    js.Syntax.code('(function() {})();');
    correct;
  }

  public function testSemicolons() {
    return assert(href);
  }
}
