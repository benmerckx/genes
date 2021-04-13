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
    asserts.assert(types.indexOf('type A_ = number | string') > -1);
    asserts.assert(types.indexOf('type B_ = B') > -1);
    asserts.assert(types.indexOf('type C_ = C') > -1);
    return asserts.done();
  }
}
