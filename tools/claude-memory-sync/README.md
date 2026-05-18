# claude-memory-sync

Sync Claude Code project memories across machines using git.

Claude Code stores memories under `~/.claude/projects/*/memory/` using path-mangled directory names. The same project gets a different name on each machine (`D--anbs-dev-my-project` on Windows vs `home-user-my-project` on Linux). This tool syncs those memories through a git repo with cross-machine alias mapping.

## Prerequisites

- **git** — for sync transport
- **jq** or **python3** — for bash script JSON parsing (uses jq if available, falls back to python3)
- PowerShell 5.1+ — Windows script uses built-in JSON parsing, no extra dependencies

## Setup

1. Create a **private** repo on GitHub (memories can contain project details and personal info)

2. Run setup:
   ```bash
   # Bash
   ./claude-memory-sync.sh setup https://github.com/you/claude-memories.git

   # PowerShell
   .\claude-memory-sync.ps1 setup https://github.com/you/claude-memories.git

   # Or initialize locally first (add remote later)
   ./claude-memory-sync.sh setup --init
   ```

3. Set up project aliases:
   ```bash
   # Auto-detect from git remote (run from inside each project)
   cd ~/my-project
   claude-memory-sync alias --detect

   # Manual alias
   claude-memory-sync alias D--anbs-dev-my-project owner-my-project
   ```

4. Push your memories:
   ```bash
   claude-memory-sync push
   ```

5. On another machine, repeat steps 1-3, then pull:
   ```bash
   claude-memory-sync pull
   ```

## Commands

| Command | Description |
|---------|-------------|
| `setup <repo-url>` | Clone sync repo and create config |
| `setup --init` | Initialize a new local sync repo |
| `sync [--delete] [--force]` | Push then pull (full round-trip) |
| `push [--delete] [--force]` | Push local memories to sync repo (additive by default) |
| `pull [--delete] [--force]` | Pull memories from sync repo to local (additive by default) |
| `status` | Show sync status and last sync info |
| `doctor` | Run health checks against config, aliases, and repo state |
| `list` | List discovered projects and their aliases |
| `alias <mangled> <canonical>` | Manually map a local project name to a canonical name |
| `alias --detect [path]` | Auto-detect canonical name from git remote |

### Push/pull flags

| Flag | Description |
|------|-------------|
| `--delete` | Propagate deletions (push: remove from repo; pull: remove from local). Files move to `.trash/` for recovery. |
| `--force` | Skip the 3-file safety threshold for `--delete` (use only after inspecting the listed files). |

## Alias Resolution

When syncing, each local project needs a canonical name so different machines can map to the same project. Resolution order:

1. **Git remote URL** (`alias --detect`) — extracts `owner-repo` slug from origin. Most reliable since the remote URL is identical on every machine.
2. **Directory name fallback** — if no git remote, uses the leaf directory name.
3. **Manual alias** — set with `alias <mangled> <canonical>` for edge cases.

The canonical name determines the folder name in the sync repo.

## Sync Repo Structure

```
projects/
  owner-project-a/
    memory/
      MEMORY.md          ← auto-generated index
      user_role.md
      feedback_testing.md
  owner-project-b/
    memory/
      ...
.sync-meta.json          ← tracks last sync machine/timestamp
```

`MEMORY.md` is regenerated from the actual files after every sync — it's never a source of conflict.

## Config File

Located at `~/.claude-memory-sync.json`:

```json
{
  "sync_repo": "/home/user/.claude-memory-sync",
  "machine_id": "desktop-linux",
  "aliases": {
    "D--anbs-dev-my-project": "owner-my-project",
    "home-user-my-project": "owner-my-project"
  }
}
```

Override location with `CLAUDE_MEMORY_SYNC_CONFIG` env var.

## Hook Integration

Auto-sync on every Claude Code session by adding a `SessionStart` hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-memory-sync sync",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

This pushes any stale local changes from the last session, then pulls the latest from other machines. No `SessionEnd` hook needed — the next session start picks up anything unpushed.

## Deletion Propagation

Both `push` and `pull` are **additive by default** — they never remove files. This protects against accidental data loss from misconfigured aliases, empty local dirs, or sync running before a project has any memories.

If files exist on one side but not the other, sync reports them and exits without deleting:

```
warning: Push is additive by default. 2 file(s) exist in the repo but not locally:
    paira/codex-patterns.md
    paira/paira.md
warning: To propagate these deletions, re-run with --delete (files move to .trash/ for recovery).
```

### Opting in to delete

To actually propagate deletions, pass `--delete`:

```bash
# Push side: remove from sync repo, files that no longer exist locally
claude-memory-sync push --delete

# Pull side: remove from local, files that no longer exist in repo
claude-memory-sync pull --delete

# Both halves of sync
claude-memory-sync sync --delete
```

Files are **soft-deleted** to `<sync_repo>/.trash/<canonical>/<timestamp>-<filename>` rather than `rm`-ed. The `.trash/` directory is gitignored, so soft-deleted files don't pollute the repo history but stay recoverable until you clean them up manually.

### Safety threshold

If `--delete` would remove more than **3 files in one run**, the operation aborts:

```
error: Refusing to delete 8 files (threshold: 3). This usually means a misconfigured alias or empty local dir. Inspect the list above, then re-run with --delete --force if you're sure.
```

Pass `--force` to override after you've verified the list:

```bash
claude-memory-sync push --delete --force
```

## Health Check

Run `claude-memory-sync doctor` to verify your setup:

```
Config
  [ok] Config file: ~/.claude-memory-sync.json
  [ok] machine_id: anbu-laptop-windows
  [ok] sync_repo: ~/.claude-memory-sync

Aliases
  [ok] D--anbs-dev-my-project -> owner-my-project
  [!! ] Multiple aliases -> 'paira': c--anbs-dev--paira, c--anbs-dev-paira

Local projects
  [ok] All local projects with memory/ are aliased

Canonical names in repo
  [ok] All canonical names resolve to a local dir

Sync repo state
  [ok] On branch main
  [ok] In sync with remote

Trash
  [ok] .trash/ is empty

Last sync
  [ok] 2026-05-18T03:05:30Z by anbu-laptop-windows (this machine)
```

Doctor reports:
- Aliases pointing to non-existent local dirs
- Local projects with `memory/` but no alias (will sync under raw cwd name)
- Canonical names in the repo with no local mapping (next pull would create a sync-artifact dir)
- Multiple aliases mapping to the same canonical (ambiguous reverse lookup)
- Sync repo on non-default branch, or commits ahead/behind remote
- Recoverable files in `.trash/`
- Last sync timestamp and which machine performed it

Run it any time something feels off, especially after renaming projects or before pushing on a long-untouched machine.

## New Machine Setup

On a fresh machine, `pull` creates local project directories using the canonical name even if no alias mapping exists yet. This means you can:

1. Run `setup` + `pull` to get all your memories immediately
2. Run `alias --detect` from each project directory later to set up proper mappings

You don't need to set up aliases before your first pull.

## Conflict Handling

Most syncs are conflict-free because memories are typically separate files. When conflicts do occur:

- `push` runs `git pull --rebase` before committing — git auto-merges where possible
- If auto-merge fails, the tool warns you with the conflicting file paths and stops
- `MEMORY.md` is never a conflict source since it's regenerated, not synced

## Privacy

Your sync repo should be **private**. Memory files can contain:
- Your role and preferences
- Project details and decisions
- Feedback you've given Claude

Never use a public repo for memory sync.
