package genes;

import haxe.macro.Expr.Position;

class Emitter {
  final ctx: genes.Context;
  final writer: Writer;
  final sourceMap: SourceMapGenerator;

  public function new(ctx: Context, writer: Writer, sourceMap: SourceMapGenerator) {
    this.ctx = ctx;
    this.writer = writer;
    this.sourceMap = sourceMap;
  }

  function emitPos(pos: Position) {

  }

  inline function write(data: String) {
    writer.write(data);
  }
}
