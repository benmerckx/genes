package tests;

import tink.unit.Assert.*;

class TestTypeA {}

class TestTypeB extends TestTypeA {
  public function new() {}

  @:keep public static var a: String;
  @:keep public static var b: String;
  @:keep public static var c: String;
}

enum TestTypeEnum {
  A;
  B;
  C(param: Int);
}

// https://github.com/benmerckx/genes/issues/77
class MySuperType {
  @:keep var bar = 2;
}

class MyType extends MySuperType {
  @:keep var foo = 1;

  public function new() {}
}

@:asserts
class TestType {
  public function new() {}

  public function testInstanceFields() {
    final fields = Type.getInstanceFields(MyType);
    asserts.assert(fields[0] == 'foo');
    asserts.assert(fields[1] == 'bar');
    return asserts.done();
  }

  public function testAllEnums() {
    final enums = Type.allEnums(TestTypeEnum);
    asserts.assert(enums.length == 2);
    asserts.assert(enums[0] == A);
    asserts.assert(enums[1] == B);
    return asserts.done();
  }

  public function testCreateEmptyInstance() {
    return assert(Std.is(Type.createEmptyInstance(TestTypeA), TestTypeA));
  }

  public function testCreateEnum() {
    return assert(switch Type.createEnum(TestTypeEnum, 'C', [1]) {
      case C(1): true;
      default: false;
    });
  }

  public function testGetEnumName() {
    return assert(Type.getEnumName(TestTypeEnum) == 'tests.TestTypeEnum');
  }

  function testResolveEnum() {
    return assert(Type.resolveEnum('tests.TestTypeEnum') == TestTypeEnum);
  }

  public function testEnumParameters() {
    return assert(Type.enumParameters(C(1))[0] == 1);
  }

  public function testGetEnumConstructs() {
    final constructs = Type.getEnumConstructs(TestTypeEnum);
    asserts.assert(constructs[0] == 'A');
    asserts.assert(constructs[1] == 'B');
    asserts.assert(constructs[2] == 'C');
    return asserts.done();
  }

  public function testEnumIndex() {
    asserts.assert(Type.enumIndex(A) == 0);
    asserts.assert(Type.enumIndex(B) == 1);
    asserts.assert(Type.enumIndex(C(0)) == 2);
    return asserts.done();
  }

  public function testSuperClass() {
    return assert(Type.getSuperClass(TestTypeB) == TestTypeA);
  }

  public function testResolveClass() {
    return assert(Type.resolveClass('tests.TestTypeB') == TestTypeB);
  }

  public function testClassName() {
    return assert(Type.getClassName(Type.getClass(this)) == 'tests.TestType');
  }

  public function testGetClass() {
    return assert(Type.getClass(new TestTypeB()) == TestTypeB);
  }
  /*
    Todo:
    getInstanceFields
    typeof
    getClassFields

    function testGetClassFields() {
      final fields = Type.getClassFields(TestTypeB);
      asserts.assert(fields[0] == 'a');
      asserts.assert(fields[1] == 'b');
      asserts.assert(fields[2] == 'c');
      return asserts.done();
  }*/
}
