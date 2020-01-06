import {ExternalClass} from '../bin/tests/ExternalClass'

export default function (num) {
  this.test = num
}

export class ExtendHaxeClass extends ExternalClass {
  test() {
    return super.test() + '!'
  }
}