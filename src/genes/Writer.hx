package genes;

import haxe.io.Encoding;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import genes.util.Timer.timer;

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
    #if (debug || js_source_map)
    for (char in data)
      if (char == '\n'.code) {
        line++;
        column = 0;
      } else {
        column++;
      }
    #end
  }

  public function isEmpty() {
    return line == 1 && column == 0;
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

  public static function bufferedFileWriter(file: String) {
    var buffer = new StringBuf();
    return new Writer((data : String) -> {
      buffer.add(data);
    }, () -> {
        if (buffer.length == 0)
          return;
        final dir = Path.directory(file);
        if (!FileSystem.exists(dir))
          FileSystem.createDirectory(dir);
        final endTimer = timer('writeToFile');
        final output = buffer.toString();
        #if genes.unchanged_no_rewrite
        try
          if (FileSystem.exists(file) && output == File.getContent(file))
            return endTimer()
        catch (e:Dynamic) {}
        #end
        File.saveContent(file, output);
        endTimer();
      });
  }
}
