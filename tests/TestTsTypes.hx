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

@:keep
class ParametrizedStaticVarInClass<T:{}> {
  public static final CLASS_INST: ParametrizedStaticVarInClass<String> = null;
}

@:keep
abstract ParametrizedStaticVarInAbstract<T>(Int) {
  public static final ABSTRACT_INST: ParametrizedStaticVarInAbstract<String> = null;
}

@:asserts
class TestTsTypes {
  var types = sourceCode(true);

  @:genes.type('number') @:keep public final prop = 'string';

  @:keep final v1 = ParametrizedStaticVarInClass.CLASS_INST; // ensure the types are generated
  @:keep final v2 = ParametrizedStaticVarInAbstract.ABSTRACT_INST; // ensure the types are generated

  public function new() {}

  public function testType() {
    asserts.assert(types.contains('export type X1<T> = T'));
    asserts.assert(types.contains('type Overwritten = number'));
    asserts.assert(types.contains('prop: number'));
    asserts.assert(types.contains('T extends __A & __B'));
    asserts.assert(types.contains('import {ExternalEnum} from'));
    asserts.assert(types.contains('a: param2'));
    asserts.assert(types.contains('<param1'));
    return asserts.done();
  }

  // https://github.com/benmerckx/genes/issues/50
  public function testIssue50() {
    asserts.assert(types.contains('static CLASS_INST: ParametrizedStaticVarInClass<string>'));
    asserts.assert(types.contains('static ABSTRACT_INST: number'));
    return asserts.done();
  }

  public function testCompile() {
    // make sure TS compiler approves the generated codes
    asserts.assert(Sys.command('tsc', ['bin/tests.d.ts']) == 0);
    return asserts.done();
  }
}
