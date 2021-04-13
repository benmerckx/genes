package tests;

import tests.util.ModuleSource.sourceCode;
import haxe.extern.EitherType in Either;

typedef E = Either<Int, String>;

@:asserts
class TestEitherAlias {
  var types = sourceCode(true);

  public function new() {}

  public function testType() {
    asserts.assert(types.indexOf('number | string') > -1);
    return asserts.done();
  }
}
