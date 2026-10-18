# Other stacks

Tool equivalents for stacks other than Node and TypeScript. The steps, layers, and report are the same; only the tools change. Use what the project already has, and record the rest as skipped with the command to add it. Where an organization keeps an approved tool list, prefer tools from it.

## Tools

| Purpose | Python | Java / Kotlin | Go | .NET |
|---|---|---|---|---|
| Strict types | `mypy --strict`, or pyright in strict mode | `javac -Xlint:all -Werror`; Error Prone with NullAway; Kotlin `allWarningsAsErrors` | `go vet ./...` | `<Nullable>enable</Nullable>`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` |
| Lint | `ruff check` | Checkstyle, PMD, SpotBugs; detekt for Kotlin | `staticcheck ./...` or `golangci-lint run` | Roslyn analyzers with `<AnalysisLevel>latest-all</AnalysisLevel>` |
| Dead code | `vulture` | IDE inspections; PMD unused-code rules | `deadcode ./...` (`golang.org/x/tools/cmd/deadcode`) | analyzers IDE0051 and IDE0052 |
| Unused dependencies | `deptry` | `mvn dependency:analyze`; Gradle dependency-analysis plugin | `go mod tidy -diff` | not covered by a standard tool; review the project file |
| Boundaries | `import-linter` | ArchUnit; Konsist for Kotlin | `depguard` in golangci-lint (the compiler already rejects import cycles) | NetArchTest or ArchUnitNET |
| Duplication | `jscpd`, or pylint `duplicate-code` | PMD CPD | `dupl` in golangci-lint | `jscpd` |
| Tests | `pytest` | JUnit through Maven or Gradle | `go test ./...` | `dotnet test` |

`jscpd` works on any language and is a fallback for duplication everywhere.

## Escape hatches to search for

| Stack | Patterns |
|---|---|
| Python | `# type: ignore`, `Any`, `cast(`, `# noqa`, bare `except:`, `except Exception: pass` |
| Java / Kotlin | `@SuppressWarnings`, raw generic types, `Object` parameters, empty `catch` blocks, Kotlin `!!` |
| Go | `//nolint`, `interface{}` or `any` in signatures, `_ =` or `_, _ =` on calls that return an error |
| .NET | `#pragma warning disable`, the null-forgiving `!`, `dynamic`, empty `catch` blocks |

## Canonical patterns

The Node reference describes the patterns in Fastify terms. The same ideas map across stacks:

| Idea | Python | Java / Kotlin | Go | .NET |
|---|---|---|---|---|
| Validate at the boundary, types from the schema | Pydantic models (FastAPI uses them for request and response) | Jakarta Bean Validation on request DTOs | struct validation at the handler, then typed values inside | DataAnnotations or FluentValidation on request models |
| One API contract | FastAPI's generated OpenAPI | springdoc-openapi | oapi-codegen from one OpenAPI file | Swashbuckle or NSwag |
| Config validated at boot | pydantic-settings | `@ConfigurationProperties` with `@Validated` | one config struct loaded and checked in `main` | the options pattern with `ValidateOnStart()` |
| One error model | exception classes with one handler | `@ControllerAdvice` | error types with one mapping function | exception middleware or `IExceptionHandler` |
| Distinct ID types | `NewType` | value classes or records | named types (`type UserID string`) | `readonly record struct` wrappers |
| Layer rules as code | import-linter contracts | ArchUnit tests | depguard rules | NetArchTest tests |

The new-app baseline in the Node reference applies with these substitutions: strict compiler settings, a strict linter, a formatter, layer rules, boundary validation, config validated at boot, one error model, one test harness that starts the app the same way production does, CI on every PR, git and agent hooks, one-command scripts, one vertical slice to copy, and a short instruction file plus a verification skill.
