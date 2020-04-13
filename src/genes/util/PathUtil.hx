package genes.util;

import sys.FileSystem;
import haxe.io.Path;

class PathUtil {
  public static function relative(from: String, to: String) {
    from = Path.normalize(FileSystem.absolutePath(from));
    to = Path.normalize(FileSystem.absolutePath(to));
    final fromParts = from.split('/').filter(v -> v != '');
    final toParts = to.split('/').filter(v -> v != '');
    // Substract one since don't want to compare the file part
    final length: Int = cast Math.min(fromParts.length, toParts.length) - 1;
    var samePartsLength = length;
    for (i in 0...length)
      if (fromParts[i] != toParts[i]) {
        samePartsLength = i;
        break;
      }
    final to = [
      for (i in samePartsLength...fromParts.length - 1)
        '..'
    ].concat(toParts.slice(samePartsLength)).join('/');
    return if (to.charAt(0) != '.') './' + to else to;
  }
}
