package genes.util;

class IteratorAdapter {
  public static function create<T>(from: js.lib.Iterator<T>): Iterator<T> {
    var value: T;
    var done: Bool;
    function queue() {
      var data = from.next();
      value = data.value;
      done = data.done;
    }
    return {
      hasNext: () -> {
        if (done == null)
          queue();
        return !done;
      },
      next: () -> {
        if (done == null)
          queue();
        var pending = value;
        queue();
        return pending;
      }
    }
  }
}
