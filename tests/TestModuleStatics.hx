package tests;

final foo = 'bar';

function hello()
  return 'world';

@:asserts
class TestModuleStatics {
  public function new() {}

  public function testModuleStatics() {
    asserts.assert(foo == 'bar');
    asserts.assert(hello() == 'world');
    return asserts.done();
  }
}
