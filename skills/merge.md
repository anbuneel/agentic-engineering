# Merge & Document

Squash-merge the current PR and update all project documentation. Follow these steps exactly.

## When to Invoke

- When the user runs `/merge` on a branch with an open PR
- When the user wants to squash-merge and update docs in one step

## Prerequisites

Requires **git** and **gh** (authenticated).

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
gh auth status
```
- Not authenticated → stop: "Run `gh auth login` first."

Detect the default branch:

```bash
gh repo view --json defaultBranchRef
```

Parse JSON natively to extract the default branch name. Store as `DEFAULT_BRANCH`.

```bash
git rev-parse --abbrev-ref HEAD
```
- Equals `DEFAULT_BRANCH` → stop: "Switch to the feature branch you want to merge."

```bash
git status --porcelain
```
- Non-empty → stop: "Working tree is not clean. Commit or stash changes first."

Find the PR for the current branch:

```bash
gh pr view --json number,title,state,mergeable,baseRefName
```
- No PR found → stop: "No PR found for this branch. Create one first."
- State is not `OPEN` → stop: "PR is not open (state: {state})."
- Mergeable is `CONFLICTING` → stop: "PR has merge conflicts. Resolve them before merging."

Parse JSON natively. Store `baseRefName` as `TARGET_BRANCH` — this is the branch the PR merges into (may differ from the repo default branch in release/hotfix flows).

Print the PR number, title, and target branch to the user for confirmation before proceeding.

---

### Step 2: Squash-Merge

```bash
gh pr merge --squash
```

If the merge fails:
- **Merge conflict** → STOP and report the conflict details to the user. Do NOT attempt to resolve conflicts without user input.
- **CI checks failing** → Report which checks failed. Ask the user whether to merge anyway with `gh pr merge --squash --admin` or wait.
- **Any other error** → Report the exact error message and stop.

---

### Step 3: Switch to Target Branch

```bash
git checkout ${TARGET_BRANCH}
```

```bash
git pull
```

Verify the merge commit is present:

```bash
git log --oneline -1
```

---

### Step 4: Update Documentation

Read each file before editing. Only update files that exist — do NOT create new files in this step.

**README.md** — If the merged PR added, removed, or changed a feature that the README describes, update the relevant sections. Skip if the PR was an internal refactor with no user-facing changes.

**CHANGELOG.md** — If the file exists, add an entry under the appropriate section (Added, Changed, Fixed, Removed). Use the PR title and number as the entry. Skip if no CHANGELOG exists.

**CLAUDE.md** — If the merged PR introduced new patterns, conventions, architectural decisions, or learnings, add them. Skip if nothing changed.

**Other tracking docs** — If the project has a roadmap, TODO, or project board doc, update it to reflect the completed work.

---

### Step 5: Commit and Push Doc Updates

Only if files were actually modified in Step 4:

```bash
git add <specific files changed>
git commit -m "docs: update project docs after merging PR #<number>"
git push
```

If no docs needed updating, skip this step entirely. Do NOT create empty commits.

---

### Step 6: Clean Up

Delete the merged branch locally if it still exists:

```bash
git branch -d <branch-name>
```

Use `-d` (safe delete), NOT `-D`. If the branch isn't fully merged for some reason, report it instead of force-deleting.

---

### Step 7: Summary

Report to the user:
- Which PR was merged (number and title)
- Which docs were updated (list the files) or "No doc updates needed"
- Confirm the branch was cleaned up

---

## Rules

- Do NOT run build commands — these are doc-only updates after the merge
- Do NOT modify any source code files during the doc update step
- Do NOT create new documentation files — only update existing ones
- Do NOT force-delete branches — use `git branch -d` only
- If the merge fails for ANY reason, STOP and report — do not retry or work around it
- Always use `git add <specific files>` — never `git add -A` or `git add .`
- Read files before editing them
