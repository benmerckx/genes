package genes.util;

class Timer {
  public static function timer(id: String) {
    #if macro_times
    return haxe.macro.Context.timer(id);
    #else
    return () -> {}
    #end
  }
}
