package genes;

import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.macro.Expr.Position;
import haxe.display.Position.Location;
import haxe.macro.PositionTools.toLocation;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;
import haxe.Json;
import genes.util.PathUtil;

@:structInit
class SourcePositionData {
  public final line: Int;
  public final column: Int;
  public final file: Null<String>;
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
      column: location.range.start.character - 1,
      file: location.file.toString()
    } : SourcePositionData);

  public static final EMPTY: SourcePosition = ({
    line: 1,
    column: 0,
    file: null
  } : SourcePositionData);
}

class SourceMapGenerator {
  static final chars = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd',
    'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's',
    't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', '+', '/'
  ];

  final sources: Array<String> = [];
  var mappings = '';
  var previousGeneratedColumn = 0;
  var previousGeneratedLine = 1;
  var previousOriginalColumn = 0;
  var previousOriginalLine = 0;
  var previousSource = 0;

  public function new() {}

  static function toVlq(number: Int)
    return (number < 0) ? ((-1 * number) << 1) + 1 : (number << 1);

  function base64Vlq(number: Int) {
    var vlq = toVlq(number);
    do {
      final shift = 5;
      final base = 1 << shift;
      final mask = base - 1;
      final continuationBit = base;
      final digit = vlq & mask;
      final next = vlq >> shift;
      final mapping = chars[
        if (next > 0)
          digit | continuationBit
        else
          digit
      ];
      mappings += mapping;
      vlq = next;
    } while (vlq > 0);
  }

  public function addMapping(original: SourcePosition,
      generated: SourcePositionData) {
    final source = switch sources.indexOf(original.file) {
      case -1: sources.push(original.file) - 1;
      case v: v;
    }
    if (generated.line != previousGeneratedLine) {
      previousGeneratedColumn = 0;
      while (generated.line != previousGeneratedLine) {
        mappings += ";";
        previousGeneratedLine++;
      }
    } else if (mappings.length > 0) {
      mappings += ",";
    }

    base64Vlq(generated.column - previousGeneratedColumn);
    base64Vlq(source - previousSource);
    base64Vlq(original.line - 1 - previousOriginalLine);
    base64Vlq(original.column - previousOriginalColumn);

    previousGeneratedColumn = generated.column;
    previousOriginalLine = original.line - 1;
    previousOriginalColumn = original.column;
    previousSource = source;
  }

  public function toJSON(path: String, withSources: Bool) {
    final map: Dynamic = {
      version: 3,
      names: [],
      file: Path.withoutDirectory(path),
      sourceRoot: "",
      sources: sources.map(source -> if (source == '?') null else PathUtil.relative(path, source)),
      mappings: mappings
    }
    #if source_map_content
    if (withSources)
      map.sourcesContent = sources.map(source -> switch source {
        case null | '?': null;
        case file: File.getContent(file);
      });
    #end
    return map;
  }

  public function write(path: String, withSources: Bool) {
    final dir = Path.directory(path);
    if (!FileSystem.exists(dir))
      FileSystem.createDirectory(dir);
    File.saveContent(path, Json.stringify(toJSON(path, withSources)));
  }
}
