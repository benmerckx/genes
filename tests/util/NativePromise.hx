package tests.util;

import tink.core.Promise;
import js.lib.Promise as JsPromise;

abstract NativePromise<T>(JsPromise<T>) from JsPromise<T> {
  @:from static function ofPromise<T>(promise: Promise<T>): NativePromise<T>
    return promise.toJsPromise();
}
