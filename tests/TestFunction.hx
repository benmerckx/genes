package tests;

@:asserts
class TestFunction {
  public function new() {}

  public function testDefaultValues() {
    asserts.assert(getDefaultInt() == 31);
    asserts.assert(getDefaultInt(null) == 31);
    asserts.assert(getDefaultInt(32) == 32);
    
    asserts.assert(getDefaultFloat() == 100.56);
    asserts.assert(getDefaultFloat(null) == 100.56);
    asserts.assert(getDefaultFloat(101.99) == 101.99);
    
    asserts.assert(getDefaultBool() == true);
    asserts.assert(getDefaultBool(null) == true);
    asserts.assert(getDefaultBool(false) == false);
    
    asserts.assert(getDefaultString() == ' test ');
    asserts.assert(getDefaultString(null) == ' test ');
    asserts.assert(getDefaultString('testing') == 'testing');
    
    asserts.assert(getDefaultNull() == null);
    asserts.assert(getDefaultNull(null) == null);
    asserts.assert(getDefaultNull(true) == true);
    
    return asserts.done();
  }

  public function testAnonymousDefaultValues() {
    var test = function(a = 1) return a;
    
    asserts.assert(test() == 1);
    asserts.assert(test(null) == 1);
    asserts.assert(test(2) == 2);
    
    inline function inlined(a = 1) return a;
    
    asserts.assert(inlined() == 1);
    asserts.assert(inlined(null) == 1);
    asserts.assert(inlined(2) == 2);
    
    return asserts.done();
  }

  public function testDefaultValueWithReservedName() {
    var test = function(native = 1) return native;
    
    asserts.assert(test() == 1);
    asserts.assert(test(null) == 1);
    asserts.assert(test(2) == 2);
    
    return asserts.done();
  }

  function getDefaultInt(a = 31) {
    return a;
  }

  function getDefaultFloat(a = 100.56) {
    return a;
  }

  function getDefaultBool(a = true) {
    return a;
  }

  function getDefaultString(a = ' test ') {
    return a;
  }

  function getDefaultNull(a = null) {
    return a;
  }
}
