package genes.util;

import helder.Set;

class GlobalTypes {
  // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects
  static final LIST = new Set([
    'Infinity', 'NaN', 'Object', 'Function', 'Boolean', 'Symbol', 'Error',
    'AggregateError ', 'EvalError', 'InternalError', 'RangeError',
    'ReferenceError', 'SyntaxError', 'TypeError', 'URIError', 'Number',
    'BigInt', 'Math', 'Date', 'String', 'RegExp', 'Array', 'Int8Array',
    'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array',
    'Int32Array', 'Uint32Array', 'Float32Array', 'Float64Array',
    'BigInt64Array', 'BigUint64Array', 'Map', 'Set', 'WeakMap', 'WeakSet',
    'ArrayBuffer', 'SharedArrayBuffer', 'Atomics', 'DataView', 'JSON',
    'Promise', 'Generator', 'GeneratorFunction', 'AsyncFunction',
    'AsyncGenerator', 'AsyncGeneratorFunction', 'Reflect', 'Proxy', 'Intl',
    'WebAssembly',
  ]);

  public static inline function exists(v)
    return LIST.exists(v);
}
