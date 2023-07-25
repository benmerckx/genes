package tests;

import tink.unit.Assert.*;

enum Gen<A, B> {
  Single:Gen<String, A>;
  Multi(a: A, b: B):Gen<Bool, B>;
  More<T>(a: A, b: B, c: T):Gen<T, T>;
}

enum Order {
  Asc;
  Desc;
}

enum abstract Str(String) to String {
  final A = 'a';
}

// https://github.com/benmerckx/genes/issues/46
enum Query {
  Delete(delete: {});
}

@:asserts
class TestEnum {
  @:keep var query = Delete({});

  public function new() {}

  public function test()
    return assert(Gen.Single == Gen.Single);

  public function testAbstract()
    return assert((Str.A : String) == 'a');

  public function testConstructorOrder()
    return assert(Asc.getName().toUpperCase() == 'ASC');

  #if (genes.enum_discriminator)
  public function testEnumDiscriminator() {
    final discriminator = haxe.macro.Compiler.getDefine('genes.enum_discriminator');
    asserts.assert(Reflect.field(Asc, discriminator) == 'Asc');
    asserts.assert(Reflect.field(Multi(1, 2), discriminator) == 'Multi');
    return asserts.done();
  }
  #end
}
