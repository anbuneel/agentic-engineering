# Node and TypeScript

Tools, canonical patterns, and the new-app baseline for Node, TypeScript, Fastify, and web frontends.

## Running tools

Run local tools through the project's package manager so the project's versions are used:

| Package manager | Installed tool | Missing tool, `tools=fetch` only |
|---|---|---|
| npm | `npx --no-install <bin> ...` | `npx --yes <package> ...` |
| pnpm | `pnpm exec <bin> ...` | `npx --yes <package> ...` |
| Yarn | `yarn <bin> ...` | `npx --yes <package> ...` |

A "not found" or missing-package error from the installed form means `skipped: not installed`. Record the command that would add the tool as a dev dependency in the report.

In a monorepo, run per package when the tool has no workspace mode, and sum the counts.

## Tools

| Purpose | Tool | Command | Record |
|---|---|---|---|
| Compiler, current config | tsc | `tsc --noEmit -p <tsconfig> --pretty false` | `error TS` count per code and per directory |
| Cost of stricter flags | tsc | the same command plus one flag at a time (see below) | error count per flag |
| Lint, current config | the project's linter (ESLint, Biome, or oxlint) | ESLint: `eslint <scope> -f json -o ${REVIEW_DIR}/eslint-${RUN_ID}.json` | violation count per rule |
| Cost of strict type-aware lint | ESLint 9+ with typescript-eslint 8+, only if both are installed | the probe below | violation count per rule |
| Unused files, exports, dependencies | knip | `knip --reporter json --no-exit-code` | counts per category, examples |
| Boundaries and cycles, configured | dependency-cruiser, if the repo has a config | `depcruise <scope> --output-type json --output-to ${REVIEW_DIR}/depcruise-${RUN_ID}.json` | violations per rule |
| Cycles, no config | madge | `madge --circular --extensions ts,tsx --ts-config <tsconfig> <scope>` | each cycle |
| Duplication | jscpd | `jscpd <scope> --min-tokens 70 --reporters json --output ${REVIEW_DIR}/jscpd-${RUN_ID} --ignore "**/node_modules/**,**/dist/**,**/build/**,**/coverage/**"` | duplicated-lines percentage, top clone pairs from `jscpd-report.json` |
| Tests | the project's test script | run once | pass, fail, and skip counts; duration |
| Escape hatches and drift | file search | the patterns below | count per pattern and per directory |

If the project uses TypeScript project references (`tsc -b`), run the compiler per package `tsconfig` with `-p`. If a flag probe fails to start, record it as failed and move on.

### Strictness flag probe

Skip flags that are already on. `strict` is on by default from TypeScript 6 and off by default before it, and the config can override either default. If it is off, probe `--strict` first, then run the other probes with `--strict` added, because `--exactOptionalPropertyTypes` fails to start without `strictNullChecks`.

- `--strict`
- `--noUncheckedIndexedAccess`
- `--exactOptionalPropertyTypes`
- `--noImplicitOverride`
- `--noFallthroughCasesInSwitch`
- `--noImplicitReturns`

### Strict lint probe

Write this file to `${REVIEW_DIR}/eslint-probe-${RUN_ID}.mjs`, with `PROJECT_ROOT` in forward-slash form. It lives inside the project, so its import resolves from the project's `node_modules`. It is a probe only; never copy it into the project.

```js
import tseslint from 'typescript-eslint';

export default [
  { ignores: ['**/node_modules/**', '**/dist/**', '**/build/**', '**/coverage/**', '**/*.config.*'] },
  ...tseslint.configs.strictTypeChecked.map((config) => ({
    ...config,
    files: ['**/*.ts', '**/*.tsx', '**/*.mts', '**/*.cts'],
  })),
  {
    files: ['**/*.ts', '**/*.tsx', '**/*.mts', '**/*.cts'],
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: '<PROJECT_ROOT>' },
    },
  },
];
```

