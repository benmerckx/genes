package tests;

import tink.unit.Assert.*;

/** Class comment */
class TestComments {
  public function new() {}

  /**  Method comment */
  public function test() // Todo: somehow parse source code and check for comment here?
    return assert(true);
}
