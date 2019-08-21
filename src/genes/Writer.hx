package genes;

import haxe.io.Encoding;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;

using StringTools;

class Writer {
  final writer: (data: String) -> Void;

  public final close: () -> Void;
  public var line(default, null): Int = 1;
  public var column(default, null): Int = 0;

  public function new(writer, close) {
    this.writer = writer;
    this.close = close;
  }

  public function write(data: String) {
    writer(data);
    for (char in data)
      if (char == '\n'.code) {
        line++;
        column = 0;
      } else {
        column++;
      }
  }

  public static function fileWriter(file: String) {
    var input;
    return new Writer((data : String) -> {
      if (input == null) {
        final dir = Path.directory(file);
        if (!FileSystem.exists(dir))
          FileSystem.createDirectory(dir);
        input = File.write(file);
      }
      input.writeString(data, Encoding.UTF8);
    }, () -> if (input != null) input.close());
  }
}
