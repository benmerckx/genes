import {ExternalClass} from '../bin/tests/ExternalClass.js'

const DummyClass = function (num) {
  this.test = num
}

export default DummyClass

export class ExtendHaxeClass extends ExternalClass {
  test() {
    return super.test() + '!'
  }
}

export const Dropdown = function() {}
Dropdown.Header = DummyClass
Dropdown.Menu = DummyClass

export class MyClass {
  constructor() {}
  toString() {
    return 'baz'
  }
}
