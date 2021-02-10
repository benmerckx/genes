package tests;

import tests.TestCycle2.TestBase;

class ExternalSubClass2 {
  public function new() {}

  public static function sub() {
    return 'sub2';
  }
}

class ExternalClass2 extends TestBase {
  public function new() {
    super();
  }

  @:keep public function test() {
    return 'ok2';
  }

  public static function success() {
    return 'success2';
  }
}
