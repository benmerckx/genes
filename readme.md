# genes

Generates ES6 modules and Typescript definitions from Haxe modules.

Requires Haxe nightly (e6ecc54+)

## Usage

Install the library and add `-lib genes` to your hxml.

Options:

- add `-D dts` to generate Typescript definition files
- use `-debug` or `-D js-source-map` to generate source maps

## Limitations

Circular statics and inheritance are currently solved by:

- Making each static lazy
- Deferring resolving the inheritance chain until usage

In the future I'd like to make this more configurable by providing
these options as defines:

- Opt-out completely
- Detect when needed by dependency graph (adds compile time)

## Alternatives

- Split output with require calls (not bound to above limitations): [hxgenjs](https://github.com/kevinresol/hxgenjs)
- Typescript definition generation: [hxtsdgen](https://github.com/nadako/hxtsdgen)