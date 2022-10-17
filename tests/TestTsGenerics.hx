package tests;

import tests.util.NativePromise;
import tests.util.ModuleSource.sourceCode;
import tests.bar.MyClass in MyClassAlias;

@:asserts
class TestTsGenerics {
  public function new() {}

  var types = sourceCode(true);

  @:keep var checkType: NativePromise<String>;

  public function testType() {
    asserts.assert(types.contains('checkType: Promise<string>'));
    return asserts.done();
  }
}
