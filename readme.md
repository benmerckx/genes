# genes

An attempt at generating seperate ES6 modules and Typescript definitions from Haxe modules.

## Usage

Install the library and add `-lib genes` to your hxml.

Options:

- add `-D dts` to generate Typescript definition files
- use `-debug` or `-D js-source-map` to generate source maps

## Limitations

These will currently fail at runtime:

- No `this` access before `super` call in your constructor (unless someone feels like porting [this](https://github.com/HaxeFoundation/haxe/blob/ee31280c11d2302a7f6ebb9a7d09067070e59dc3/src/filters/ES6Ctors.ml#L69))
- No circular static inits or inheritance

## Alternatives

- Split output with require calls (not bound to above limitations): [hxgenjs](https://github.com/kevinresol/hxgenjs)
- Typescript definition generation: [hxtsdgen](https://github.com/nadako/hxtsdgen)