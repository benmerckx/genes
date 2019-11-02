# genes

Generates ES6 modules and Typescript definitions from Haxe modules.

Requires Haxe 4, status: experimental

## Usage

Install the library and add `-lib genes` to your hxml.

Options:

- add `-D dts` to generate Typescript definition files
- use `-debug` or `-D js-source-map` to generate source maps

## Dynamic imports

```haxe
import genes.Genes.dynamicImport;
import my.module.MyClass;
// ...
dynamicImport(MyClass -> new MyClass()).then(trace);
```

Translates to:

```js
import('./my/module/MyClass')
  .then(({MyClass}) => new MyClass())
  .then(console.log)
```


## Todo

- [ ] Extending extern classes
- [ ] Most `Type` reflection (resolveClass/resolveEnum/...)
- [ ] Improve `$hxEnums` declaration
- [ ] Performance

## Alternatives

- Split output with require calls: [hxgenjs](https://github.com/kevinresol/hxgenjs)
- Typescript definition generation: [hxtsdgen](https://github.com/nadako/hxtsdgen)
