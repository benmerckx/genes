package tests;

@:expose typedef Hello = String;

@:expose
class RootExport {
  static final works = 'yep';
}

@:expose enum RootExportEnum {
  Works;
}

#if (haxe_ver >= 4.2)
// TODO expose these too
@:expose function a() {}
@:expose final b = 'c';
#end

@:asserts
class TestExpose {
  public function new() {}

  public function testExpose() {
    final source = sys.io.File.getContent('bin/tests.js');
    asserts.assert(source.indexOf('export {RootExport} from "./tests/TestExpose.js"') > -1);
    asserts.assert(source.indexOf('export {RootExportEnum} from "./tests/TestExpose.js"') > -1);
    final source = sys.io.File.getContent('bin/tests.d.ts');
    asserts.assert(source.indexOf('export {Hello} from "./tests/TestExpose"') > -1);
    return asserts.done();
  }
}
