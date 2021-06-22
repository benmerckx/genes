package tests;

import tests.util.ModuleSource.sourceCode;
import tests.ExternalAbstract;

// https://github.com/benmerckx/genes/issues/47
@:asserts
class TestAbstract {
  var code = sourceCode();

  public function new() {}

  public function testAbstractName() {
    asserts.assert(Some.x == 3);
    return asserts.done();
  }
}
