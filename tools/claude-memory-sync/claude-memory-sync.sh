#!/usr/bin/env bash
set -euo pipefail

# claude-memory-sync.sh — Sync Claude Code memories across machines via git
# https://github.com/anbuneel/agentic-engineering

VERSION="1.0.0"
CONFIG_FILE="${CLAUDE_MEMORY_SYNC_CONFIG:-$HOME/.claude-memory-sync.json}"
CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"

# --- Output helpers ---

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

usage() {
  cat <<EOF
claude-memory-sync $VERSION — Sync Claude Code memories across machines via git

Usage: claude-memory-sync <command> [options]

Commands:
  setup <repo-url>                  Clone sync repo and create config
  setup --init                      Initialize a new local sync repo
  sync                              Push then pull (full round-trip)
  push                              Push local memories to sync repo
  pull                              Pull memories from sync repo to local
  status                            Show sync status
  list                              List discovered projects and aliases
  alias <mangled-name> <canonical>  Set a manual alias
  alias --detect [project-path]     Auto-detect alias from git remote

Options:
  --help     Show this help
  --version  Show version

Prerequisites: git, jq or python3
EOF
}

# --- JSON backend (jq with python3 fallback) ---

_JSON_CMD=""

_init_json() {
  [[ -n "$_JSON_CMD" ]] && return
  if command -v jq &>/dev/null; then
    _JSON_CMD="jq"
  elif python3 -c "import json" 2>/dev/null; then
    _JSON_CMD="python3"
  elif python -c "import json, sys; assert sys.version_info[0]>=3" 2>/dev/null; then
    _JSON_CMD="python"
  else
    die "Either jq or python3 is required"
  fi
}

# Read a top-level string field from a JSON file
json_read() {
  local file="$1" field="$2"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    jq -r ".$field // empty" "$file"
  else
    "$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
v = d.get(sys.argv[2], '')
print(v if v else '')
" "$file" "$field"
  fi
}

# Read an alias value for a mangled name
json_get_alias() {
  local file="$1" mangled="$2"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    jq -r --arg m "$mangled" '.aliases[$m] // empty' "$file"
  else
    "$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
print(d.get('aliases', {}).get(sys.argv[2], ''))
" "$file" "$mangled"
  fi
}

# Find the alias key (mangled name) for a canonical value
json_find_alias_key() {
  local file="$1" canonical="$2"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    jq -r --arg c "$canonical" \
      '.aliases | to_entries[] | select(.value == $c) | .key' \
      "$file" 2>/dev/null | head -1
  else
    "$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
keys = [k for k, v in d.get('aliases', {}).items() if v == sys.argv[2]]
print(keys[0] if keys else '')
" "$file" "$canonical"
  fi
}

# Set an alias in the config file (read → modify → write)
json_set_alias() {
  local file="$1" mangled="$2" canonical="$3"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    local config
    config=$(cat "$file")
    echo "$config" | jq --arg m "$mangled" --arg c "$canonical" \
      '.aliases[$m] = $c' > "${file}.tmp"
  else
    "$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
d.setdefault('aliases', {})[sys.argv[2]] = sys.argv[3]
with open(sys.argv[4], 'w', encoding='utf-8-sig') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$file" "$mangled" "$canonical" "${file}.tmp"
  fi
  mv "${file}.tmp" "$file"
}

# Create a new config file
json_create_config() {
  local file="$1" repo="$2" mid="$3"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    jq -n --arg repo "$repo" --arg mid "$mid" \
      '{sync_repo: $repo, machine_id: $mid, aliases: {}}' > "$file"
  else
    "$_JSON_CMD" -c "
import json, sys
with open(sys.argv[3], 'w', encoding='utf-8-sig') as f:
    json.dump({'sync_repo': sys.argv[1], 'machine_id': sys.argv[2], 'aliases': {}}, f, indent=2)
    f.write('\n')
" "$repo" "$mid" "$file"
  fi
}

# Update sync_repo and machine_id in existing config
json_update_config() {
  local file="$1" repo="$2" mid="$3"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    local config
    config=$(cat "$file")
    echo "$config" | jq --arg repo "$repo" --arg mid "$mid" \
      '.sync_repo = $repo | .machine_id = $mid' > "${file}.tmp"
  else
    "$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
d['sync_repo'] = sys.argv[2]
d['machine_id'] = sys.argv[3]
with open(sys.argv[4], 'w', encoding='utf-8-sig') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$file" "$repo" "$mid" "${file}.tmp"
  fi
  mv "${file}.tmp" "$file"
}

