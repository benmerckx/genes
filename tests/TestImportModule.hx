package tests;

import tests.util.ModuleSource.sourceCode;
import tink.unit.AssertionBuffer;
import tests.ExternalEnum;
import tests.ExternalClass;
import tests.ExternalClass2;
import tests.foo.MyClass as FooClass;
import tests.bar.MyClass as BarClass;

using StringTools;
using tink.CoreApi;

@:asserts
class TestImportModule {
  var source = sourceCode();

  public function new() {}

  public function testImportEnum(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalEnum -> {
      asserts.assert(ExternalEnum.A != null);
      asserts.assert(Std.is(ExternalEnum.A, ExternalEnum));
      asserts.assert(!enumStaticallyImported(ExternalEnum));
      return asserts.done();
    }).ofJsPromise();
  }

  public function testImportModule(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalClass -> {
      var a = new ExternalClass();
      asserts.assert(Std.is(a, ExternalClass));
      asserts.assert(ExternalClass.success() == 'success');
      asserts.assert(!classStaticallyImported(ExternalClass));
      return asserts.done();
    }).ofJsPromise();
  }

  public function testImportSubModule(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalSubClass -> {
      var a = new ExternalSubClass();
      asserts.assert(Std.is(a, ExternalSubClass));
      asserts.assert(ExternalSubClass.sub() == 'sub');
      asserts.assert(!classStaticallyImported(ExternalSubClass));
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
        asserts.assert(!classStaticallyImported(ExternalClass));
        asserts.assert(!classStaticallyImported(ExternalSubClass));
        asserts.assert(!classStaticallyImported(ExternalClass2));
        asserts.assert(!classStaticallyImported(ExternalSubClass2));
        return asserts.done();
      })
      .ofJsPromise();
  }

  @:exclude
  public function testImportAliased(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport((FooClass, BarClass) -> {
      asserts.assert(new FooClass().toString() == 'foo');
      asserts.assert(new BarClass().toString() == 'bar');
      asserts.assert(!classStaticallyImported(FooClass));
      asserts.assert(!classStaticallyImported(BarClass));
      return asserts.done();
    }).ofJsPromise();
  }

  // TODO: this check is quite rough
  function classStaticallyImported<T>(cls: Class<T>) {
    return staticallyImported(Type.getClassName(cls));
  }

  function enumStaticallyImported<T>(enm: Enum<T>) {
    return staticallyImported(Type.getEnumName(enm));
  }

  function staticallyImported(typeName: String) {
    final name = typeName.split('.').pop();
    return new EReg('^import {.*$name.*} from ".*"$$', 'm').match(source);
  }
}
