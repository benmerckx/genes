package tests;

using tink.CoreApi;

@:asserts
class TestAbstractClass {
  public function new() {}

  public function abstractClass() {
    final inst = new ConcreteClass();
    asserts.assert(inst.foo() == 'foo');
    asserts.assert(inst.bar() == 'bar');
    asserts.assert(inst.baz() == 'override-baz');
    return asserts.done();
  }
}

abstract class AbstractClass {
  @:keep // make sure this abstract function reaches the generator
  abstract public function foo(): String;

  public function bar(): String
    return 'bar';

  public function baz(): String
    return 'baz';
}

class ConcreteClass extends AbstractClass {
  public function new() {}

  public function foo(): String {
    return 'foo';
  }

  override function baz(): String {
    return 'override-' + super.baz();
  }
}
