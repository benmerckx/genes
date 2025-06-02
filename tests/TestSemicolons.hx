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

  // benmerckx/genes#80
  public function testWhileSwitch() {
    var x = 0;
    do
      switch x {
        case 0:
          x++;
        default:
          break;
      } while (x == 0);
    return assert(true);
  }

  // benmerckx/genes#16
  public function testHxOverridesInit() {
    #if (haxe_ver >= 4.1)
    return assert(@:privateAccess HxOverrides.now() > 0);
    #else
    return assert(true);
    #end
  }
}
