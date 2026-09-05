---
name: merge
description: >
  Squash-merge the current PR and update all project documentation in
  one step. Use when the user wants to merge a PR, says "merge this",
  "squash and merge", "merge and update docs", or is done with a
  feature branch and ready to merge into the default branch.
---

# Merge & Document

Squash-merge the current PR and update project documentation. This skill is driver-neutral: the **primary driver** is whichever agent is executing it (Claude Code, Codex App, or Codex CLI). Follow these steps exactly.

## When to Invoke

- When the user runs `/merge` on a branch with an open PR
- When the user wants to squash-merge and update docs in one step

## Prerequisites

- **git** — required.
- **GitHub access** — either `gh` (authenticated) or GitHub MCP tools available in the runtime. Step 1 detects which one is present. Stop only if neither is available.

---

## Runtime Adapter

Use the primary driver's native file-read and file-edit capabilities for documentation updates, and standalone shell commands for git operations. Claude Code may use Read/Write/Edit/Bash; Codex may use native file/edit/shell tools. Do not require subagents.

---

## GitHub Access Modes

`gh` is not always installed. Claude Code on the web and other remote containers run without it and expose GitHub MCP tools instead. Detect the mode once in Step 1, store it as `GH_MODE`, and use the matching column below for every GitHub operation in this skill. Both modes cover everything the skill needs.

| Operation | `GH_MODE = cli` | `GH_MODE = mcp` |
|-----------|-----------------|-----------------|
| Repo identity | `gh repo view --json nameWithOwner` | `git -C "${PROJECT_ROOT}" remote get-url origin`, then parse `<owner>/<repo>` natively |
| Default branch | `gh repo view --json defaultBranchRef` | `git -C "${PROJECT_ROOT}" symbolic-ref --quiet refs/remotes/origin/HEAD`, then parse the trailing name; if it fails, use the PR's base branch |
| PR for current branch | `gh pr view --json number,title,state,mergeable,baseRefName,headRefName` | `list_pull_requests` with `state: "open"` and `head: "<owner>:<branch>"`, then `pull_request_read` with `method: "get"` |
| Squash-merge | `gh pr merge <number> --squash --delete-branch` | `merge_pull_request` with `merge_method: "squash"`, then `git -C "${PROJECT_ROOT}" push origin --delete <branch-name>` |
| Squash commit SHA | `gh pr view <number> --json mergeCommit` (read `mergeCommit.oid`) | `pull_request_read` with `method: "get"` (read `merge_commit_sha`) |
| Merged PR list | `gh pr list --state merged --limit 30 --json number,headRefName,headRefOid,mergeCommit` | `list_pull_requests` with `state: "closed"`, keeping entries whose `merged_at` is set |
| Open PR list | `gh pr list --state open --json number,headRefName` | `list_pull_requests` with `state: "open"` |

Parse all JSON natively — never pipe to `jq`.

MCP tool calls take `owner`, `repo`, and `pullNumber` from the values stored in Step 1. Tool names differ slightly between GitHub MCP server versions. If a name in this table is missing from the runtime, use the closest equivalent it exposes and record the substitution in the Step 7 summary.

---

## Agent Instructions

When invoked, execute the following steps sequentially.

---

### Step 1: Preflight

Run ALL checks — stop if any fail:

```bash
git rev-parse --is-inside-work-tree
```
```bash
git rev-parse --show-toplevel
```

Store the toplevel path as `PROJECT_ROOT`. **Shell safety rules for the entire skill:**
- **Never use `cd`** — use `git -C "${PROJECT_ROOT}"` and absolute paths
- **Never use `$()`** command substitution, and never export shell variables. Run each command standalone, read its output, and paste the literal value — SHA, branch name, PR number — into the next command. Names such as `${PROJECT_ROOT}` and `${TARGET_BRANCH}` in this file are placeholders for values you substitute yourself
- The only pipes in this skill are the two `git diff ... | git patch-id --stable` commands in Steps 6 and 6b. Both sides are git; no other command may be piped

