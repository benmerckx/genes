package tests;

import tink.unit.Assert.*;

@:native('React.Component')
extern class ComponentA {}

@:jsRequire('react', 'Component')
@:native('React.Component')
extern class ComponentB {}

abstract Foo(String) {
  public inline function new()
    this = '';

  public function foo() {
    return '100';
  }
}

@:asserts
class TestSyntax {
  public function new() {}

  // benmerckx/genes#17
  public function testCode() {
    return assert(js.Syntax.code("parseFloat({0})", new Foo().foo()) == 100);
  }

  // benmerckx/genes#57
  public function testGlobal() {
    untyped global.a = 1;
    asserts.assert(js.Lib.global.a == 1);
    asserts.assert(js.Syntax.code('{0}', js.Lib.global.a) == 1);
    return asserts.done();
  }

  // benmerckx/genes#27
  public function testCodeTypeAccessor() {
    asserts.assert(js.Syntax.code('{0}', ComponentA) == ComponentA);
    asserts.assert(js.Syntax.code('{0}', ComponentB) == ComponentB);
    return asserts.done();
  }
}
