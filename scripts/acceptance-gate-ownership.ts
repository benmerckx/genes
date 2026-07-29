import { readFileSync } from "node:fs";
import path from "node:path";

/**
 * Focused compiler contracts that acceptance, rather than an outer CI wrapper,
 * owns.
 *
 * Why: these tests previously ran only from the release-oriented `test:ci`
 * command. The normal stable pull-request job calls `test:acceptance`
 * directly, so regressions in module-function emission or strict array reads
 * could reach main before the focused test ran.
 *
 * What/How: `test-acceptance.ts` executes this list exactly once. The
 * validation below rejects a second direct invocation from `test:ci` or either
 * GitHub workflow. Standalone focused commands remain available for iteration.
 */
export const acceptanceOwnedFocusedGates = [
  {
    packageScript: "test:module-functions",
    compiledScript: "scripts/dist/test-module-functions.js"
  },
  {
    packageScript: "test:array-index-strict",
    compiledScript: "scripts/dist/test-array-index-strict.js"
  },
  {
    packageScript: "test:reflection-class-values",
    compiledScript: "scripts/dist/test-reflection-class-values.js"
  }
] as const;

function directInvocation(source: string, packageScript: string): string | undefined {
  return [
    `yarn ${packageScript}`,
    `yarn run ${packageScript}`,
    `npm run ${packageScript}`,
    `pnpm ${packageScript}`,
    `pnpm run ${packageScript}`
  ].find((candidate) => source.includes(candidate));
}

/**
 * Rejects CI wiring that executes an acceptance-owned focused gate twice.
 *
 * The check deliberately covers only direct invocations. Aggregate commands
 * remain free to compose other suites; acceptance is the documented owner for
 * the two entries above, and a duplicate direct command is the regression this
 * checkpoint found.
 */
export function assertFocusedGateOwnership(repoRoot: string): void {
  const packageJson = JSON.parse(
    readFileSync(path.join(repoRoot, "package.json"), "utf8")
  ) as { scripts?: Record<string, string> };
  const sources = [
    {
      label: "test:ci",
      source: packageJson.scripts?.["test:ci"] ?? ""
    },
    ...[
      ".github/workflows/ci.yml",
      ".github/workflows/release.yml"
    ].map((relativePath) => ({
      label: relativePath,
      source: readFileSync(path.join(repoRoot, relativePath), "utf8")
    }))
  ];

  const seen = new Set<string>();
  for (const gate of acceptanceOwnedFocusedGates) {
    if (seen.has(gate.compiledScript)) {
      throw new Error(`Acceptance focused gate is listed twice: ${gate.compiledScript}`);
    }
    seen.add(gate.compiledScript);

    for (const owner of sources) {
      const duplicate = directInvocation(owner.source, gate.packageScript);
      if (duplicate !== undefined) {
        throw new Error(
          `${gate.packageScript} is owned by test:acceptance and must not also run directly from ${owner.label}: ${duplicate}`
        );
      }
    }
  }
}