**Detect GitHub access mode:**

```bash
gh auth status
```

- Succeeds → store `GH_MODE = cli`
- `gh` missing or not authenticated → check the runtime's tool list for GitHub MCP tools (`pull_request_read`, `merge_pull_request`, `list_pull_requests`). Present → store `GH_MODE = mcp`
- Neither available → stop: "No GitHub access. Run `gh auth login`, or enable the GitHub MCP server."

**Resolve repo identity** using the GitHub Access table. Store the owner as `OWNER` and the repository name as `REPO`.

**Detect the default branch** using the GitHub Access table. Store as `DEFAULT_BRANCH`.

```bash
git rev-parse --abbrev-ref HEAD
```
- Equals `DEFAULT_BRANCH` → stop: "Switch to the feature branch you want to merge."

Store the current branch name as `BRANCH`.

```bash
git status --porcelain
```
- Non-empty → stop: "Working tree is not clean. Commit or stash changes first."

**Detect shallow history** — remote containers often clone with `--depth`:

```bash
git -C "${PROJECT_ROOT}" rev-parse --is-shallow-repository
```

- `true` → store `SHALLOW = true`. Step 6 deepens history before verifying anything, and keeps any branch it cannot verify

**Find the PR for the current branch** using the GitHub Access table:

```bash
gh pr view --json number,title,state,mergeable,baseRefName,headRefName
```

- No PR found → stop: "No PR found for this branch. Create one first."
- State is not `OPEN` → stop: "PR is not open (state: {state})."
- Mergeable is `CONFLICTING` → stop: "PR has merge conflicts. Resolve them before merging."

In MCP mode, `list_pull_requests` returning an empty array is the same as "no PR found"; `pull_request_read` supplies `state`, `mergeable`, and `base.ref`.

Parse JSON natively. Store the PR number as `PR_NUMBER` and `baseRefName` as `TARGET_BRANCH` — this is the branch the PR merges into (may differ from the repo default branch in release/hotfix flows).

Present the PR number, title, target branch, and detected `GH_MODE` to the user, then proceed to Step 2.

---

### Step 2: Squash-Merge

```bash
gh pr merge <number> --squash --delete-branch
```

The `--delete-branch` flag removes the remote branch after merge, preventing stale remote branches from accumulating. It does not touch the local branch — Step 6 handles that.

In MCP mode, call `merge_pull_request` with `merge_method: "squash"`, then delete the remote branch explicitly:

```bash
git -C "${PROJECT_ROOT}" push origin --delete <branch-name>
```

If that push reports the remote ref does not exist, the repository already auto-deletes merged branches — continue.

If the merge fails:
- **Merge conflict** → STOP and report the conflict details to the user. Do NOT attempt to resolve conflicts without user input.
- **CI checks failing** → Report which checks failed and recommend waiting for CI to pass. Only mention `gh pr merge --squash --delete-branch --admin` as a last resort — warn that it bypasses branch protection and could merge broken code. In MCP mode there is no admin override; report the failing checks and stop.
- **Any other error** → Report the exact error message and stop. In MCP mode, report the tool's error body verbatim.

---

### Step 3: Switch to Target Branch

```bash
git -C "${PROJECT_ROOT}" checkout "${TARGET_BRANCH}"
```

```bash
git -C "${PROJECT_ROOT}" pull
```

Verify the merge commit is present:

```bash
git -C "${PROJECT_ROOT}" log --oneline -1
```

---

### Step 4: Update Documentation

Read each file before editing. Only update files that exist — do NOT create new files in this step.

**README.md** — If the merged PR added, removed, or changed a feature that the README describes, update the relevant sections. Skip if the PR was an internal refactor with no user-facing changes.

