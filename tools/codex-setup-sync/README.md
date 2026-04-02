# codex-setup-sync

`codex-setup-sync` is a Windows-first PowerShell tool for keeping your Codex setup consistent across machines without copying fragile runtime state. It syncs portable configuration, rules, skills, memories, and optionally completed session JSONL history through a private Git repository.

The tool itself is open source. Your synced state repository should stay private.

## What It Syncs

Managed Codex state:

- `~/.codex/config.toml` via `config.base.toml` plus machine-local `config.local.toml`
- `~/.codex/rules/**`
- `~/.codex/memories/**`
- `~/.agents/skills/**`
- `~/.agents/.skill-lock.json`
- Optional generated launch wrappers
- Optional completed session exports and imports

Local-only exclusions:

- `~/.codex/auth.json`
- `~/.codex/cap_sid`
- `~/.codex/state_*.sqlite*`
- `~/.codex/logs_*.sqlite*`
- `~/.codex/cache/**`
- `~/.codex/.sandbox*/**`
- `%APPDATA%/Codex/**`
- `%LOCALAPPDATA%/Codex/**`
- `~/.codex/skills/.system/**`

## Why Private Git

Rules, skills, memories, and session history can contain sensitive prompts, code, paths, or project names. The recommended pattern is:

1. Keep this tool public and versioned in your main repo.
2. Create a separate private Git repo for your synced machine state.
3. Point `codex-setup-sync` at that private repo.

## Current Support

- Official support in v1: Windows
- Primary provider in v1: Codex
- Session import: experimental

Windows matters here because the official Codex hooks flow is currently not the right integration point for this setup. `codex-setup-sync` uses wrapper launchers instead.

## Install

From the `agentic-engineering` repo:

```powershell
Set-Location D:\path\to\agentic-engineering\tools\codex-setup-sync
Copy-Item .\config.example.json "$HOME\.codex-setup-sync.json"
```

Then edit `~/.codex-setup-sync.json` and choose a private sync repo path.

## Commands

```powershell
.\codex-setup-sync.ps1 setup <repo-url>
.\codex-setup-sync.ps1 setup --init
.\codex-setup-sync.ps1 doctor
.\codex-setup-sync.ps1 status
.\codex-setup-sync.ps1 push
.\codex-setup-sync.ps1 pull
.\codex-setup-sync.ps1 sync
.\codex-setup-sync.ps1 alias add <local-path> <canonical-id>
.\codex-setup-sync.ps1 alias detect [path]
.\codex-setup-sync.ps1 config print
.\codex-setup-sync.ps1 session export
.\codex-setup-sync.ps1 session import
```

## Quick Start

Bootstrap a new private sync repo:

```powershell
.\codex-setup-sync.ps1 setup --init
.\codex-setup-sync.ps1 push
```

Bootstrap from an existing private sync repo:

```powershell
.\codex-setup-sync.ps1 setup https://github.com/you/private-codex-sync.git
.\codex-setup-sync.ps1 doctor
.\codex-setup-sync.ps1 sync
```

## Sync Repo Layout

```text
providers/codex/
  shared/
    config.base.toml
    rules/
    memories/
    agents/
      skills/
      .skill-lock.json
      plugins/
        marketplace.json
  machines/<machine-id>/
    config.local.toml
    aliases.json
    machine.json
    git.local.ini
  sessions/<canonical-project>/<yyyy>/<mm>/<dd>/
    rollout-....jsonl
    rollout-....manifest.json
.sync-meta.json
Open-CodexCLI.ps1
Open-CodexApp.ps1
```

If `launch_wrappers` is enabled, setup also generates `Open-CodexCLI.ps1` and `Open-CodexApp.ps1` into the sync repo root so you can pin and use them directly.

## Migration From An Existing Local Setup

`codex-setup-sync` handles the one-time migration steps for you during export:

- Split live `~/.codex/config.toml` into portable `shared/config.base.toml` and machine-local `machines/<id>/config.local.toml`
- Move `~/.codex/skills/frontend-skill` into `~/.agents/skills/frontend-skill` if it exists there
- Mirror rules, memories, and user skills into the sync repo
- Optionally install a managed PowerShell profile stub and managed Git includes

The intended steady state is:

- edit shared Codex config in the sync repo
- keep machine-specific trust/path entries in `config.local.toml`
- sign into Codex separately on each machine

## Session Import

Session export is enabled by default. Session import is disabled by default and should stay that way unless you explicitly want completed session history materialized back into `~/.codex/sessions`.

Important limitations:

- Only completed, non-empty JSONL session files are exported
- Files modified in the last two minutes are skipped
- Live SQLite, WAL, SHM, or app runtime state is never copied
- Imported sessions are treated as read-only continuity artifacts

## Future Providers

The internal structure is provider-based even though v1 only ships a Codex provider. Future providers should implement:

- path discovery
- portable state export/import
- session export/import
- canonical project identity resolution
- exclusion rules

## References

- [Codex Config Basics](https://developers.openai.com/codex/config-basic)
- [Codex Skills](https://developers.openai.com/codex/skills)
- [Codex Hooks](https://developers.openai.com/codex/hooks)
- [Codex Plugins](https://developers.openai.com/codex/plugins)
- [Build Plugins](https://developers.openai.com/codex/plugins/build)
