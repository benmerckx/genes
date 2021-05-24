package tests;

import tests.util.ModuleSource.sourceCode;

typedef __A = {a: Int}
typedef __B = {b: String}
@:genes.type('number') typedef Overwritten = Dynamic;

@:keep
enum TestEnumConstraints<T:__A> {
  CTor<A:__A>
  (_ : Int) : TestEnumConstraints<A>;
  TestImportTypeConstraint<X:ExternalEnum>
  (_ : Int);
}

@:keep
class TsMethods<T:{}> {
  public function typeConstraints<T: (__A & __B)>() {}

  public function testParamType<@:genes.type('param1') T>(@:genes.type('param2') a: Int) {}
}

@:asserts
class TestTsTypes {
  var types = sourceCode(true);

  @:genes.type('number') @:keep public final prop = 'string';

  public function new() {}

  public function testType() {
    asserts.assert(types.contains('type Overwritten = number'));
    asserts.assert(types.contains('prop: number'));
    asserts.assert(types.contains('T extends __A & __B'));
    asserts.assert(types.contains('import {ExternalEnum} from'));
    asserts.assert(types.contains('a: param2'));
    asserts.assert(types.contains('<param1'));
    return asserts.done();
  }
}