**CHANGELOG.md** — If the file exists, add an entry under the appropriate section (Added, Changed, Fixed, Removed). Use the PR title and number as the entry. Skip if no CHANGELOG exists.

**Agent guidance docs** — If the merged PR introduced new patterns, conventions, architectural decisions, or learnings, update existing guidance files such as `AGENTS.md`, `CLAUDE.md`, or equivalent local agent docs. Skip if nothing changed.

**Other tracking docs** — If the project has a roadmap, TODO, or project board doc, update it to reflect the completed work.

---

### Step 5: Commit and Push Doc Updates

Only if files were actually modified in Step 4:

Run each as a separate command:

```bash
git -C "${PROJECT_ROOT}" add <specific files changed>
```
```bash
git -C "${PROJECT_ROOT}" commit -m "docs: update project docs after merging PR #<number>"
```
```bash
git -C "${PROJECT_ROOT}" push
```

If no docs needed updating, skip this step entirely. Do NOT create empty commits.

---

### Step 6: Verify and Delete the Merged Branch

A squash merge writes a **new** commit on the target branch. The feature branch head never becomes an ancestor of the target, so `git branch -d` and `git branch --merged` — both of which test ancestry — refuse the branch every single time. Ancestry cannot prove a squash merge. Prove it with **content** instead, then delete on that proof.

Work through the three stages in order. Substitute every value by hand: run a command, read its output, paste the literal SHA or name into the next command.

#### Stage 1: Preconditions

Check whether the branch exists locally:

```bash
git -C "${PROJECT_ROOT}" rev-parse --verify --quiet refs/heads/<branch-name>
```

- Prints nothing and exits non-zero → the branch is **absent**. This is normal after a fresh container clone, where the merged branch was never checked out. Record "absent — nothing to delete" and go to Step 6b. Do NOT report this as an error.
- Prints a SHA → record it as `BRANCH_HEAD` and continue.

Check whether any worktree has it checked out:

```bash
git -C "${PROJECT_ROOT}" worktree list --porcelain
```

Collect every `branch refs/heads/<name>` line. If `<branch-name>` appears, record "kept — checked out in a worktree" and go to Step 6b. A branch checked out in any worktree is never deleted, whatever the content evidence says.

If `SHALLOW = true`, the history needed for verification is missing. Deepen it:

```bash
git -C "${PROJECT_ROOT}" fetch --deepen 200 origin
```

If the fetch fails, record "kept — unverified (shallow history)" and go to Step 6b. Never delete on absent evidence.

#### Stage 2: Gather Evidence

Get the squash commit SHA on the target branch using the GitHub Access table:

```bash
gh pr view <number> --json mergeCommit
```

Read `mergeCommit.oid` (`merge_commit_sha` in MCP mode). If it is empty — the API occasionally lags immediately after a merge — fall back to a message search, since GitHub's default squash subject ends with the PR number:

```bash
git -C "${PROJECT_ROOT}" log --fixed-strings --grep "(#<number>)" --max-count 1 --format=%H "${TARGET_BRANCH}"
```

Neither source yields a SHA → record "kept — unverified (no squash commit found)" and go to Step 6b. Otherwise store it as `SQUASH_SHA`.

Confirm the squash commit is in local history:

```bash
git -C "${PROJECT_ROOT}" merge-base --is-ancestor <squash-sha> "${TARGET_BRANCH}"
```

Exit 0 → present. Non-zero → run `git -C "${PROJECT_ROOT}" fetch origin "${TARGET_BRANCH}"` and retry once. Still non-zero → record "kept — unverified (squash commit not in local history)" and go to Step 6b.

Fetch the PR head into a temporary ref:

```bash
git -C "${PROJECT_ROOT}" fetch origin "refs/pull/<number>/head:refs/prheads/<number>"
```

If this fails — no network, or a fork whose PR refs are restricted — record "kept — unverified (PR head unavailable)" and go to Step 6b.

