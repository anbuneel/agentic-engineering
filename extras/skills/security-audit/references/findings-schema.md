# Findings Schema

Every external reviewer and native lens returns one object in this shape, so consolidation, deduplication, and convergence work on data instead of prose. The primary driver writes the schema to `${REVIEW_DIR}/findings.schema.json` at preflight with the severity enum for the skill filled in.

| Skill | `severity` enum |
|-------|-----------------|
| `multi-agent-code-review`, `multi-agent-plan-review` | `MUST_FIX`, `SHOULD_FIX`, `CONSIDER` |
| `security-audit` | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` |

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "findings"],
  "properties": {
    "verdict": { "type": "string", "enum": ["APPROVED", "REVISE"] },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["file", "line", "severity", "title", "detail"],
        "properties": {
          "file": { "type": "string", "description": "Path relative to the repository root" },
          "line": { "type": "integer", "description": "1-based line number, 0 when not applicable" },
          "severity": { "type": "string", "enum": ["MUST_FIX", "SHOULD_FIX", "CONSIDER"] },
          "title": { "type": "string", "description": "One line, under 80 characters" },
          "detail": { "type": "string", "description": "What is wrong, why it matters, and what would fix it" }
        }
      }
    }
  }
}
```

## Passing it to reviewers

- Claude CLI: `--json-schema '<the JSON above>'`. The parsed object arrives in the `structured_output` field of the JSON result.
- Codex CLI: `--output-schema "${REVIEW_DIR}/findings.schema.json"`. The file named by `-o` contains the object.
- Native lens agents: include the schema in the task prompt and ask for the object as the final message.
- GitHub review agent comments arrive as text. Parse each into the same shape natively before consolidation, with `line` set to `0` when the comment has no anchor.

## Verdict

`APPROVED` means the reviewer found nothing at the top severity of the skill's scale. `REVISE` means at least one such finding. The verdict is advisory: the primary driver counter-reviews every finding and decides convergence itself.

## Fingerprints

Compute `fingerprint = <file>:<severity>:<slug>` natively for every finding, where `slug` is three to five lowercase keywords from the title joined by hyphens. Fingerprints drive deduplication within a round and cross-round tracking of GitHub bot findings. Match fuzzily: same file plus overlapping keywords counts as the same finding even when the line moved or the severity label differs.
