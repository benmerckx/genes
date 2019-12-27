package genes;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.JSGenApi;
import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.io.Path;
import genes.es.ModuleEmitter;
import genes.dts.DefinitionEmitter;
import genes.util.Timer.timer;
import genes.util.TypeUtil;

using Lambda;
using StringTools;

class Generator {
  #if macro
  public static function use()
    Compiler.setCustomJSGenerator(api -> new Generation(api).generate());
  #end
}
