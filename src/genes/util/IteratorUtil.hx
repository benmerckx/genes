package genes.util;

class IteratorUtil {
  public static function join<T>(input: Iterable<T>, joiner: () -> Void)
    return joinIt(input.iterator(), joiner);

  public static function joinIt<T>(iterator: Iterator<T>,
      joiner: () -> Void): Iterator<T> {
    var started = false;
    return {
      hasNext: iterator.hasNext,
      next: () -> {
        if (!started)
          started = true;
        else
          joiner();
        return iterator.next();
      }
    }
  }
}
