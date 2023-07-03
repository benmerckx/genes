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
      new TestAbstract(), new TestRequire(), new TestExtendExtern(),
      new TestReactComponent(), new TestImportModule(), new TestCycle(),
      new TestCycle2(), new TestComments(), new TestTsTypes(),
      new TestTsGenerics(), new TestTypeAlias(), new TestSyntax(),
      #end
      new TestAsterisk(),
      new TestBind(),
      new TestImportAlias(),
      new TestMap(),
      new TestIterators(),
      new TestTypedef(),
      new TestEnum(),
      new TestRegisterAlias(),
      new TestRecursiveTypedef(),
      new TestFunction(),
      new TestType(),
      new TestBoot(),
      new TestReservedClassNames(),
      new TestSemicolons(),
      new TestTypeNameClash(),
      new TestTypesAsValues(),
      new TestGetterSetter(),
      new TestExpose(),
      new TestStatics(),
      new TestDoWhile(),
      #if (haxe_ver >= 4.1)
      new TestException(),
      #end
      #if (haxe_ver >= 4.2)
      new TestModuleStatics(), new TestRest(), new TestAbstractClass(),
      #end
      #if (haxe_ver >= 4.3)
      new TestOperators()
      #end
    ]), new BasicReporter(new AnsiFormatter())).handle(Runner.exit);
  }
}
