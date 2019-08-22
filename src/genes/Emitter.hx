package genes;

import genes.SourceMapGenerator;
import haxe.io.Path;

class Emitter {
  final ctx: genes.Context;
  final writer: Writer;
  final sourceMap: SourceMapGenerator;

  var lastPos = SourcePosition.EMPTY;

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
        if (lastPos.column != column || lastPos.line != line)
          sourceMap.addMapping(pos, {
            line: writer.line,
            column: writer.column,
            file: null
          });
        lastPos = pos;
    }
    #end
  }

  public function write(data: String) {
    writer.write(data);
  }

  public function emitSourceMap(path: String, withSources = false) {
    if (writer.isEmpty())
      return;
    final output = Path.withoutDirectory(path);
    write('\n//# sourceMappingURL=$output');
    sourceMap.write(path, withSources);
  }

  public function finish() {
    writer.close();
  }
}
