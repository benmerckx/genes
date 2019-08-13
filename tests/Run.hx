package tests;

class Run {
  function new() {
    trace('hello');
  }

  static function main() {
    /*var a = 1 + 2 + 3, b = [1, 5, 6];
    var c = {a: a, b: b}
    var d = haxe.io.Bytes.ofString('abc');
    var i = 25;
    while (i > 10) i--;
    for (j in 0 ... i) trace(j);
    trace(switch i+1 {
      case null: {
        var a = 0;
        a + 'f';
      };
      case 1: 'abc';
      default: '';
    });*/
    var str = "[";
    var x = 20;
    for (i in 0...x)
      str += (if (i > 0) "," else "") + 'a';
    str += "]";
    trace(str);
  }
}
