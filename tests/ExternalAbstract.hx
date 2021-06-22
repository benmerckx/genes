package tests;

abstract Some(Int) {
  public function new() {
    this = 38;
  }

  public static function f() {
    var s = new Some();
  }

  public static var x: Int = 3;
}
