package tests;

import tink.testrunner.Reporter.AnsiFormatter;
import tink.testrunner.Reporter.BasicReporter;
import tink.unit.TestBatch;
import tink.testrunner.Runner;

class Run {
  static function main() {
    Runner.run(TestBatch.make([
      // These test specific genes features that make no sense in default
      // haxe generated js
      #if !genes.disable
      new TestRequire(), new TestExtendExtern(), new TestReactComponent(),
      new TestImportModule(), new TestCycle(), new TestCycle2(),
      #end
      new TestBind(),
      new TestImportAlias(),
      new TestMap(),
      new TestIterators(),
      new TestComments(),
      new TestTypedef(),
      new TestEnum(),
      new TestRegisterAlias(),
      new TestRecursiveTypedef(),
      new TestFunction(),
      new TestType(),
      new TestBoot(),
      new TestReservedClassNames(),
      new TestSemicolons(),
      new TestTypesAsValues(),
      new TestGetterSetter(),
      new TestSyntax(),
      #if (haxe_ver >= 4.2) new TestModuleStatics(), new TestRest()
      #end
    ]), new BasicReporter(new AnsiFormatter())).handle(Runner.exit);
  }
}
