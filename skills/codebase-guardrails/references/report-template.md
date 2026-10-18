# Report template

Write the report in this structure, in plain language. Every finding cites `file:line` or a tool output file.

```markdown
# Codebase guardrails: <repo or scope>

Run <RUN_ID>, <YYYY-MM-DD>. Mode: <existing|new>. Scope: <path>. Stack: <one line>.

## Summary

Three to five sentences: the biggest source of drift, the most important missing check, and what to do first.

## Top 10

| ID | Problem | Layer | Fix | Check that keeps it fixed | Effort | Risk | Leverage |
|---|---|---|---|---|---|---|---|

## Conventions

| Concern | Variants found (count, example paths) | Canonical | Example to copy |
|---|---|---|---|

## Findings  (mode=existing)

One line per finding, grouped under CODE, CHECK, PROSE, REVIEW:
- <ID> <cause>: <count> places (<file:line>, <file:line>). Fix: <end state>. Check: <rule or "none" and why>. <effort>/<risk>/<leverage>

## Baseline  (mode=new)

| Item | Status | Evidence | Action |
|---|---|---|---|

## Tool counts

| Metric | Count | Last report |
|---|---|---|

Include compiler errors per strict flag, lint violations per top rule, unused files, exports and dependencies, import cycles, duplicated lines %, and escape hatches by pattern.

## Prose audit

| File | Rule | Class | Action |
|---|---|---|---|

Then the proposed instruction file text in full.

## Plan

### Phase <n>: <goal>

#### PR <n>.<m>: <title>

- Goal:
- Files:
- Check and rollout step:
- Verify:
- Done when:

## Questions for the owner

The REVIEW decisions and anything that may be deliberate.

## Skipped

Tools and lenses that were skipped or failed, with the reason, and lens findings dropped.
```