# Update .sync-meta.json with last sync info
json_update_meta() {
  local file="$1" mid="$2" ts="$3"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    local existing
    existing=$(cat "$file" 2>/dev/null || echo '{}')
    echo "$existing" | jq --arg mid "$mid" --arg ts "$ts" \
      '. * {last_sync: {machine: $mid, timestamp: $ts}}' > "${file}.tmp"
    mv "${file}.tmp" "$file"
  else
    "$_JSON_CMD" -c "
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
except:
    d = {}
d['last_sync'] = {'machine': sys.argv[2], 'timestamp': sys.argv[3]}
with open(sys.argv[1], 'w', encoding='utf-8-sig') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$file" "$mid" "$ts"
  fi
}

# Print formatted last sync info, or empty string if never synced
json_format_last_sync() {
  local file="$1"
  if [[ "$_JSON_CMD" == "jq" ]]; then
    local last_sync
    last_sync=$(jq -r '.last_sync // empty' "$file" 2>/dev/null || true)
    if [[ -n "$last_sync" ]]; then
      echo "$last_sync" | jq -r '"by \(.machine) at \(.timestamp)"'
    fi
  else
    "$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
ls = d.get('last_sync')
if ls:
    print(f'by {ls[\"machine\"]} at {ls[\"timestamp\"]}')
" "$file" 2>/dev/null || true
  fi
}

# --- Config helpers ---

require_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Not set up. Run: claude-memory-sync setup <repo-url>"
}

get_sync_repo() {
  local repo
  repo=$(json_read "$CONFIG_FILE" "sync_repo")
  [[ -n "$repo" ]] || die "sync_repo not set in config"
  repo="${repo/#\~/$HOME}"
  echo "$repo"
}

get_machine_id() {
  json_read "$CONFIG_FILE" "machine_id"
}

# --- Path / alias helpers ---

# Convert an absolute path to Claude's mangled project directory name
mangle_path() {
  local p="$1"

  # Git Bash on Windows: /d/path → D:/path
  if [[ "$p" =~ ^/([a-zA-Z])(/.*) ]]; then
    local drive="${BASH_REMATCH[1]}"
    local rest="${BASH_REMATCH[2]}"
    drive="${drive^^}"
    p="${drive}:${rest}"
  fi

  # Replace : / \ with -
  p="${p//\:/-}"
  p="${p//\//-}"
  p="${p//\\/-}"
  # Strip leading -
  p="${p#-}"
  echo "$p"
}

# Extract owner-repo slug from a git remote URL
slugify_remote() {
  local url="$1"
  # SSH:   git@github.com:owner/repo.git → owner-repo
  # HTTPS: https://github.com/owner/repo.git → owner-repo
  local slug
  slug=$(echo "$url" | sed -E 's#^.*[:/]([^/]+)/([^/]+?)(\.git)?$#\1-\2#')
  echo "$slug"
}

# Resolve mangled name → canonical name
resolve_canonical() {
  local mangled="$1"

  local alias_val
  alias_val=$(json_get_alias "$CONFIG_FILE" "$mangled")
  if [[ -n "$alias_val" ]]; then
    echo "$alias_val"
    return
  fi

  echo "$mangled"
}

# Reverse lookup: find local mangled name for a canonical name
find_local_for_canonical() {
  local canonical="$1"

  local mangled
  mangled=$(json_find_alias_key "$CONFIG_FILE" "$canonical")

  if [[ -n "$mangled" && -d "$PROJECTS_DIR/$mangled" ]]; then
    echo "$mangled"
    return
  fi

  # Direct match
  if [[ -d "$PROJECTS_DIR/$canonical" ]]; then
    echo "$canonical"
    return
  fi

  echo ""
}

# List all local project directories that have memory files
discover_projects() {
  [[ -d "$PROJECTS_DIR" ]] || return
  for dir in "$PROJECTS_DIR"/*/memory; do
    if [[ -d "$dir" ]]; then
      local project_dir="${dir%/memory}"
      basename "$project_dir"
    fi
  done
}

# Rebuild MEMORY.md index from the .md files present in a directory
regenerate_memory_index() {
  local memory_dir="$1"
  local index_file="$memory_dir/MEMORY.md"

  local files=()
  for f in "$memory_dir"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
    files+=("$f")
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    rm -f "$index_file"
    return
  fi

  {
    echo "# Memory Index"
    echo ""
    echo "_Auto-generated by claude-memory-sync. Do not edit manually._"
    echo ""
    for f in "${files[@]}"; do
      local name desc
      name=$(basename "$f" .md)
      desc=$(sed -n '/^---$/,/^---$/{ /^description:/{ s/^description: *//; p; } }' "$f" 2>/dev/null || true)
      if [[ -n "$desc" ]]; then
        echo "- [$name]($name.md) — $desc"
      else
        echo "- [$name]($name.md)"
      fi
    done
  } > "$index_file"
}

