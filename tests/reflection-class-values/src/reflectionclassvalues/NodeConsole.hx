package reflectionclassvalues;

/**
 * Writes through JavaScript's built-in console object.
 *
 * Why `@:native("console")` instead of `@:jsRequire`:
 * Genes TypeScript, Genes classic JavaScript, and Haxe's standard JavaScript
 * target all provide the global `console` value. Naming that existing value
 * keeps the fixture package-neutral and avoids introducing a module import
 * that the standard Haxe JavaScript emitter does not generate here.
 */
@:native("console")
extern class NodeConsole {
  static function log(value: String): Void;
}
