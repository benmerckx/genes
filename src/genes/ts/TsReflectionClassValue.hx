package genes.ts;

import genes.EmittedMemberName;
import haxe.macro.Context;
import haxe.macro.Type;

/**
 * Proves when a generated class constructor needs an identity bridge to
 * TypeScript's structural `Function` interface at Haxe reflection boundaries.
 *
 * Why
 * ----
 * JavaScript implements every emitted class constructor as a Function object.
 * Haxe may also declare an unrelated static method whose emitted name belongs
 * to JavaScript's `Function` surface:
 *
 * ```haxe
 * class Calculator {
 *   public static function apply(a:Int, b:Int, c:Int):Int {
 *     return a + b + c;
 *   }
 * }
 * ```
 *
 * TypeScript compares properties structurally. It therefore compares that
 * three-argument Haxe method with `Function.apply(thisArg, args?)` and rejects
 * `typeof Calculator` as `Function`, even though the runtime class constructor
 * is still a genuine Function object.
 *
 * What
 * ----
 * This relation recognizes the two reviewed incompatibilities exposed by real
 * Haxe libraries:
 *
 * - `toString` cannot require arguments and must return the core Haxe `String`
 *   projection expected by JavaScript's zero-argument method;
 * - `apply` cannot require more than the two arguments offered by
 *   `Function.apply`.
 *
 * A function-valued `call` or `bind` remains compatible because TypeScript's
 * declarations expose rest arguments for those methods. A non-function field
 * with one of these callable names is incompatible. The check follows the
 * superclass chain because JavaScript and TypeScript class values inherit
 * static members.
 *
 * How
 * ---
 * The TypeScript emitter consults this typed, output-name-aware proof only
 * while emitting `__interfaces__`, `__super__`, `__class__`, or runtime class
 * registration. It then emits `Register.unsafeCast<Function>(ClassValue)`, a
 * runtime identity operation. Ordinary construction, static calls, imports,
 * declarations, and classic JavaScript never consume this proof.
 *
 * This is deliberately not a general TypeScript assignability engine. Unknown
 * or future Function-member collisions stay visible to strict TypeScript until
 * they receive their own typed evidence and positive/negative fixtures.
 */
class TsReflectionClassValue {
  public static function needsFunctionBridge(owner: ClassType): Bool {
    return classOrParentConflicts(owner, 0);
  }

  static function classOrParentConflicts(owner: ClassType, depth: Int): Bool {
    // Haxe rejects cyclic class inheritance. If an unexpectedly deep compiler
    // structure reaches this guard, the safe reflection-boundary fallback is
    // still to preserve the JavaScript runtime fact that the class is a
    // Function. Returning true avoids silently overlooking a parent conflict.
    if (depth > 128)
      return true;

    for (field in owner.statics.get())
      if (fieldConflicts(owner, field))
        return true;

    return switch owner.superClass {
      case null:
        false;
      case {t: parent}:
        classOrParentConflicts(parent.get(), depth + 1);
    }
  }

  static function fieldConflicts(owner: ClassType,
      field: ClassField): Bool {
    final emittedName = EmittedMemberName.classStaticField(owner, field);
    return switch Context.follow(field.type) {
      case TFun(arguments, result):
        switch emittedName {
          case 'toString':
            requiredArity(arguments) > 0 || !isCoreString(result);
          case 'apply':
            requiredArity(arguments) > 2;
          case 'call' | 'bind':
            false;
          default:
            false;
        }
      default:
        switch emittedName {
          case 'toString' | 'apply' | 'call' | 'bind':
            true;
          default:
            false;
        }
    }
  }

  /**
   * Returns the minimum positional arity emitted by TypeScript.
   *
   * A Haxe optional argument before a later required argument cannot use `?`
   * syntax in TypeScript, so every position through the final required
   * argument remains part of the callable's minimum arity.
   */
  static function requiredArity(arguments: Array<{
      name: String,
      opt: Bool,
      t: Type
    }>): Int {
    var required = 0;
    for (index in 0...arguments.length)
      if (!arguments[index].opt)
        required = index + 1;
    return required;
  }

  static function isCoreString(type: Type): Bool {
    return switch Context.follow(type) {
      case TInst(reference, _):
        final value = reference.get();
        value.pack.length == 0
          && value.module == 'String'
          && value.name == 'String';
      case TDynamic(_):
        true;
      default:
        false;
    }
  }
}
