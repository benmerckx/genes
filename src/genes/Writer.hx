package genes;

import haxe.io.Encoding;
import sys.io.File;

using StringTools;

class Writer {
  final writer: (data: String) -> Void;

  public final close: () -> Void;
  public var line(default, null): Int = 0;
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
    final input = File.write(file);
    return
      new Writer((data : String) -> input.writeString(data, Encoding.UTF8), input.close);
  }
}
