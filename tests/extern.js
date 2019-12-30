import {ExternalClass} from '../bin/tests/ExternalClass'

export default class {
  constructor() {this.test = 1}
}

export class ExtendHaxeClass extends ExternalClass {
  test() {
    return super.test() + '!'
  }
}