# --- Commands ---

cmd_setup() {
  local arg="${1:-}"
  [[ -n "$arg" ]] || die "Usage: claude-memory-sync setup <repo-url>  OR  setup --init"

  _init_json

  local sync_dir="$HOME/.claude-memory-sync"

  if [[ -d "$sync_dir/.git" ]]; then
    warn "Sync repo already exists at $sync_dir"
  elif [[ "$arg" == "--init" ]]; then
    info "Initializing new sync repo at $sync_dir..."
    mkdir -p "$sync_dir"
    git -C "$sync_dir" init 2>&1
  else
    info "Cloning sync repo to $sync_dir..."
    git clone "$arg" "$sync_dir" 2>&1
  fi

  # Generate machine ID
  local machine_id
  machine_id="$(hostname)-$(uname -s | tr '[:upper:]' '[:lower:]')"

  # Create or update config
  if [[ -f "$CONFIG_FILE" ]]; then
    warn "Config already exists at $CONFIG_FILE — updating"
    json_update_config "$CONFIG_FILE" "$sync_dir" "$machine_id"
  else
    json_create_config "$CONFIG_FILE" "$sync_dir" "$machine_id"
    info "Config created at $CONFIG_FILE"
  fi

  # Ensure repo structure
  mkdir -p "$sync_dir/projects"
  if [[ ! -f "$sync_dir/.sync-meta.json" ]]; then
    echo '{}' > "$sync_dir/.sync-meta.json"
  fi

  info ""
  info "Setup complete."
  info "  Machine ID: $machine_id"
  info "  Sync repo:  $sync_dir"
  info "  Config:     $CONFIG_FILE"
  info ""
  info "Next steps:"
  info "  1. Run 'claude-memory-sync list' to see discovered projects"
  info "  2. cd into each project and run 'claude-memory-sync alias --detect'"
  info "  3. Run 'claude-memory-sync push' to sync"
}

cmd_push() {
  _init_json
  require_config

  local sync_repo machine_id
  sync_repo=$(get_sync_repo)
  machine_id=$(get_machine_id)

  [[ -d "$sync_repo/.git" ]] || die "Sync repo not found at $sync_repo"

  # Pull latest first
  info "Pulling latest from remote..."
  git -C "$sync_repo" pull --rebase 2>&1 || warn "Pull failed — continuing with local state"

  # Discover and sync projects
  local projects
  projects=$(discover_projects) || true
  local count=0

  if [[ -z "${projects:-}" ]]; then
    info "No project memories found."
    return
  fi

  while IFS= read -r mangled; do
    local canonical
    canonical=$(resolve_canonical "$mangled")
    local local_memory="$PROJECTS_DIR/$mangled/memory"
    local repo_memory="$sync_repo/projects/$canonical/memory"

    # Check if there are any .md files (besides MEMORY.md)
    local has_files=false
    for f in "$local_memory"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
      has_files=true
      break
    done
    $has_files || continue

    info "Syncing $mangled → $canonical"
    mkdir -p "$repo_memory"

    # Copy memory files (skip MEMORY.md — regenerated)
    for f in "$local_memory"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
      cp "$f" "$repo_memory/"
    done

    # Delete files from sync repo that no longer exist locally
    for rf in "$repo_memory"/*.md; do
      [[ -f "$rf" ]] || continue
      [[ "$(basename "$rf")" == "MEMORY.md" ]] && continue
      local rf_name
      rf_name=$(basename "$rf")
      if [[ ! -f "$local_memory/$rf_name" ]]; then
        rm "$rf"
        info "  Deleted (removed locally): $rf_name"
      fi
    done

    # Regenerate index in sync repo
    regenerate_memory_index "$repo_memory"

    count=$((count + 1))
  done <<< "$projects"

  # Update sync metadata
  local meta_file="$sync_repo/.sync-meta.json"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  json_update_meta "$meta_file" "$machine_id" "$ts"

  # Commit and push
  git -C "$sync_repo" add -A
  if git -C "$sync_repo" diff --cached --quiet; then
    info "No changes to push."
  else
    git -C "$sync_repo" commit -m "sync from $machine_id — $ts" 2>&1
    info "Pushing..."
    git -C "$sync_repo" push 2>&1 || warn "Push failed — changes committed locally"
    info "Pushed $count project(s)."
  fi
}

cmd_pull() {
  _init_json
  require_config

  local sync_repo
  sync_repo=$(get_sync_repo)

  [[ -d "$sync_repo/.git" ]] || die "Sync repo not found at $sync_repo"

  info "Pulling from remote..."
  git -C "$sync_repo" pull --rebase 2>&1 || die "Pull failed"

  local count=0
  local projects_dir="$sync_repo/projects"

  [[ -d "$projects_dir" ]] || { info "No projects in sync repo."; return; }

  for canonical_dir in "$projects_dir"/*/; do
    [[ -d "$canonical_dir" ]] || continue
    local canonical
    canonical=$(basename "$canonical_dir")
    local repo_memory="$canonical_dir/memory"
    [[ -d "$repo_memory" ]] || continue

    # Find local project for this canonical name
    local mangled
    mangled=$(find_local_for_canonical "$canonical")

    if [[ -z "$mangled" ]]; then
      mangled="$canonical"
      info "No local mapping for $canonical — creating as $canonical (run 'alias' to remap)"
    fi

    local local_memory="$PROJECTS_DIR/$mangled/memory"
    mkdir -p "$local_memory"

    info "Pulling $canonical → $mangled"

    # Copy memory files (skip MEMORY.md — regenerated)
    for f in "$repo_memory"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
      cp "$f" "$local_memory/"
    done

    # Regenerate local index
    regenerate_memory_index "$local_memory"

    count=$((count + 1))
  done

  info "Pulled $count project(s)."
}

