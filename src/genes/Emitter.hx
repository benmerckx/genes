package genes;

import genes.SourceMapGenerator;

class Emitter {
  final ctx: genes.Context;
  final writer: Writer;
  final sourceMap: SourceMapGenerator;

  var lastPos = SourcePosition.EMPTY;

  public function new(ctx: Context, writer: Writer,
      sourceMap: SourceMapGenerator) {
    this.ctx = ctx;
    this.writer = writer;
    this.sourceMap = sourceMap;
  }

  function emitPos(pos: SourcePosition) {
    switch pos {
      case null:
      case {column: column, line: line, file: file}:
        if (lastPos.column != column || lastPos.line != line)
          sourceMap.addMapping(pos, {
            line: writer.line,
            column: writer.column,
            file: null
          });
        lastPos = pos;
    }
  }

  inline function write(data: String) {
    writer.write(data);
  }
}
