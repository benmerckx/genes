package tests;

import tink.unit.AssertionBuffer;
import tests.ExternalClass;
import tests.ExternalClass2;
import tests.foo.MyClass as FooClass;
import tests.bar.MyClass as BarClass;

using StringTools;
using tink.CoreApi;

@:asserts
class TestImportModule {
  var source: String;

  public function new() {}

  @:setup
  public function setup() {
    final url: String = js.Syntax.code('import.meta.url');
    return if (url.startsWith('file://')) {
      source = sys.io.File.getContent(url.substr('file://'.length));
      Promise.NOISE;
    } else {
      Promise.reject(new Error('Unexpected URL: $url'));
    }
  }

  public function testImportModule(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalClass -> {
      var a = new ExternalClass();
      asserts.assert(Std.is(a, ExternalClass));
      asserts.assert(ExternalClass.success() == 'success');
      asserts.assert(!staticallyImported(ExternalClass));
      return asserts.done();
    }).ofJsPromise();
  }

  public function testImportSubModule(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport(ExternalSubClass -> {
      var a = new ExternalSubClass();
      asserts.assert(Std.is(a, ExternalSubClass));
      asserts.assert(ExternalSubClass.sub() == 'sub');
      asserts.assert(!staticallyImported(ExternalSubClass));
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
        asserts.assert(!staticallyImported(ExternalClass));
        asserts.assert(!staticallyImported(ExternalSubClass));
        asserts.assert(!staticallyImported(ExternalClass2));
        asserts.assert(!staticallyImported(ExternalSubClass2));

        return asserts.done();
      })
      .ofJsPromise();
  }

  public function testImportAliased(): Promise<AssertionBuffer> {
    return genes.Genes.dynamicImport((FooClass, BarClass) -> {
      asserts.assert(new FooClass().toString() == 'foo');
      asserts.assert(new BarClass().toString() == 'bar');
      asserts.assert(!staticallyImported(FooClass));
      asserts.assert(!staticallyImported(BarClass));
      return asserts.done();
    }).ofJsPromise();
  }

  // TODO: this check is quite rough
  function staticallyImported<T>(cls: Class<T>) {
    final name = Type.getClassName(cls).split('.').pop();
    return new EReg('^import {.*$name.*} from ".*"$$', 'm').match(source);
  }
}
