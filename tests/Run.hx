package tests;

import tink.unit.TestBatch;
import tink.testrunner.Runner;

class Run {
  static function main() {
    Runner.run(TestBatch.make([
      new TestBind(), new TestRequire(), new TestImportAlias(), new TestMap(),
      new TestIterators(), new TestComments(), new TestCycle(),
      new TestCycle2(), new TestTypedef(), new TestEnum(),
      new TestImportModule(), new TestRegisterAlias(),
      new TestRecursiveTypedef(), new TestExtendExtern(), new TestFunction(),
      new TestType(), new TestBoot(), new TestReservedClassNames(),
      new TestReactComponent()])).handle(Runner.exit);
  }
}
