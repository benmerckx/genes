package tests;

import tink.unit.AssertionBuffer;
import tests.ExternalClass;

using tink.CoreApi;

@:asserts
class TestImportModule {
  public function new() {}

  public function testImportModule(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalClass -> {
      var a = new ExternalClass();
      asserts.assert(Std.is(a, ExternalClass));
      asserts.assert(ExternalClass.success() == 'success');
      return asserts.done();
    }).ofJsPromise();
  }

  public function testImportSubModule(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalSubClass -> {
      var a = new ExternalSubClass();
      asserts.assert(Std.is(a, ExternalSubClass));
      asserts.assert(ExternalSubClass.sub() == 'sub');
      return asserts.done();
    }).ofJsPromise();
  }
}
