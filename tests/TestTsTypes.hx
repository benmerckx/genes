package tests;

import tests.util.ModuleSource.sourceCode;

typedef __A = {a: Int}
typedef __B = {b: String}
@:genes.type('number') typedef Overwritten = Dynamic;

@:keep
enum TestEnumConstraints<T:__A> {
  CTor<A:__A>
  (_ : Int) : TestEnumConstraints<A>;
}

@:keep
class TsMethods<T:{}> {
  public function typeConstraints<T: (__A & __B)>() {}
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
    return asserts.done();
  }
}
