# claude-memory-sync

Sync Claude Code project memories across machines using git.

Claude Code stores memories under `~/.claude/projects/*/memory/` using path-mangled directory names. The same project gets a different name on each machine (`D--anbs-dev-my-project` on Windows vs `home-user-my-project` on Linux). This tool syncs those memories through a git repo with cross-machine alias mapping.

## Prerequisites

- **git** — for sync transport
- **jq** — for bash script JSON parsing (`brew install jq` / `apt install jq` / `choco install jq`)
- PowerShell 5.1+ — Windows script uses built-in JSON parsing, no jq needed

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
            "command": "claude-memory-sync push && claude-memory-sync pull",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

This pushes any stale local changes from the last session, then pulls the latest from other machines. No `SessionEnd` hook needed — the next session start picks up anything unpushed.

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
