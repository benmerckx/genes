package tests;

@:asserts
class TestFunction {
  public function new() {}

  public function testDefaultValues() {
    asserts.assert(this.getDefaultInt() == 31);
    asserts.assert(this.getDefaultInt(32) == 32);
    asserts.assert(this.getDefaultFloat() == 100.56);
    asserts.assert(this.getDefaultFloat(101.99) == 101.99);
    asserts.assert(this.getDefaultBool() == true);
    asserts.assert(this.getDefaultBool(false) == false);
    asserts.assert(this.getDefaultString() == ' test ');
    asserts.assert(this.getDefaultString('testing') == 'testing');
    asserts.assert(this.getDefaultNull() == null);
    asserts.assert(this.getDefaultNull(true) == true);
    return asserts.done();
  }

  private function getDefaultInt(a = 31) {
    return a;
  }

  private function getDefaultFloat(a = 100.56) {
    return a;
  }

  private function getDefaultBool(a = true) {
    return a;
  }

  private function getDefaultString(a = ' test ') {
    return a;
  }

  private function getDefaultNull(a = null) {
    return a;
  }
}
