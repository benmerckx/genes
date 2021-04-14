package tests;

import tests.util.ModuleSource.sourceCode;
import haxe.extern.EitherType in A;
import tests.ExternalClass in B;
import tests.ExternalTypedef.B as C;

typedef A_ = A<Int, String>;
typedef B_ = B;
typedef C_ = C;

@:asserts
class TestTypeAlias {
  var types = sourceCode(true);

  public function new() {}

  public function testType() {
    asserts.assert(types.contains('type A_ = number | string'));
    asserts.assert(types.contains('type B_ = B'));
    asserts.assert(types.contains('type C_ = C'));
    return asserts.done();
  }
}
