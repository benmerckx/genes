package tests;

import tink.unit.Assert.*;
import tests.util.ModuleSource.sourceCode;

/** Class comment */
class TestComments {
  final source = sourceCode();

  public function new() {}

  /**  Method comment */
  public function test()
    return assert(source.contains('Method comment'));
}
