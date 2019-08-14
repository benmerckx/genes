package tests;

import tink.unit.*;
import tink.unit.Assert.*;
import tink.testrunner.*;

class Run {
    static function main() {
        Runner.run(TestBatch.make([
            new Test(),
        ])).handle(Runner.exit);
    }
}

class Test {
    public function new() {}

    public function test()
        return assert(true);
}