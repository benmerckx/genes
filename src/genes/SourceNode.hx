package genes;

import haxe.macro.Type;
import haxe.macro.Expr.Position;
import haxe.display.Position.Location;
import haxe.macro.PositionTools.toLocation;

@:structInit
private class SourcePositionData {
  public final line: Int;
  public final column: Int;
  public final file: String;
}

@:forward
abstract SourcePosition(SourcePositionData) from SourcePositionData {
  @:from static function fromTypedExpr(expr: TypedExpr)
    return fromPos(expr.pos);

  @:from static function fromPos(pos: Position)
    return fromLocation(toLocation(pos));

  @:from static function fromLocation(location: Location): SourcePosition
    return ({
      line: location.range.start.line,
      column: location.range.start.character,
      file: location.file
    } : SourcePositionData);
}

private enum SourceNodeChunk {
  ReadContext(create: (ctx: Context) -> SourceNode);
  WriteContext(writer: (ctx: Context) -> Context, chunks: SourceNode);
  Node(position: SourcePosition, node: Array<SourceNode>);
  Code(value: String);
  Multiple(chunks: Array<SourceNode>);
}

typedef Context = {
  var ?idCounter: Int;
  final ?tabs: String;
  final ?inValue: Int;
  final ?inLoop: Bool;
  final ?expr: (expr: TypedExpr) -> String;
  final ?value: (expr: TypedExpr) -> String;
  final ?hasFeature: (feature: String) -> Bool;
  final ?addFeature: (feature: String) -> Void;
  final ?typeAccessor: (type: ModuleType) -> String;
}

private typedef C = SourceNode;

@:forward
abstract SourceNode(SourceNodeChunk) from SourceNodeChunk {
  @:from public static function read(create: (ctx: Context) -> SourceNode): SourceNode
    return ReadContext(create);

  public static function write(writer: (ctx: Context) -> Context, node: SourceNode): SourceNode
    return WriteContext(writer, node);

  @:from static function fromString(value: String): SourceNode
    return Code(value);

  @:from static function fromMultiple(chunks: Array<SourceNode>): SourceNode
    return Multiple(chunks);

  static function createContext(): Context
    return {
      idCounter: 0,
      tabs: '',
      inValue: 0,
      inLoop: false,
      hasFeature: feature -> false,
      addFeature: function (feature) {},
      expr: (e: TypedExpr) -> '',
      value: (e: TypedExpr) -> '',
      typeAccessor: (type: ModuleType) -> 
        switch type {
          case TClassDecl(_.get() => {pack: pack, module: module, name: name}) |
          TEnumDecl(_.get() => {pack: pack, module: module, name: name}) |
          TTypeDecl(_.get() => {pack: pack, module: module, name: name}) |
          TAbstract(_.get() => {pack: pack, module: module, name: name}):
            module;
        }
    }

  static function set<T: {}>(object: T, changes: {}): T {
    final res = Reflect.copy(object);
    for (key => value in (cast changes: haxe.DynamicAccess<Dynamic>))
      Reflect.setField(res, key, value);
    return res;
  }

  public function toString(?ctx: Context) {
    final context = switch ctx {
      case null: createContext();
      case c: set(createContext(), c);
    }
    return switch this {
      case ReadContext(create): create(context).toString(context);
      case WriteContext(writer, n):
        n.toString(set(context, writer(context)));
      case Code(value): value;
      case Node(_, chunks) | Multiple(chunks):
        chunks.map(c -> c.toString(context)).join('');
    }
  }

  public static final join = (chunks: Array<SourceNode>, by: SourceNode) -> {
    final res = [];
    for (i in 0...chunks.length) {
      res.push(chunks[i]);
      if (i != chunks.length - 1)
        res.push(by);
    }
    return (res : SourceNode);
  }

  public static final node = (position: SourcePosition, ?a: C, ?b: C, ?c: C, ?d
    : C, ?e: C, ?f: C, ?g: C, ?h: C, ?i: C, ?j: C, ?k: C, ?l: C,
    ?m: C) ->
    Node(position, [a, b, c, d, e, f, g, h, i, j, k, l, m].filter(c -> c != null));
}