Run `eslint <scope> -c ${REVIEW_DIR}/eslint-probe-${RUN_ID}.mjs -f json -o ${REVIEW_DIR}/eslint-probe-${RUN_ID}.json`.

### Search patterns

Search `.ts`, `.tsx`, `.mts`, and `.cts` files, excluding generated and build output. Non-null assertions come from the lint probe, not from search.

| Pattern | Regex |
|---|---|
| `any` | `\bas any\b`, `:\s*any\b`, `<any>` |
| Double cast | `as unknown as` |
| Compiler suppression | `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck` |
| Lint suppression | `eslint-disable` |
| Env access | `process\.env` (count files outside the config module) |
| Raw fetch | `\bfetch\(` (count files outside the API client) |
| Console in server code | `console\.[a-z]+\(` |
| Empty catch | `catch\s*(\([^)]*\))?\s*\{\s*\}` |
| Skipped or focused tests | `\.skip\(`, `\.only\(`, `\bxit\(`, `\bxdescribe\(` |
| Markers | `TODO`, `FIXME`, `HACK` |

## Canonical patterns

Use these as the default canonical choice in Step 4 when the code has no clear winner. Prefer what the project already does well over these.

### Server (Fastify)

- **Schema-first routes.** Define request and response schemas with TypeBox (`@fastify/type-provider-typebox`) or Zod (`fastify-type-provider-zod`). Handler types come from the schema, so there are no hand-written duplicate interfaces. Response schemas also drop undeclared fields during serialization, which stops accidental data leaks.
- **One route module per resource**, registered as a plugin with a prefix. Use either `@fastify/autoload` or explicit registration, not both.
- **Thin handlers.** A handler parses input, calls a service, and returns the result. Services take typed inputs and never see `request` or `reply`. Data access lives in one layer.
- **Config validated at boot** with `@fastify/env` or a schema over `process.env`, exported as one typed object. Nothing else reads `process.env`.
- **One error model.** A small set of error classes (or `@fastify/error`) and one `setErrorHandler` that maps them to status codes. Handlers throw; they do not build error responses.
- **Typed decorators.** Every `decorate` and `decorateRequest` has a matching `declare module 'fastify'` augmentation, in one file.
- **Encapsulation on purpose.** Wrap a plugin with `fastify-plugin` only when its decorators must be visible to the parent. Wrapping everything removes Fastify's encapsulation.
- **Logging** through `request.log` and `fastify.log`, never `console`.
- **One app factory.** `buildApp()` creates the instance for both the server and the tests. Route tests use `app.inject()` with no open port.

### Shared contracts

- **One source of truth** for API shapes: a shared `contracts` package or folder of schemas that both server and client import. The alternative is generating OpenAPI with `@fastify/swagger` and a typed client with `openapi-typescript`. Pick one.
- **Branded IDs**, for example `type UserId = string & { readonly __brand: 'UserId' }`, created only by a parse function. Swapping two IDs then fails to compile.
- **Discriminated unions** for status and result types, with exhaustive `switch` checks.
- **Parse at the boundaries**: requests, env, database rows, third-party responses. Trust the types inside.

### Frontend

- **One API client module.** Components never call `fetch` directly.
- **One server-state library** (for example TanStack Query) and one approach to UI state.
- **Feature folders** with a public `index.ts`. Other features import only through it.

## Checks that encode boundaries

Prefer an existing rule to a custom one, and a custom rule to a prose line.

