package tests;

import tink.unit.*;
import tink.unit.Assert.*;
import tink.testrunner.*;

class Run {
  static function main() {
    Runner.run(TestBatch.make([new TestRequire(), new TestImportAlias(), new TestMap(), new TestIterators()]))
      .handle(Runner.exit);
  }
}
