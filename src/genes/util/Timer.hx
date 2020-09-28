package genes.util;

class Timer {
  public static function timer(id: String) {
    #if (haxe_ver >= 4.1)
    return haxe.macro.Context.timer(id);
    #else
    return function() {}
    #end
  }
}
