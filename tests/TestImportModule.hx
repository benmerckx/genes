package tests;

import tink.unit.AssertionBuffer;
import tests.ExternalClass;
import tests.ExternalClass2;

using tink.CoreApi;

// TODO: we should probably also make sure the static import statements are not present in the generated js
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

  public function testImportMultiple(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport((ExternalClass, ExternalSubClass,
        ExternalClass2, ExternalSubClass2) -> {
        var a = new ExternalClass();
        asserts.assert(Std.is(a, ExternalClass));
        asserts.assert(ExternalClass.success() == 'success');
        var a = new ExternalSubClass();
        asserts.assert(Std.is(a, ExternalSubClass));
        asserts.assert(ExternalSubClass.sub() == 'sub');
        var a = new ExternalClass2();
        asserts.assert(Std.is(a, ExternalClass2));
        asserts.assert(ExternalClass2.success() == 'success2');
        var a = new ExternalSubClass2();
        asserts.assert(Std.is(a, ExternalSubClass2));
        asserts.assert(ExternalSubClass2.sub() == 'sub2');
        return asserts.done();
      })
      .ofJsPromise();
  }
}
