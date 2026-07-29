package reflectionclassvalues;

/**
 * Same-source proof for Haxe class values used by runtime reflection.
 *
 * JavaScript implements every emitted class constructor as a Function object.
 * The static methods below intentionally reuse names from JavaScript's
 * Function interface while keeping ordinary Haxe signatures.
 */
class Main {
  public static function main(): Void {
    final reflected = [
      reflectedName(new ToStringCollision()),
      reflectedName(new ApplyCollision()),
      reflectedName(new CompatibleToString()),
      reflectedName(new CompatibleApply()),
      reflectedName(new CallCollision()),
      reflectedName(new BindCollision()),
      reflectedName(new NativeApplyCollision()),
      reflectedName(new NativeApplyEscape()),
      reflectedName(new PropertyCollision()),
      reflectedName(new InheritedCollision()),
      reflectedName(new OrdinaryClass()),
      reflectedName(new ImplementsMarker())
    ];
    final resolved = [
      resolvedName("reflectionclassvalues._Main.ToStringCollision"),
      resolvedName("reflectionclassvalues._Main.ApplyCollision"),
      resolvedName("reflectionclassvalues._Main.CompatibleToString"),
      resolvedName("reflectionclassvalues._Main.CompatibleApply"),
      resolvedName("reflectionclassvalues._Main.CallCollision"),
      resolvedName("reflectionclassvalues._Main.BindCollision"),
      resolvedName("reflectionclassvalues._Main.NativeApplyCollision"),
      resolvedName("reflectionclassvalues._Main.NativeApplyEscape"),
      resolvedName("reflectionclassvalues._Main.PropertyCollision"),
      resolvedName("reflectionclassvalues._Main.InheritedCollision"),
      resolvedName("reflectionclassvalues._Main.OrdinaryClass"),
      resolvedName("reflectionclassvalues._Main.ImplementsMarker")
    ];
    final statics = [
      ToStringCollision.toString(3),
      Std.string(ApplyCollision.apply(2, 5, 7)),
      CompatibleToString.toString(),
      Std.string(CompatibleApply.apply(8, 5)),
      CallCollision.call("value"),
      BindCollision.bind("left", "right"),
      Std.string(NativeApplyCollision.combine(3, 4, 5)),
      Std.string(NativeApplyEscape.apply(4, 5, 6)),
      PropertyCollision.call,
      Std.string(InheritedBase.apply(4, 6, 2))
    ];
    NodeConsole.log(reflected.concat(resolved).concat(statics).join("|"));
  }

  static function reflectedName(value: Dynamic): String {
    return Type.getClassName(Type.getClass(value));
  }

  static function resolvedName(name: String): String {
    return Type.getClassName(Type.resolveClass(name));
  }
}

private class ToStringCollision {
  public function new() {}

  public static function toString(value: Int): String {
    return 'toString:$value';
  }
}

private class ApplyCollision {
  public function new() {}

  public static function apply(left: Int, middle: Int, right: Int): Int {
    return left + middle + right;
  }
}

private class CompatibleToString {
  public function new() {}

  public static function toString(): String {
    return "compatible-toString";
  }
}

private class CompatibleApply {
  public function new() {}

  public static function apply(left: Int, right: Int): Int {
    return left - right;
  }
}

private class CallCollision {
  public function new() {}

  public static function call(value: String): String {
    return 'call:$value';
  }
}

private class BindCollision {
  public function new() {}

  public static function bind(left: String, right: String): String {
    return '$left+$right';
  }
}

private class NativeApplyCollision {
  public function new() {}

  /**
   * The Haxe name is harmless, but the emitted TypeScript name collides.
   */
  @:native("apply")
  public static function combine(left: Int, middle: Int, right: Int): Int {
    return left + middle + right;
  }
}

private class NativeApplyEscape {
  public function new() {}

  /**
   * The Haxe name looks conflicting, but the emitted name is harmless.
   */
  @:native("domainApply")
  public static function apply(left: Int, middle: Int, right: Int): Int {
    return left * middle - right;
  }
}

private class PropertyCollision {
  public function new() {}

  /**
   * JavaScript Function.call is callable, so a string property is incompatible.
   */
  public static final call: String = "property-call";
}

private class InheritedBase {
  public function new() {}

  public static function apply(left: Int, middle: Int, right: Int): Int {
    return left * middle * right;
  }
}

private class InheritedCollision extends InheritedBase {
  public function new() {
    super();
  }
}

private class OrdinaryClass {
  public function new() {}

  public static function describe(value: String): String {
    return 'ordinary:$value';
  }
}

private interface Marker {}

private class ImplementsMarker implements Marker {
  public function new() {}
}
