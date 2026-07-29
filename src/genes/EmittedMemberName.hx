package genes;

import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import genes.Module.Field;
import genes.util.TypeUtil;

/**
 * Resolves observable class-member spellings before target printing.
 *
 * Why: module-function validation, the descriptor seed, its direct assignment,
 * and ordinary class emission must agree on the same property key. Recomputing
 * `@:native` and Haxe's generated `name`/`length` escape in each printer could
 * validate one property and install another.
 *
 * What/How: this is the existing Genes static-member rule expressed once as a
 * target-neutral semantic fact. It does not sanitize or make a requested name
 * unique; callers either print the returned member syntax or reject a shape
 * their output contract cannot represent.
 */
class EmittedMemberName {
  public static function staticField(owner: ClassType, field: Field): String {
    return resolveStaticField(owner, field.name, field.meta);
  }

  /**
   * Resolves the emitted spelling directly from a compiler `ClassField`.
   *
   * Why: some TypeScript-only semantic checks inspect another class's typed
   * static surface rather than the current module's projected `Module.Field`.
   * Those checks must observe the same `@:native` and generated `name`/`length`
   * escaping as the class printer or they can reason about a property that is
   * never emitted.
   *
   * What/How: both field representations delegate to the same resolver. This
   * method changes no field identity and allocates no output name.
   */
  public static function classStaticField(owner: ClassType,
      field: ClassField): String {
    return resolveStaticField(owner, field.name, field.meta);
  }

  static function resolveStaticField(owner: ClassType, name: String,
      meta: Null<haxe.macro.Type.MetaAccess>): String {
    final nativeName = TypeUtil.nativeName(meta);
    if (nativeName != null)
      return nativeName;
    return switch [owner.isExtern, name] {
      case [false, name = 'name' | 'length']: '$' + name;
      default: name;
    };
  }
}
