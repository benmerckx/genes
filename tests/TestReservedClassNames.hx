package tests;

import tests.ExternalClass;

class Reserved extends Object {}

// Some bundlers (parcel) will mess up extending know global class names
// like Object

@:asserts
class TestReservedClassNames {
  public function new() {}

  public function testExtendsObject() {
    asserts.assert(Std.is(new Reserved(), Object));
    return asserts.done();
  }

  public function testGlobalType() {
    /*
      asserts.assert(Object != cast js.lib.Object); // class Object is defined in another module
      asserts.assert(Promise != cast js.lib.Promise); // class Promise is defined in current module
      asserts.assert(Collator != cast js.lib.intl.Collator); // Collator is a sub-type of Intl `@:native("Intl.Collator")`

      final nativePromise: Dynamic = js.lib.Promise; // we can actually reference the native Promise type
      asserts.assert(Type.getClassName(nativePromise) == null); // no "haxe class name" for native types
      asserts.assert(nativePromise.name == 'Promise'); // every js function has a `name`

      final customPromise: Dynamic = Promise; // we can actually reference the custom Promise type
      asserts.assert(Type.getClassName(customPromise) == 'tests.Promise');
      asserts.assert(customPromise.name == 'Promise'); // every js function has a `name`
     */

    return asserts.done();
  }
}

class Promise {}
class Collator {}