cmd_status() {
  _init_json
  require_config

  local sync_repo machine_id
  sync_repo=$(get_sync_repo)
  machine_id=$(get_machine_id)

  echo "Machine:   $machine_id"
  echo "Sync repo: $sync_repo"
  echo "Config:    $CONFIG_FILE"
  echo ""

  if [[ -d "$sync_repo/.git" ]]; then
    local meta_file="$sync_repo/.sync-meta.json"
    if [[ -f "$meta_file" ]]; then
      local formatted
      formatted=$(json_format_last_sync "$meta_file")
      if [[ -n "$formatted" ]]; then
        echo "Last sync: $formatted"
      else
        echo "Last sync: never"
      fi
    else
      echo "Last sync: never"
    fi

    echo ""
    echo "Remote status:"
    git -C "$sync_repo" fetch --quiet 2>/dev/null || true
    git -C "$sync_repo" status --short --branch
  else
    echo "Sync repo not found at $sync_repo"
  fi
}

cmd_list() {
  _init_json
  require_config

  local projects
  projects=$(discover_projects) || true

  if [[ -z "${projects:-}" ]]; then
    echo "No project memories found under $PROJECTS_DIR"
    return
  fi

  echo "Discovered project memories:"
  echo ""
  printf "  %-45s %s\n" "LOCAL NAME" "CANONICAL ALIAS"
  printf "  %-45s %s\n" "----------" "---------------"

  while IFS= read -r mangled; do
    local canonical
    canonical=$(resolve_canonical "$mangled")
    local marker=""
    if [[ "$canonical" == "$mangled" ]]; then
      marker=" (no alias)"
    fi
    printf "  %-45s %s%s\n" "$mangled" "$canonical" "$marker"
  done <<< "$projects"
}

cmd_alias() {
  _init_json
  require_config

  if [[ "${1:-}" == "--detect" ]]; then
    local project_path="${2:-$(pwd)}"
    project_path=$(cd "$project_path" && pwd)

    # Compute mangled name
    local mangled
    mangled=$(mangle_path "$project_path")

    # Try git remote for canonical name
    local canonical=""
    if [[ -d "$project_path/.git" ]]; then
      local remote_url
      remote_url=$(git -C "$project_path" remote get-url origin 2>/dev/null || true)
      if [[ -n "$remote_url" ]]; then
        canonical=$(slugify_remote "$remote_url")
      fi
    fi

    if [[ -z "$canonical" ]]; then
      canonical=$(basename "$project_path")
      warn "No git remote found — using directory name: $canonical"
    fi

    json_set_alias "$CONFIG_FILE" "$mangled" "$canonical"
    info "Alias set: $mangled → $canonical"
    return
  fi

  local mangled="${1:-}"
  local canonical="${2:-}"

  [[ -n "$mangled" && -n "$canonical" ]] || die "Usage: claude-memory-sync alias <mangled-name> <canonical>  OR  alias --detect [path]"

  json_set_alias "$CONFIG_FILE" "$mangled" "$canonical"
  info "Alias set: $mangled → $canonical"
}

# --- Main ---

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    setup)     cmd_setup "$@" ;;
    sync)      cmd_push "$@"; cmd_pull "$@" ;;
    push)      cmd_push "$@" ;;
    pull)      cmd_pull "$@" ;;
    status)    cmd_status "$@" ;;
    list)      cmd_list "$@" ;;
    alias)     cmd_alias "$@" ;;
    --version|-v) echo "claude-memory-sync $VERSION" ;;
    --help|-h|"") usage ;;
    *)         die "Unknown command: $cmd — run --help for usage" ;;
  esac
}

main "$@"
