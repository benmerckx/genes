package tests;

import tests.util.ModuleSource.sourceCode;

@:genes.type('number') typedef Overwritten = Dynamic;

@:asserts
class TestTsTypes {
  var types = sourceCode(true);

  @:genes.type('number') @:keep public final prop = 'string';

  public function new() {}

  public function testType() {
    asserts.assert(types.indexOf('type Overwritten = number') > -1);
    asserts.assert(types.indexOf('prop: number') > -1);
    return asserts.done();
  }
}
