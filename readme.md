# genes

[![CI](https://github.com/benmerckx/genes/workflows/CI/badge.svg)](https://github.com/benmerckx/genes/actions)

Generates split ES6 modules and Typescript definitions from Haxe modules.

Requires Haxe 4+

## Usage

<pre><a href="https://github.com/lix-pm/lix.client">lix</a> +lib genes</pre>

Install the library and add `-lib genes` to your hxml.

### Defines

| Define                                                                                                                                   | Description                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-D dts`                                                                                                                                 | generate Typescript definition files                                                                                                                                                                                           |
| [`-debug`](https://haxe.org/manual/debugging-source-map.html) or [`-D js-source-map`](https://haxe.org/manual/debugging-source-map.html) | generate source maps                                                                                                                                                                                                           |
| [`-D source_map_content`](https://haxe.org/manual/debugging-source-map-javascript.html)                                                  | include source map contents                                                                                                                                                                                                    |
| `-D genes.unchanged_no_rewrite`                                                                                                          | don't write output files if there's no change (compares output to file on disk)                                                                                                                                                |
| `-D genes.extern_init_warning`                                                                                                           | display a warning wherever an extern `__init__` is used as these are not generated by genes                                                                                                                                    |
| `-D genes.disable`                                                                                                                       | disable genes completely (eg. to compare results to default haxe js generator)                                                                                                                                                 |
| `-D genes.no_extension`                                                                                                                  | do not use the `.js` extension in import paths                                                                                                                                                                                 |
| `-D genes.disable_native_accessors`                                                                                                      | do not generate native getter/setters for properties                                                                                                                                                                           |
| `-D genes.banner`                                                                                                                        | string to be inserted at the beginning of every generated .js file                                                                                                                                                             |
| `-D genes.dts_banner`                                                                                                                    | string to be inserted at the beginning of every generated .d.ts file                                                                                                                                                           |
| `-D genes.enum_discriminator`                                                                                                            | emit extra field in enum instance with value equal to the enum constructor name, useful for native js code to consume the enum instead of relying on the default \_hx_index field. Example `-D genes.enum_discriminator=_kind` |

### Metadata

| Metadata                         | Description                                                                                                 |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `@:genes.disableNativeAccessors` | on class level or field level to disable generation of native getter/setters for properties                 |
| `@:genes.type('MyType')`         | overwrite Typescript type in declarations (use on: class, class properties, typedef, type parameters, ....) |
| `@:genes.returnType('MyType')`   | overwrite Typescript return type in declarations (use on functions)                                         |

## Dynamic imports

```haxe
import genes.Genes.dynamicImport;
import my.module.A;
import my.module.B;
import my.module.C;
// ...
dynamicImport(A -> new A()).then(trace);

dynamicImport((B, C) -> [new B(), new C()]).then(trace);
```

Roughly translates to:

```js
import("./my/module/A")
	.then(({ A }) => new A())
	.then(console.log);

Promise.all([import("./my/module/B"), import("./my/module/C")])
	.then((modules) => [new modules[0].B(), new modules[1].C()])
	.then(console.log);
```

Genes expects a function declaration expression (`EFunction`) as the sole argument of `dynamicImport` and it will do 2 things:

1. For each argument, take the argument name (e.g. "MyClass") and resolve it as a type in the current context, taking Haxe `import` statements into account. This is for preparing the relative path of the target files (e.g. `'../../MyClass.js'`).
2. Type the function body in the current context, ignoring the fact that it is a function body. Thus in the example the scope of `A` is not the function argument but in current context i.e. the actual type `class A {...}`. The return type is then applied as the type parameter of `js.lib.Promise`. This is for hinting the return type of the `dynamicImport(...)` call so that the compiler can do its typing job properly.

## Upstream issues

- Performance could be much improved if we could use the compiler to output code.
  Haxe exposes methods to do so, but without a way to generate source maps for them.

  [HaxeFoundation/haxe#8625](https://github.com/HaxeFoundation/haxe/issues/8625)

- Typescript definitions are pretty much complete. In some cases though there will
  be references to non-existing types. Haxe does not pass any types that are
  removed through DCE to the generation phase. However it does pass every typedef
  used in the project. This means sometimes a type (which it itself is not used)
  will reference a type that does not exist (removed by DCE).
  Luckily Typescript won't warn about these issues when your definitions are
  included as a library but ideally we'd be able to output completely valid types.

  [HaxeFoundation/haxe#9252](https://github.com/HaxeFoundation/haxe/issues/9252)

## Alternatives

- `archived` Split output with require calls: [hxgenjs](https://github.com/kevinresol/hxgenjs)
- Typescript definition generation: [hxtsdgen](https://github.com/nadako/hxtsdgen)
