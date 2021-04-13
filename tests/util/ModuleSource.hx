package tests.util;

using StringTools;

class ModuleSource {
  public inline static function sourceCode(typings = false) {
    final url: String = js.Syntax.code('import.meta.url');
    // Windows can't deal with a path like /C:/dir so we strip
    // one more character off the start
    final isWindows = Sys.systemName().toLowerCase().startsWith('win');
    final path = url.substr('file://'.length + (isWindows ? 1 : 0));
    return sys.io.File.getContent(if (typings) path.replace('.js',
      '.d.ts') else path);
  }
}
