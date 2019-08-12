package tests;

class Run {
  function new() {
    trace('hello');
  }

  static function main() {
    var a = 1 + 2 + 3, b = [1, 5, 6];
    b.push(a++);
    trace(a);
  }
}
