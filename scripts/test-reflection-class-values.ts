import { deepStrictEqual, ok } from "node:assert";
import { execFileSync } from "node:child_process";
import { readFileSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { runGeneratedTypeScriptMatrix } from "./toolchains.js";

const scriptRoot = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptRoot, "../..");
const fixtureRoot = path.join(repoRoot, "tests/reflection-class-values");
const expectedTranscript = [
  "reflectionclassvalues._Main.ToStringCollision",
  "reflectionclassvalues._Main.ApplyCollision",
  "reflectionclassvalues._Main.CompatibleToString",
  "reflectionclassvalues._Main.CompatibleApply",
  "reflectionclassvalues._Main.CallCollision",
  "reflectionclassvalues._Main.BindCollision",
  "reflectionclassvalues._Main.NativeApplyCollision",
  "reflectionclassvalues._Main.NativeApplyEscape",
  "reflectionclassvalues._Main.PropertyCollision",
  "reflectionclassvalues._Main.InheritedCollision",
  "reflectionclassvalues._Main.OrdinaryClass",
  "reflectionclassvalues._Main.ImplementsMarker",
  "reflectionclassvalues._Main.ToStringCollision",
  "reflectionclassvalues._Main.ApplyCollision",
  "reflectionclassvalues._Main.CompatibleToString",
  "reflectionclassvalues._Main.CompatibleApply",
  "reflectionclassvalues._Main.CallCollision",
  "reflectionclassvalues._Main.BindCollision",
  "reflectionclassvalues._Main.NativeApplyCollision",
  "reflectionclassvalues._Main.NativeApplyEscape",
  "reflectionclassvalues._Main.PropertyCollision",
  "reflectionclassvalues._Main.InheritedCollision",
  "reflectionclassvalues._Main.OrdinaryClass",
  "reflectionclassvalues._Main.ImplementsMarker",
  "toString:3",
  "14",
  "compatible-toString",
  "3",
  "call:value",
  "left+right",
  "12",
  "14",
  "property-call",
  "48"
].join("|");

function run(command: string, args: ReadonlyArray<string>): void {
  execFileSync(command, [...args], { cwd: repoRoot, stdio: "inherit" });
}

function transcript(relativeFile: string): string {
  return execFileSync(process.execPath, [path.join(repoRoot, relativeFile)], {
    cwd: repoRoot,
    encoding: "utf8"
  }).trim();
}

rmSync(path.join(fixtureRoot, "out"), { recursive: true, force: true });
run("haxe", ["tests/reflection-class-values/build-ts.hxml"]);
runGeneratedTypeScriptMatrix(
  "tests/reflection-class-values/tsconfig.generated.json"
);
run("haxe", ["tests/reflection-class-values/build-classic.hxml"]);
run("haxe", ["tests/reflection-class-values/build-standard.hxml"]);

deepStrictEqual(
  [
    transcript("tests/reflection-class-values/out/ts/dist/index.js"),
    transcript("tests/reflection-class-values/out/classic/index.js"),
    transcript("tests/reflection-class-values/out/standard/index.cjs")
  ],
  [expectedTranscript, expectedTranscript, expectedTranscript]
);

const typescript = readFileSync(
  path.join(
    fixtureRoot,
    "out/ts/src-gen/reflectionclassvalues/Main.ts"
  ),
  "utf8"
);

for (const className of [
  "ToStringCollision",
  "ApplyCollision",
  "NativeApplyCollision",
  "PropertyCollision",
  "InheritedBase",
  "InheritedCollision"
]) {
  ok(
    typescript.includes(
      `return Register.unsafeCast<Function>(${className})`
    ),
    `${className} reflection returns use the exact Function boundary bridge`
  );
  ok(
    typescript.includes(
      `Register.setHxClass(\"reflectionclassvalues._Main.${className}\", Register.unsafeCast<Function>(${className}));`
    ),
    `${className} runtime registration uses the exact Function boundary bridge`
  );
}

for (const className of [
  "CompatibleToString",
  "CompatibleApply",
  "CallCollision",
  "BindCollision",
  "NativeApplyEscape",
  "OrdinaryClass"
]) {
  ok(
    !typescript.includes(
      `Register.unsafeCast<Function>(${className})`
    ),
    `${className} remains direct when its static surface is Function-compatible`
  );
}

ok(
  typescript.includes(
    "return Register.unsafeCast<Function>(InheritedBase)"
  ),
  "the subclass __super__ getter bridges a conflicting parent class value"
);
ok(
  !typescript.includes(
    "Register.unsafeCast<Function>(OrdinaryClass)"
  ),
  "an ordinary class does not receive an unnecessary Function bridge"
);
ok(
  !typescript.includes(
    "Register.unsafeCast<Function>(Marker)"
  ),
  "a non-conflicting interface value remains directly typed"
);

for (const relativeFile of [
  "out/classic/reflectionclassvalues/Main.js",
  "out/standard/index.cjs"
]) {
  const generated = readFileSync(path.join(fixtureRoot, relativeFile), "utf8");
  ok(
    !generated.includes("unsafeCast<Function>"),
    `${relativeFile} stays free of TypeScript-only identity syntax`
  );
}

process.stdout.write(
  "reflection-class-values:ok (TS Function boundary + classic + standard)\n"
);
