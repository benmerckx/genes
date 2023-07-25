package tests;

import tests.util.ModuleSource.sourceCode;
import tests.bar.MyClass in MyClassAlias;

// Make sure we do not try to import this from the current module,
// because it resembles import X in Y;
typedef X1<T> = T;
typedef Y = X1<MyClassAlias>;
typedef __A = {a: Int}
typedef __B = {b: String}
@:genes.type('number') typedef Overwritten = Dynamic;

/** Typedef comment */
typedef Comments = {
  /** Typedef prop comment **/
  var prop: String;

  /** Typedef prop2 comment **/
  var prop2: Int;
}

@:native('renamed')
typedef Rename = String;

@:keep
enum TestEnumConstraints<T:__A> {
  CTor<A:__A>(_: Int):TestEnumConstraints<A>;
  TestImportTypeConstraint<X:ExternalEnum>(_: Int);
}

@:keep
enum BasicEnum {
  A;
  B(value: String);
}

@:keep
class TsMethods<T:{}> {
  public function typeConstraints<T: (__A & __B)>() {}

  public function testParamType<@:genes.type('param1') T>(@:genes.type('param2') a: Int) {}

  public function testInlineAnonymous(a: {a: String, b: String}) {}
}

@:asserts
class TestTsTypes {
  var types = sourceCode(true);

  @:genes.type('number') @:keep public final prop = 'string';

  public function new() {}

  @:keep @:genes.type('() => void')
  function overwriteFunctionType() {}

  @:keep @:genes.returnType('string')
  function changeReturn() {}

  public function testType() {
    asserts.assert(types.contains('export type X1<T> = T'));
    asserts.assert(types.contains('type Overwritten = number'));
    asserts.assert(types.contains('type renamed = string'));
    asserts.assert(types.contains('overwriteFunctionType: () => void'));
    asserts.assert(types.contains('prop: number'));
    asserts.assert(types.contains('T extends __A & __B'));
    asserts.assert(types.contains('import {ExternalEnum} from'));
    asserts.assert(types.contains('a: param2'));
    asserts.assert(types.contains('<param1'));
    asserts.assert(types.contains('changeReturn(): string'));
    asserts.assert(types.contains('Typedef comment'));
    asserts.assert(types.contains('Typedef prop comment'));
    asserts.assert(types.contains('Typedef prop2 comment'));

    // benmerckx/genes#70
    asserts.assert(types.contains('"$$kind": "A", '));
    asserts.assert(types.contains('"$$kind": "B", '));
    return asserts.done();
  }
}
