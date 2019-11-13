package genes.util;

class Timer {
  public static function timer(id: String) {
    #if (macro && macro_times)
    return haxe.macro.Context.timer(id);
    #else
    return function() {}
    #end
  }
}
