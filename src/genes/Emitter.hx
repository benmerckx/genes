package genes;

import genes.SourceMapGenerator;
import haxe.io.Path;
import genes.util.Timer.timer;

class Emitter {
  final ctx: genes.Context;
  final writer: Writer;
  final sourceMap: SourceMapGenerator;

  var lastPos = SourcePosition.EMPTY;
  var lastWriterLine = -1;

  public function new(ctx: Context, writer: Writer,
      ?sourceMap: SourceMapGenerator) {
    this.ctx = ctx;
    this.writer = writer;
    this.sourceMap = if (sourceMap == null) new SourceMapGenerator() else
      sourceMap;
  }

  public function emitPos(pos: SourcePosition) {
    #if (debug || js_source_map)
    switch pos {
      case null | {file: '?'}:
      case {column: column, line: line, file: file}:
        if (lastPos.column != column || lastPos.line != line
          || lastWriterLine != writer.line)
          sourceMap.addMapping(pos, {
            line: writer.line,
            column: writer.column,
            file: null
          });
        lastPos = pos;
        lastWriterLine = writer.line;
    }
    #end
  }

  public function write(data: String) {
    writer.write(data);
  }

  public function emitSourceMap(path: String, withSources = false) {
    if (writer.isEmpty())
      return;
    final endTimer = timer('emitSourceMap');
    final output = Path.withoutDirectory(path);
    write('\n//# sourceMappingURL=$output');
    sourceMap.write(path, withSources);
    endTimer();
  }

  public function finish() {
    writer.close();
  }
}
