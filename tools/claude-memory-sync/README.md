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
| `sync` | Push then pull (full round-trip) |
| `push` | Push local memories to sync repo |
| `pull` | Pull memories from sync repo to local |
| `status` | Show sync status and last sync info |
| `list` | List discovered projects and their aliases |
| `alias <mangled> <canonical>` | Manually map a local project name to a canonical name |
| `alias --detect [path]` | Auto-detect canonical name from git remote |

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

When you delete a memory file locally and `push`, the file is also removed from the sync repo. The next `pull` on another machine will not bring it back.

This only applies to projects you're actively syncing — files from projects you haven't pushed from this machine are left untouched.

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