| Problem | Check |
|---|---|
| Import cycles | dependency-cruiser `no-circular` |
| Handlers reaching the database | dependency-cruiser rule from the routes path to the data path |
| Client importing server code | dependency-cruiser rule from the client path to the server path |
| Deep imports across features | `no-restricted-imports` with `patterns`, or a dependency-cruiser rule |
| `process.env` outside config | `no-restricted-properties` (`object: 'process', property: 'env'`) with an override for the config file |
| Raw `fetch` outside the API client | `no-restricted-globals` with an override for the client module |
| `console` in server code | `no-console` |
| `any`, unsafe casts, `!` | `@typescript-eslint/no-explicit-any`, the `no-unsafe-*` rules, `@typescript-eslint/no-non-null-assertion` |
| Floating promises | `@typescript-eslint/no-floating-promises`, `@typescript-eslint/no-misused-promises` |
| Non-exhaustive `switch` | `@typescript-eslint/switch-exhaustiveness-check` |
| Unexplained suppressions | `@typescript-eslint/ban-ts-comment` with `allow-with-description`, `linterOptions.reportUnusedDisableDirectives: 'error'` |
| Dead code and unused dependencies | knip in CI |
| Project-specific patterns | `no-restricted-syntax` with an AST selector first; a small local ESLint rule with `RuleTester` tests when a selector is not enough |

A dependency-cruiser config that encodes the layers:

```js
// .dependency-cruiser.cjs
module.exports = {
  forbidden: [
    { name: 'no-circular', severity: 'error', from: {}, to: { circular: true } },
    {
      name: 'routes-not-to-db',
      severity: 'error',
      from: { path: '^src/server/routes' },
      to: { path: '^src/server/db' },
    },
    {
      name: 'client-not-to-server',
      severity: 'error',
      from: { path: '^src/client' },
      to: { path: '^src/server' },
    },
  ],
  options: {
    tsConfig: { fileName: 'tsconfig.json' },
    doNotFollow: { path: 'node_modules' },
  },
};
```

### Rolling out a check on existing code

- ESLint: add the rule as `warn`, or keep it `error` and record today's violations with ESLint's bulk suppressions (`eslint --suppress-rule <rule>`, ESLint 9.24 and later). Fix in batches. Then remove the suppressions or switch to `error`.
- Compiler flags have no per-file baseline. Turn a flag on per package, or fix the errors in batches on a branch and turn it on in the last PR.
- dependency-cruiser: `depcruise-baseline` writes known violations to a file that the check then ignores.

### Feedback loop

- **CI on every PR:** install from the lockfile, then typecheck, lint, test, build, knip, and dependency-cruiser as separate steps, so a failure names its cause.
- **Git hooks** (husky or lefthook) run for every agent and every person: lint and format staged files before commit; typecheck and unit tests before push.
- **Agent hooks** give feedback while the agent works, before it opens a PR. Claude Code: a `PostToolUse` hook on `Edit|Write` that lints the changed file, and a `Stop` hook that runs typecheck and unit tests and exits with code 2 on failure so the agent keeps working. For other agents, use their hook feature if the version in use has one; git hooks and CI cover the rest.
- **One command per job** in `package.json` scripts: `dev`, `test`, `typecheck`, `lint`, `check` (all gates), and `db:seed` or equivalent. Agents run what the scripts name.

## New-app baseline

Check each item in `mode=new`. In `mode=existing`, use the list to spot missing feedback-loop items.

1. `tsconfig` with `strict` set explicitly, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, and `noFallthroughCasesInSwitch`
2. ESLint flat config with `strictTypeChecked`, `no-console` in server code, suppressions that need a description, and unused suppressions reported as errors
3. A formatter (Prettier or Biome) in CI and in a git hook, so style never reaches review
4. The folder layout declared and enforced with dependency-cruiser rules before most code exists
5. Schema-first routes with a type provider, and one shared contracts location
6. Config validated at boot, with `process.env` banned elsewhere
7. Error classes and one error handler
8. A `buildApp()` factory used by the server and the tests, an `inject()` test for each route, and a one-command test database setup
9. CI on every PR running every gate
10. A git hook and, where the agent supports it, an agent hook
11. One-command scripts for each job
12. One complete vertical slice (route, service, data access, client call, UI, tests) as the canonical example agents copy
13. A short agent instruction file: commands, canonical example paths, and intent. Plus a project verification skill (for example `.claude/skills/verify/SKILL.md`, `.agents/skills/verify/SKILL.md`, or `.github/skills/verify/SKILL.md`) that says how to prove a change works: start the app, seed data, call the endpoint, and run the browser test
