package tests;

import tink.unit.Assert.*;

abstract Foo(String) {
  public inline function new()
    this = '';

  public function foo() {
    return '100';
  }
}

class TestSyntax {
  public function new() {}

  // benmerckx/genes#17
  public function testCode() {
    return assert(js.Syntax.code("parseFloat({0})", new Foo().foo()) == 100);
  }
}
