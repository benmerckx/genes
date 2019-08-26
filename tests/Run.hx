package tests;

import tink.unit.*;
import tink.unit.Assert.*;
import tink.testrunner.*;

class Run {
  static function main() {
    Runner.run(TestBatch.make([
      new TestBind(),
      new TestRequire(),
      new TestImportAlias(),
      new TestMap(),
      new TestIterators(),
      // TS
      new TestTypedef(),
      new TestEnum()
    ])).handle(Runner.exit);
  }
}
