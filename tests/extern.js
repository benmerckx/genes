import {ExternalClass} from '../bin/tests/ExternalClass'

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