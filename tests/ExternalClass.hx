package tests;

import tests.TestCycle2.TestBase;

class ExternalSubClass {
  public function new() {}

  public static function sub() {
    return 'sub';
  }
}

class ExternalClass extends TestBase {
  public function new() {
    super();
  }

  @:keep public function test() {
    return 'ok';
  }

  public static function success() {
    return 'success';
  }
}

class Object {
  public function new() {}
}