```bash
git -C "${PROJECT_ROOT}" rev-parse refs/prheads/<number>
```

Record as `PR_HEAD`. If `PR_HEAD` differs from `BRANCH_HEAD`, the local branch carries commits the PR never had, or trails behind it. Verify `BRANCH_HEAD` — that is what deletion would discard — and say so in the report.

Compute the merge base:

```bash
git -C "${PROJECT_ROOT}" merge-base <branch-head> "${TARGET_BRANCH}"
```

Record as `MERGE_BASE`. Now compare what the branch contains against what the squash commit landed:

```bash
git -C "${PROJECT_ROOT}" diff <merge-base> <branch-head> | git patch-id --stable
```
```bash
git -C "${PROJECT_ROOT}" diff <squash-sha>^ <squash-sha> | git patch-id --stable
```

Each prints two fields: `<patch-id> <commit-id>`. Compare **only the first field**. The second is a commit id, is all zeros for a plain diff, and never matches — it is not part of the test.

These are the only two pipes in this skill. Both sides are git, there is no shell variable and no `$()`, and the form is identical in bash and PowerShell. `git patch-id` ignores whitespace and line numbers, so a rebase, a reindent, or CRLF translation between the branch and the squash commit does not break equality. `git patch-id` ships with git on every platform — no extra tooling.

#### Stage 3: Verdict

**First fields equal** → the branch content is exactly what landed on the target. Delete it:

```bash
git -C "${PROJECT_ROOT}" branch -D <branch-name>
```

`-D` is required here. `-d` tests ancestry and refuses every squash-merged branch. The patch-id equality plus the worktree check in Stage 1 is the proof that makes `-D` safe — never run it without both.

**First fields differ** → keep the branch and report what is unaccounted for:

```bash
git -C "${PROJECT_ROOT}" log --oneline "${TARGET_BRANCH}..<branch-name>"
```
```bash
git -C "${PROJECT_ROOT}" diff --stat "${TARGET_BRANCH}...<branch-name>"
```

Tell the user which commits and files the target does not carry. Do not delete, and do not offer to force it.

Remove the temporary ref either way, including after a failed verification:

```bash
git -C "${PROJECT_ROOT}" update-ref -d "refs/prheads/<number>"
```

---

### Step 6b: Repo-Wide Branch Sweep

The PR's own branch is not the only branch that goes stale. A branch pointing at the same head under a different name, or a one-commit branch that never got a PR, is invisible to Step 6 and accumulates silently. After the merged branch is settled, classify **every** remaining local branch.

Enumerate them with their head SHAs:

```bash
git -C "${PROJECT_ROOT}" for-each-ref --format="%(refname:short) %(objectname)" refs/heads
```

Two branches printing the same object name are two names for one head. Classify the first, then apply the identical verdict to the other — this is how a `codex/...` branch pointing at some PR's head gets reconciled even though it was never that PR's branch.

Build the protected set first. These are never deleted, whatever the content says:

- every branch on a `branch refs/heads/<name>` line of `git -C "${PROJECT_ROOT}" worktree list --porcelain`
- `TARGET_BRANCH` and `DEFAULT_BRANCH`
- every branch with an open PR (`gh pr list --state open --json number,headRefName`, or `list_pull_requests` with `state: "open"`)

Classify each remaining branch:

| Class | Test | Action |
|-------|------|--------|
| (a) Ancestor of target | `git -C "${PROJECT_ROOT}" merge-base --is-ancestor <branch-sha> "${TARGET_BRANCH}"` exits 0 | Delete with `git -C "${PROJECT_ROOT}" branch -d <branch-name>` — ancestry is proof on its own |
| (b) Squashed into target | Patch-id equality, or blob equality for every touched file, as below | Delete with `git -C "${PROJECT_ROOT}" branch -D <branch-name>` |
| (c) Unique content | Neither test passes | Keep, and report the commits and files the target does not carry |
| (d) Checked out in a worktree | Listed by `git worktree list --porcelain` | Keep, always — do not even evaluate its content |

