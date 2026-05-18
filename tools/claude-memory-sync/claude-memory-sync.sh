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
  sync [--delete] [--force]         Push then pull (full round-trip)
  push [--delete] [--force]         Push local memories to sync repo (additive by default)
  pull [--delete] [--force]         Pull memories from sync repo to local (additive by default)
  status                            Show sync status
  doctor                            Run health checks against config, aliases, and repo state
  list                              List discovered projects and aliases
  alias <mangled-name> <canonical>  Set a manual alias
  alias --detect [project-path]     Auto-detect alias from git remote

Push/pull flags:
  --delete                          Propagate deletions (push: to repo; pull: from local). Files move to .trash/ for recovery.
  --force                           Skip the 3-file safety threshold for --delete

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

# Soft-delete: move a file into <sync_repo>/.trash/<canonical>/<timestamp>-<name>
# so a botched sync run can be recovered without git surgery. Used by both
# push --delete (repo-side) and pull --delete (local-side).
move_to_trash() {
  local file_path="$1" sync_repo="$2" canonical="$3"
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  local trash_dir="$sync_repo/.trash/$canonical"
  mkdir -p "$trash_dir"
  local name
  name=$(basename "$file_path")
  mv "$file_path" "$trash_dir/$ts-$name"

  # Ensure .trash/ is gitignored. Lazy-create on first trash usage.
  local gitignore="$sync_repo/.gitignore"
  if [[ ! -f "$gitignore" ]]; then
    echo ".trash/" > "$gitignore"
  elif ! grep -qxF ".trash/" "$gitignore"; then
    echo ".trash/" >> "$gitignore"
  fi
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

  # Push is additive by default; deletion is opt-in.
  local allow_delete=false force=false
  local delete_threshold=3
  for arg in "$@"; do
    case "$arg" in
      --delete) allow_delete=true ;;
      --force)  force=true ;;
    esac
  done

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

  # Phase 1: gather pending deletions across all projects so we can threshold-check
  # BEFORE moving anything. Aborting mid-run would leave the repo half-modified.
  # Format per line: <canonical>|<filepath>|<filename>
  local pending_deletes=()
  while IFS= read -r mangled; do
    local canonical
    canonical=$(resolve_canonical "$mangled")
    local local_memory="$PROJECTS_DIR/$mangled/memory"
    local repo_memory="$sync_repo/projects/$canonical/memory"
    [[ -d "$repo_memory" ]] || continue

    for rf in "$repo_memory"/*.md; do
      [[ -f "$rf" ]] || continue
      local rf_name
      rf_name=$(basename "$rf")
      [[ "$rf_name" == "MEMORY.md" ]] && continue
      if [[ ! -f "$local_memory/$rf_name" ]]; then
        pending_deletes+=("$canonical|$rf|$rf_name")
      fi
    done
  done <<< "$projects"

  if [[ ${#pending_deletes[@]} -gt 0 ]]; then
    if ! $allow_delete; then
      warn "Push is additive by default. ${#pending_deletes[@]} file(s) exist in the repo but not locally:"
      for d in "${pending_deletes[@]}"; do
        IFS='|' read -r d_canon _ d_name <<< "$d"
        echo "    $d_canon/$d_name"
      done
      warn "To propagate these deletions, re-run with --delete (files move to .trash/ for recovery)."
    elif [[ ${#pending_deletes[@]} -gt $delete_threshold ]] && ! $force; then
      die "Refusing to delete ${#pending_deletes[@]} files (threshold: $delete_threshold). This usually means a misconfigured alias or empty local dir. Inspect the list above, then re-run with --delete --force if you're sure."
    fi
  fi

  while IFS= read -r mangled; do
    local canonical
    canonical=$(resolve_canonical "$mangled")
    local local_memory="$PROJECTS_DIR/$mangled/memory"
    local repo_memory="$sync_repo/projects/$canonical/memory"

    info "Syncing $mangled → $canonical"
    mkdir -p "$repo_memory"

    # Copy local memory files to sync repo (skip MEMORY.md — regenerated)
    for f in "$local_memory"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
      cp "$f" "$repo_memory/"
    done

    # Soft-delete to .trash/ — only when user explicitly opted in via --delete.
    if $allow_delete; then
      for d in "${pending_deletes[@]}"; do
        IFS='|' read -r d_canon d_path d_name <<< "$d"
        [[ "$d_canon" == "$canonical" ]] || continue
        move_to_trash "$d_path" "$sync_repo" "$canonical"
        info "  Trashed (removed locally): $d_name"
      done
    fi

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
    if git -C "$sync_repo" push 2>&1; then
      info "Pushed $count project(s)."
    else
      warn "Push failed — changes committed locally"
    fi
  fi
}

cmd_pull() {
  _init_json
  require_config

  local sync_repo
  sync_repo=$(get_sync_repo)

  [[ -d "$sync_repo/.git" ]] || die "Sync repo not found at $sync_repo"

  # Pull is additive by default; deletion is opt-in (symmetric with push).
  local allow_delete=false force=false
  local delete_threshold=3
  for arg in "$@"; do
    case "$arg" in
      --delete) allow_delete=true ;;
      --force)  force=true ;;
    esac
  done

  info "Pulling from remote..."
  git -C "$sync_repo" pull --rebase 2>&1 || die "Pull failed"

  local count=0
  local projects_dir="$sync_repo/projects"

  [[ -d "$projects_dir" ]] || { info "No projects in sync repo."; return; }

  # Phase 1: gather pending local deletions across all projects.
  # Format per line: <canonical>|<filepath>|<filename>
  local pending_deletes=()
  for canonical_dir in "$projects_dir"/*/; do
    [[ -d "$canonical_dir" ]] || continue
    local canonical
    canonical=$(basename "$canonical_dir")
    local repo_memory="$canonical_dir/memory"
    [[ -d "$repo_memory" ]] || continue

    local mangled
    mangled=$(find_local_for_canonical "$canonical")
    [[ -n "$mangled" ]] || continue
    local local_memory="$PROJECTS_DIR/$mangled/memory"
    [[ -d "$local_memory" ]] || continue

    for lf in "$local_memory"/*.md; do
      [[ -f "$lf" ]] || continue
      local lf_name
      lf_name=$(basename "$lf")
      [[ "$lf_name" == "MEMORY.md" ]] && continue
      if [[ ! -f "$repo_memory/$lf_name" ]]; then
        pending_deletes+=("$canonical|$lf|$lf_name")
      fi
    done
  done

  if [[ ${#pending_deletes[@]} -gt 0 ]]; then
    if ! $allow_delete; then
      warn "Pull is additive by default. ${#pending_deletes[@]} local file(s) are not in the repo:"
      for d in "${pending_deletes[@]}"; do
        IFS='|' read -r d_canon _ d_name <<< "$d"
        echo "    $d_canon/$d_name"
      done
      warn "To accept upstream deletions, re-run with --delete (files move to .trash/ for recovery)."
    elif [[ ${#pending_deletes[@]} -gt $delete_threshold ]] && ! $force; then
      die "Refusing to delete ${#pending_deletes[@]} local files (threshold: $delete_threshold). Inspect the list above, then re-run with --delete --force if you're sure."
    fi
  fi

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

    # Copy files from sync repo to local (skip MEMORY.md — regenerated)
    for f in "$repo_memory"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
      cp "$f" "$local_memory/"
    done

    # Soft-delete to .trash/ — only when user explicitly opted in via --delete.
    if $allow_delete; then
      for d in "${pending_deletes[@]}"; do
        IFS='|' read -r d_canon d_path d_name <<< "$d"
        [[ "$d_canon" == "$canonical" ]] || continue
        move_to_trash "$d_path" "$sync_repo" "$canonical"
        info "  Trashed (removed upstream): $d_name"
      done
    fi

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

cmd_doctor() {
  _init_json
  require_config

  local sync_repo machine_id
  sync_repo=$(get_sync_repo)
  machine_id=$(get_machine_id)
  local issues=0

  local C_OK C_WARN C_FAIL C_HEAD C_OFF
  if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'; C_HEAD=$'\033[36m'; C_OFF=$'\033[0m'
  else
    C_OK=""; C_WARN=""; C_FAIL=""; C_HEAD=""; C_OFF=""
  fi
  check_ok()   { echo "  ${C_OK}[ok]${C_OFF} $*"; }
  check_warn() { echo "  ${C_WARN}[!! ]${C_OFF} $*"; issues=$((issues + 1)); }
  check_fail() { echo "  ${C_FAIL}[XX]${C_OFF} $*"; issues=$((issues + 1)); }

  echo
  echo "${C_HEAD}Config${C_OFF}"
  check_ok "Config file: $CONFIG_FILE"
  if [[ -n "$machine_id" ]]; then check_ok "machine_id: $machine_id"; else check_fail "machine_id missing"; fi
  if [[ -d "$sync_repo/.git" ]]; then check_ok "sync_repo: $sync_repo"; else check_fail "sync_repo missing or not a git repo: $sync_repo"; fi

  echo
  echo "${C_HEAD}Aliases${C_OFF}"
  # List aliases via json backend (works for both jq and python3)
  local aliases_tsv
  if [[ "$_JSON_CMD" == "jq" ]]; then
    aliases_tsv=$(jq -r '.aliases // {} | to_entries[] | "\(.key)\t\(.value)"' "$CONFIG_FILE" 2>/dev/null || echo "")
  else
    aliases_tsv=$("$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
for k, v in d.get('aliases', {}).items():
    print(f'{k}\t{v}')
" "$CONFIG_FILE" 2>/dev/null || echo "")
  fi

  if [[ -z "$aliases_tsv" ]]; then
    check_warn "No aliases defined"
  else
    declare -A value_counts=()
    while IFS=$'\t' read -r key val; do
      [[ -z "$key" ]] && continue
      value_counts["$val"]="${value_counts["$val"]:+${value_counts["$val"]}, }$key"
      if [[ -d "$PROJECTS_DIR/$key" ]]; then
        check_ok "$key -> $val"
      else
        check_warn "$key -> $val: local dir does not exist"
      fi
    done <<< "$aliases_tsv"

    for val in "${!value_counts[@]}"; do
      local keys="${value_counts[$val]}"
      if [[ "$keys" == *", "* ]]; then
        check_warn "Multiple aliases -> '$val': $keys (reverse lookup may pick the wrong one)"
      fi
    done
  fi

  echo
  echo "${C_HEAD}Local projects${C_OFF}"
  if [[ -d "$PROJECTS_DIR" ]]; then
    local unaliased=()
    for d in "$PROJECTS_DIR"/*/memory; do
      [[ -d "$d" ]] || continue
      local proj
      proj=$(basename "$(dirname "$d")")
      local resolved
      resolved=$(resolve_canonical "$proj")
      # An unaliased project resolves to itself
      if [[ "$resolved" == "$proj" ]]; then
        # But it might still be the direct-match case; check if it's named in aliases as key
        local has_alias_key
        if [[ "$_JSON_CMD" == "jq" ]]; then
          has_alias_key=$(jq -r --arg k "$proj" '.aliases // {} | has($k)' "$CONFIG_FILE")
        else
          has_alias_key=$("$_JSON_CMD" -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
print('true' if sys.argv[2] in d.get('aliases', {}) else 'false')
" "$CONFIG_FILE" "$proj")
        fi
        [[ "$has_alias_key" == "true" ]] || unaliased+=("$proj")
      fi
    done
    if [[ ${#unaliased[@]} -eq 0 ]]; then
      check_ok "All local projects with memory/ are aliased"
    else
      for n in "${unaliased[@]}"; do
        check_warn "$n has memory/ but no alias (will sync under raw name)"
      done
    fi
  fi

  echo
  echo "${C_HEAD}Canonical names in repo${C_OFF}"
  local repo_projects="$sync_repo/projects"
  if [[ -d "$repo_projects" ]]; then
    local unmapped=()
    for d in "$repo_projects"/*/; do
      [[ -d "$d" ]] || continue
      local canon
      canon=$(basename "$d")
      local local_name
      local_name=$(find_local_for_canonical "$canon")
      [[ -z "$local_name" ]] && unmapped+=("$canon")
    done
    if [[ ${#unmapped[@]} -eq 0 ]]; then
      check_ok "All canonical names resolve to a local dir"
    else
      for n in "${unmapped[@]}"; do
        check_warn "Canonical '$n' has no local mapping (next pull will create '$n' locally)"
      done
    fi
  fi

  echo
  echo "${C_HEAD}Sync repo state${C_OFF}"
  local branch
  branch=$(git -C "$sync_repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    check_ok "On branch $branch"
  else
    check_warn "On non-default branch '$branch' (expected main/master)"
  fi
  git -C "$sync_repo" fetch --quiet 2>/dev/null || true
  local ahead behind
  ahead=$(git -C "$sync_repo" rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  behind=$(git -C "$sync_repo" rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
  if [[ "$ahead" -gt 0 ]]; then check_warn "$ahead commit(s) ahead of remote (unpushed)"; fi
  if [[ "$behind" -gt 0 ]]; then check_warn "$behind commit(s) behind remote (unpulled)"; fi
  if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then check_ok "In sync with remote"; fi

  echo
  echo "${C_HEAD}Trash${C_OFF}"
  local trash_dir="$sync_repo/.trash"
  if [[ -d "$trash_dir" ]]; then
    local trash_count
    trash_count=$(find "$trash_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$trash_count" -gt 0 ]]; then
      check_warn "$trash_count recoverable file(s) in .trash/ (review and clean manually)"
    else
      check_ok ".trash/ is empty"
    fi
  else
    check_ok ".trash/ does not exist (nothing has been deleted)"
  fi

  echo
  echo "${C_HEAD}Last sync${C_OFF}"
  local meta_file="$sync_repo/.sync-meta.json"
  if [[ -f "$meta_file" ]]; then
    local formatted
    formatted=$(json_format_last_sync "$meta_file" || echo "")
    if [[ -n "$formatted" ]]; then
      check_ok "$formatted"
    fi
  fi

  echo
  if [[ "$issues" -eq 0 ]]; then
    echo "${C_OK}All checks passed.${C_OFF}"
  else
    echo "${C_WARN}$issues issue(s) found. Review the warnings above.${C_OFF}"
  fi
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
    doctor)    cmd_doctor "$@" ;;
    list)      cmd_list "$@" ;;
    alias)     cmd_alias "$@" ;;
    --version|-v) echo "claude-memory-sync $VERSION" ;;
    --help|-h|"") usage ;;
    *)         die "Unknown command: $cmd — run --help for usage" ;;
  esac
}

main "$@"
