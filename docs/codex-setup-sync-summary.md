# codex-setup-sync Summary

## What We Built

We implemented a new Windows-first OSS tool at `tools/codex-setup-sync` inside the `agentic-engineering` repo.

What is in place:

- Entry point and command surface in `tools/codex-setup-sync/codex-setup-sync.ps1`: `setup`, `doctor`, `status`, `push`, `pull`, `sync`, `alias`, `config print`, `session export`, `session import`
- Core modules in `tools/codex-setup-sync/lib` for config loading, git ops, identity mapping, session handling, config rendering, doctor checks, and sync orchestration
- A Codex provider in `tools/codex-setup-sync/providers/codex.ps1` that:
  - syncs portable Codex state
  - keeps auth and runtime state local
  - splits `config.toml` into a shared base plus machine-local overlay
  - migrates `frontend-skill` into `.agents/skills`
  - exports and imports completed session JSONL files
  - generates launch wrappers when enabled
- Wrapper scripts in `tools/codex-setup-sync/wrappers`
- Example config in `tools/codex-setup-sync/config.example.json`
- Tool docs in `tools/codex-setup-sync/README.md`

Repo docs were also updated:

- `README.md`
- `CHANGELOG.md`

Verification completed:

- Added Pester coverage in `tools/codex-setup-sync/tests`
- Ran parser checks across the new PowerShell files
- Ran the test suite: 8 passed, 0 failed

Notable fixes made during implementation:

- fixed `~/...` path expansion
- fixed wrapper generation
- made tests compatible with the Pester version installed on this machine

## Why We Built It

We built `codex-setup-sync` to solve a practical gap: using Codex across multiple Windows machines is frustrating if you want the same setup, the same skills and rules, and usable session continuity without manually recreating everything on each box.

The core problem is that Codex state is not one clean portable bundle. Some parts should sync, like config, rules, skills, and memories. Some parts are machine-specific, like trusted project paths. Some parts should never sync, like auth tokens, SQLite and runtime state, caches, and app internals. Without separating those layers, “sync everything” is brittle and unsafe, while “sync nothing” means constant setup drift.

So we built it to give people a disciplined middle path:

- keep portable Codex setup consistent across machines
- preserve machine-local differences where needed
- avoid corrupting live state by syncing the wrong files
- optionally carry completed session history across devices
- package the workflow as an open-source tool others can adopt, not just a one-off personal script

In short, the goal is to make cross-machine Codex use feel consistent and low-friction without pretending that all local Codex state is safe to replicate.