**Branches that map to a PR.** Fetch the merged PR list from the GitHub Access table, then match a branch to a PR by, in order:

1. `headRefName` equals the branch name.
2. `headRefOid` equals the branch's object name from `for-each-ref` — this catches a branch that was never the PR's branch but points at the same commit.

On a match, run the Stage 2 and Stage 3 procedure with that PR's number and merge commit, then delete the temporary ref.

**Branches with no PR at all.** There is no squash commit to compare against, so compare file contents directly. List what the branch touched:

```bash
git -C "${PROJECT_ROOT}" diff --name-only "${TARGET_BRANCH}...<branch-name>"
```

Then, for each path, compare blob hashes:

```bash
git -C "${PROJECT_ROOT}" rev-parse "<branch-name>:<path>"
```
```bash
git -C "${PROJECT_ROOT}" rev-parse "${TARGET_BRANCH}:<path>"
```

Identical hashes mean the file content is already on the target, byte for byte.

- Every touched path matches → class (b). The work reached the target under a different commit. Delete with `-D`.
- Any path differs, or `rev-parse` fails because the target has no such file → class (c). Keep the branch and report every path that did not match. When a path looks superseded rather than lost — the target carries a rewritten or relocated version of it — say exactly that, name both locations, and let the user decide. Do not delete on your own judgment that content "looks superseded".

Report each deletion and each retention as you go, with the evidence that decided it.

---

### Step 7: Summary

Report to the user:

- Which PR was merged (number and title), and the squash commit SHA
- Which docs were updated (list the files) or "No doc updates needed"
- The merged branch's outcome — deleted (with the matching patch id), absent, or kept with the reason
- Any MCP tool substitutions made under `GH_MODE = mcp`

Then print the **branch inventory** — every local branch that still exists and why it is still there:

| Branch | Class | Evidence | Kept because |
|--------|-------|----------|--------------|
| `main` | target | — | Target branch |
| `feat/sender-rules` | unique content | 2 commits, 3 files not on target | Not merged anywhere |
| `wip/spike` | checked out | worktree at `../spike` | Checked out in a worktree |
| `codex/logo` | unverified | PR head unavailable | Could not prove content landed |

List every branch, including the obviously fine ones. A branch left out of this table is a branch nobody notices for another ten merges.

---

## Rules

- Never delete a branch without content proof — patch-id equality against the squash commit, blob equality for every touched file, or plain ancestry
- `-D` is permitted only after that proof plus the worktree check; `-d` alone can never delete a squash-merged branch, because it tests ancestry and a squash merge breaks ancestry by design
- Never delete a branch that a worktree has checked out or that has an open PR, however strong the content evidence
- Never delete on absent evidence — an unreachable PR head, a missing squash commit, or an un-deepened shallow clone means "keep and mark unverified", not "assume merged"
- A branch missing from a fresh container clone is "absent", not an error
- Compare only the first field of `git patch-id` output; the second field is a commit id and never matches
- Delete `refs/prheads/*` temporary refs after every verification, including failed ones
- Detect `gh` versus GitHub MCP once in preflight and use the matching column for every GitHub call — never assume `gh` exists
- Every local branch appears in the Step 7 inventory, deleted or kept
- Do NOT run build commands — these are doc-only updates after the merge
- Do NOT modify any source code files during the doc update step
- Do NOT create new documentation files — only update existing ones
- If the merge fails for ANY reason, STOP and report — do not retry or work around it
- Always use `git add <specific files>` — never `git add -A` or `git add .`
- Read files before editing them
- **Never use `cd`** — use `git -C "${PROJECT_ROOT}"` and absolute paths
- **Never use `$()` or shell variables** — run each command standalone and paste the literal value into the next one
- **Never pipe** except the two `git diff ... | git patch-id --stable` verification commands
