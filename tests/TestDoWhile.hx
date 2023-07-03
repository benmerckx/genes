package tests;

import tink.unit.Assert.*;

class TestDoWhile {
  public function new() {}

  public function testDoWhileExpr() {
    var i = 0;
    do i++ while(i < 10);
    return assert(i == 10);
  }
  public function testDoWhileBody() {
    var a = 0;
    var b = 0;
    do {
      a++;
      b++;
    } while(a < 10);
    return assert(b == 10);
  }
}
