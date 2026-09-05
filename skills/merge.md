---
name: merge
description: >
  Squash-merge the current PR and update all project documentation in
  one step. Use when the user wants to merge a PR, says "merge this",
  "squash and merge", "merge and update docs", or is done with a
  feature branch and ready to merge into the default branch.
---

# Merge & Document

Squash-merge a PR and update project documentation. This skill is driver-neutral: the **primary driver** is whichever agent is executing it (Claude Code, Codex App, or Codex CLI). Follow these steps exactly.

## When to Invoke

- When the user runs `/merge` on a branch with an open PR
- When the user runs `/merge <PR number or URL>` from anywhere in the repository
- When the user wants to squash-merge and update docs in one step
- To finish an interrupted run — the skill is resumable and re-entry after a successful merge is expected, not an error

## Options

`/merge [<PR number or URL>]`

With no argument, resolve the PR from the current branch. With an argument, resolve that PR directly — the feature branch does not need to exist locally or be checked out.

## Prerequisites

- **git** — required.
- **GitHub access** — either `gh` (authenticated) or GitHub MCP tools available in the runtime. Stop only if neither is available.

Everything else is a **capability**, not a prerequisite. Step 1 records which capabilities are present; missing ones degrade the run and are reported as outstanding work rather than treated as failures.

---

## Runtime Adapter

Use the primary driver's native file-read and file-edit capabilities for documentation updates, and standalone shell commands for git operations. Claude Code may use Read/Write/Edit/Bash; Codex may use native file/edit/shell tools. Do not require subagents.

---

## Capabilities

GitHub API access, git fetch, git push, and local branch deletion are **separate** capabilities. A container with GitHub MCP tools can merge a PR through the API and still be unable to run `git push`; a fresh shallow clone can push but cannot verify branch content. Probe each one, store the result, and never infer one from another.

| Capability | Probe | If absent |
|------------|-------|-----------|
| `CAP_GITHUB` | `gh auth status`, else GitHub MCP tools in the runtime tool list | Stop — the skill cannot run |
| `CAP_FETCH` | `git -C "${PROJECT_ROOT}" ls-remote --exit-code "${BASE_REMOTE}" HEAD` | Branch verification is impossible; keep every branch and mark it unverified |
| `CAP_PUSH` | Unknown until first use. Classify the failure at Step 5 or Step 2 as auth, permission, or branch protection | Commit locally, report the unpushed commit as outstanding work |
| `CAP_LOCAL` | Repository has a working tree (`git -C "${PROJECT_ROOT}" rev-parse --is-bare-repository` returns `false`) | Skip Steps 3-6b; report that only the merge was performed |

Record every capability and every skipped operation. The Step 7 report must state precisely what was completed and what was not — silence about a skipped step is a failure of this skill.

---

## GitHub Access Modes

`gh` is not always installed. Claude Code on the web and other remote containers run without it and expose GitHub MCP tools instead. Detect the mode once in Step 1, store it as `GH_MODE`, and use the matching column below. Both modes cover everything the skill needs.

| Operation | `GH_MODE = cli` | `GH_MODE = mcp` |
|-----------|-----------------|-----------------|
| PR by number | `gh pr view <number> --repo "${BASE_REPO}" --json number,title,state,mergeable,mergeStateStatus,baseRefName,headRefName,headRefOid,headRepositoryOwner,headRepository,isCrossRepository,mergeCommit` | `pull_request_read` with `method: "get"` |
| PR for current branch | `gh pr view --json <same fields>` — no `--repo`, see below | `list_pull_requests` with `state: "open"` and `head: "<head-owner>:<branch>"`, then `pull_request_read` |
| Base repo identity | `gh repo view --repo "${BASE_REPO}" --json nameWithOwner` | Start from each remote's URL (below), then confirm against the PR's own base repository |
| Default branch | `gh repo view --repo "${BASE_REPO}" --json defaultBranchRef` | `git -C "${PROJECT_ROOT}" symbolic-ref --quiet "refs/remotes/${BASE_REMOTE}/HEAD"`, then parse the trailing name; if it fails, use the PR's base branch |
| Squash-merge | `gh pr merge <number> --repo "${BASE_REPO}" --squash` | `merge_pull_request` with `merge_method: "squash"` |
| Confirm merged | `gh pr view <number> --repo "${BASE_REPO}" --json state,mergeCommit` | `pull_request_read` with `method: "get"` — read `merged` and `merge_commit_sha` |
| Delete remote branch | `git -C "${PROJECT_ROOT}" push --force-with-lease="refs/heads/<head-branch>:<merged-head-sha>" "${HEAD_REMOTE}" --delete "refs/heads/<head-branch>"` | same git command, or the MCP delete-ref tool if it accepts an expected SHA |
| Merged PR list | `gh pr list --repo "${BASE_REPO}" --state merged --limit 100 --json number,headRefName,headRefOid,mergeCommit` | `list_pull_requests` with `state: "closed"`, paging with `page`/`perPage`, keeping entries whose `merged_at` is set |
| Open PR list | `gh pr list --repo "${BASE_REPO}" --state open --limit 100 --json number,headRefName` | `list_pull_requests` with `state: "open"`, paged |

Every `gh` command carries `--repo "${BASE_REPO}"`. The single exception is the branch-inference lookup: it is how `BASE_REPO` is discovered in the first place, and `gh pr view` cannot infer a branch when `--repo` is given. Once the PR is resolved, that exception is over — every later call names the repository.

Parse all JSON natively — never pipe to `jq`.

MCP tool calls take `owner`, `repo`, and `pullNumber` from the values stored in Step 1. Tool names differ slightly between GitHub MCP server versions. If a name in this table is missing from the runtime, use the closest equivalent it exposes and record the substitution in the Step 7 report.

---

## Agent Instructions

When invoked, execute the following steps sequentially.

---

### Step 1: Preflight and Resolve

```bash
git rev-parse --is-inside-work-tree
```
```bash
git rev-parse --show-toplevel
```

Store the toplevel path as `PROJECT_ROOT`. **Shell safety rules for the entire skill:**
- **Never use `cd`** — use `git -C` with the resolved root and absolute paths: `PROJECT_ROOT` in Steps 1-2, `WORK_ROOT` from Step 3 onward
- **Never use `$()`** command substitution, and never export shell variables. Run each command standalone, read its output, and paste the literal value — SHA, branch name, PR number — into the next command. Names such as `${PROJECT_ROOT}` and `${TARGET_BRANCH}` in this file are placeholders for values you substitute yourself
- The only pipes in this skill are the `git diff ... | git patch-id ...` commands in Steps 6 and 6b. Both sides are git; no other command may be piped

**Detect GitHub access mode:**

```bash
gh auth status
```

- Succeeds → store `GH_MODE = cli`
- `gh` missing or not authenticated → check the runtime's tool list for GitHub MCP tools (`pull_request_read`, `merge_pull_request`, `list_pull_requests`). Present → store `GH_MODE = mcp`
- Neither available → stop: "No GitHub access. Run `gh auth login`, or enable the GitHub MCP server."

Store `PROJECT_ROOT` as `WORK_ROOT` — the directory every later git command and file edit runs against. Step 3 may move it.

**Map the remotes.** Every remote operation names a remote explicitly; nothing in this skill assumes `origin` is the right one:

```bash
git -C "${PROJECT_ROOT}" remote -v
```

Parse each remote's URL natively into `<owner>/<repo>`. After the PR is resolved below, store:

- `BASE_REMOTE` — the remote whose URL matches `BASE_REPO`. Used for every fetch, pull, push to the target branch, and `refs/pull/<N>/head`
- `HEAD_REMOTE` — the remote whose URL matches `HEAD_REPO`. Used only to delete the head branch

In a fork checkout, `origin` is usually the fork and `upstream` the base repository, so `BASE_REMOTE` is `upstream` and `HEAD_REMOTE` is `origin`. In a same-repository PR both are `origin`. If no remote matches `BASE_REPO`, stop: the local clone is not connected to the repository the PR merges into. If no remote matches `HEAD_REPO`, record `HEAD_REMOTE = none` — the head branch simply is not deletable from here, which is reported, not worked around.

In MCP mode, look the PR up through `origin`'s repository first, then read the PR's own base repository from the response and correct `BASE_REPO` and `BASE_REMOTE` if they differ.

**Probe remote reachability:**

```bash
git -C "${PROJECT_ROOT}" ls-remote --exit-code "${BASE_REMOTE}" HEAD
```

Fails → store `CAP_FETCH = false`. The merge can still proceed through the API, but no branch may be deleted in Step 6 or 6b.

**Resolve the PR.** If the user supplied a number or URL, use it directly — do not require a local branch. Otherwise:

```bash
git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD
```

- Output is `HEAD` → detached HEAD. There is no branch to resolve a PR from. Stop: "Detached HEAD — re-run as `/merge <PR number>`."
- Output equals the default branch → stop: "Switch to the feature branch, or re-run as `/merge <PR number>`."

Read the PR through the GitHub Access table and store:

| Value | Source | Note |
|-------|--------|------|
| `PR_NUMBER` | `number` | |
| `TARGET_BRANCH` | `baseRefName` | The branch the PR merges into — may differ from the default branch in release/hotfix flows |
| `HEAD_BRANCH` | `headRefName` | |
| `HEAD_REPO` | `headRepositoryOwner.login` + `headRepository.name` | For a fork PR this is **not** the base repo. `headRepository.nameWithOwner` comes back empty — compose the two fields |
| `BASE_REPO` | base repo `nameWithOwner` | Where the PR merges and where `refs/pull/<N>/head` lives |
| `MERGED_HEAD_SHA` | `headRefOid` | The commit the PR actually merged. Step 2 needs it to delete the head branch safely |
| `PR_STATE` | `state` | |

Now resolve `BASE_REMOTE` and `HEAD_REMOTE` against these values as described above.

Pass `--repo "${BASE_REPO}"` to **every** `gh` command in this skill, and name `BASE_REMOTE` or `HEAD_REMOTE` in every git command that touches a remote. A bare PR number resolves against whatever repository the current directory happens to point at, which is the wrong one whenever the checkout is a fork.

`isCrossRepository` true means the head branch lives in a different repository from the base. That is not a reason to refuse cleanup — when you are working in your own fork, the head branch is yours and deleting it is correct. The rule is narrower: delete the head branch **only through `HEAD_REMOTE`**, the remote that actually points at the repository holding it. If `HEAD_REMOTE` is `none`, skip the deletion and report it. Never delete a branch through a remote that points somewhere else.

Verification is unaffected by forks: `refs/pull/<N>/head` is served by `BASE_REPO`.

**Branch on PR state — this is what makes the skill resumable:**

- `OPEN` → continue to Step 2.
- `MERGED` → the merge already happened, on this machine or elsewhere. Skip Step 2 entirely, record "merge already complete", and continue at Step 3 to finish documentation and cleanup. This is the normal path when a previous run was interrupted.
- `CLOSED` and not merged → stop: "PR #<number> was closed without merging."

For an `OPEN` PR, check mergeability:

- `mergeable` is `CONFLICTING` → stop: "PR has merge conflicts. Resolve them before merging."

**Working tree state:**

```bash
git -C "${PROJECT_ROOT}" status --porcelain
```

Non-empty → stop: "Working tree is not clean. Commit or stash changes first." Skip this check when `CAP_LOCAL` is false.

**Worktree map** — needed by Steps 3, 6, and 6b:

```bash
git -C "${PROJECT_ROOT}" worktree list --porcelain
```

Record every `branch refs/heads/<name>` line as `WORKTREE_BRANCHES`. A branch in this set is never deleted, and the target branch being in it changes Step 3.

**Shallow history:**

```bash
git -C "${PROJECT_ROOT}" rev-parse --is-shallow-repository
```

`true` → store `SHALLOW = true`. Step 6 deepens history before verifying and keeps anything it cannot verify.

Present the PR number, title, target branch, `GH_MODE`, and the resolved capabilities to the user, then proceed.

---

### Step 2: Squash-Merge

```bash
gh pr merge <number> --repo "${BASE_REPO}" --squash
```

**Do NOT pass `--delete-branch`.** `gh` documents it as "Delete the local **and** remote branch after merge" — it can remove the local branch immediately, before any verification has run, which is exactly what this skill exists to prevent. Cleanup is Step 6's job, and it happens only against evidence. Remote branch deletion is handled below, after the merge is confirmed.

In MCP mode, call `merge_pull_request` with `merge_method: "squash"`.

**Confirm the merge actually happened.** A successful command is not a merged PR:

```bash
gh pr view <number> --repo "${BASE_REPO}" --json state,mergeCommit
```

- `state` is `MERGED` with a `mergeCommit.oid` → store the SHA as `SQUASH_SHA` and continue.
- `state` is still `OPEN` → the PR was **queued or scheduled**, not merged. `gh` enables auto-merge when required checks are pending, and adds the PR to the merge queue when the target branch requires one. Neither has produced a squash commit yet. Stop and tell the user: "PR #<number> is queued for merge, not merged. Re-run `/merge <number>` once GitHub reports it merged — this skill resumes from there." Do NOT continue to Step 3; there is nothing to verify and nothing to document yet.

Do not bypass a merge queue on your own initiative. Mention `--admin` only if the user asks how to force it, and warn that it bypasses branch protection.

**Delete the remote branch** once the merge is confirmed — but only the commit that was actually merged. A merged PR proves what `MERGED_HEAD_SHA` contained; it proves nothing about where the branch points *now*. Anyone can push to a head branch after the merge, and an unconditional delete would destroy that work.

Skip this entirely when `HEAD_REMOTE` is `none`. Otherwise check the current tip first:

```bash
git -C "${PROJECT_ROOT}" ls-remote "${HEAD_REMOTE}" "refs/heads/<head-branch>"
```

- No output → the branch is already gone (the repository auto-deletes merged branches). Continue.
- Tip differs from `MERGED_HEAD_SHA` → someone pushed after the merge. **Keep the branch** and report the new commits as outstanding work.
- Tip equals `MERGED_HEAD_SHA` → delete it under an expected-SHA lease, so the delete still fails if the branch moves between the check and the push:

```bash
git -C "${PROJECT_ROOT}" push --force-with-lease="refs/heads/<head-branch>:<merged-head-sha>" "${HEAD_REMOTE}" --delete "refs/heads/<head-branch>"
```

A stale lease is reported by git as `! [rejected] (delete) -> <branch> (stale info)` with a non-zero exit, and the branch is left intact. Treat that as "keep and report", never as a reason to retry without the lease.

- Permission denied → record `CAP_PUSH = false` and list the remote branch as outstanding work.

If the merge itself fails:
- **Merge conflict** → STOP and report the conflict details. Do NOT attempt to resolve conflicts without user input.
- **CI checks failing** → Report which checks failed and recommend waiting for CI to pass.
- **Any other error** → Report the exact error message and stop. In MCP mode, report the tool's error body verbatim.

---

### Step 3: Switch to Target Branch

Skip this step and Steps 4-6b when `CAP_LOCAL` is false; report that only the merge was performed.

If `TARGET_BRANCH` is checked out in a **different** worktree, do not check it out here — git will refuse, and forcing it would disturb that worktree. Instead, adopt that worktree as `WORK_ROOT` and re-run the preflight cleanliness check there, because Step 1 only checked `PROJECT_ROOT`:

```bash
git -C "<that worktree path>" status --porcelain
```

- Empty → set `WORK_ROOT` to that path. Every remaining command and file edit in Steps 3-6b uses `git -C "${WORK_ROOT}"`, and documentation edits apply to files under it.
- Non-empty → that worktree has uncommitted work of its own, and committing docs there would sweep it into your commit. Do not touch it. Skip to Step 6, and report that documentation updates need to run from that worktree once it is clean.

Otherwise `WORK_ROOT` stays `PROJECT_ROOT`:

```bash
git -C "${WORK_ROOT}" checkout "${TARGET_BRANCH}"
```

If the branch does not exist locally — normal in a single-branch or fresh container clone:

```bash
git -C "${WORK_ROOT}" fetch "${BASE_REMOTE}" "${TARGET_BRANCH}:refs/remotes/${BASE_REMOTE}/${TARGET_BRANCH}"
```
```bash
git -C "${WORK_ROOT}" checkout -b "${TARGET_BRANCH}" "${BASE_REMOTE}/${TARGET_BRANCH}"
```

Then:

```bash
git -C "${WORK_ROOT}" pull
```

Verify the squash commit is present:

```bash
git -C "${WORK_ROOT}" log --oneline -1
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

Only if files were actually modified in Step 4. Run each as a separate command:

```bash
git -C "${WORK_ROOT}" add <specific files changed>
```
```bash
git -C "${WORK_ROOT}" commit -m "docs: update project docs after merging PR #<number>"
```
```bash
git -C "${WORK_ROOT}" push
```

If no docs needed updating, skip this step entirely. Do NOT create empty commits.

**If the push is rejected**, classify the failure and do not retry blindly:

| Rejection | Meaning | Do this |
|-----------|---------|---------|
| Protected branch / "changes must be made through a pull request" | The target branch does not accept direct pushes | Push the commit to a new branch (`docs/pr-<number>-followup`) and open a follow-up PR with the same GitHub Access table. Report its URL |
| Authentication or permission denied | No push credentials in this environment | Record `CAP_PUSH = false`. Leave the commit in place locally and report it as outstanding work — do not discard it |
| Non-fast-forward | The target moved while you worked | `git -C "${WORK_ROOT}" pull --rebase`, then push once more. Still rejected → stop and report |

Repositories that require PRs for every change are common. Treat the follow-up PR as a normal outcome, not an error.

---

### Step 6: Verify and Delete the Merged Branch

A squash merge writes a **new** commit on the target branch. The feature branch head never becomes an ancestor of the target, so `git branch -d` and `git branch --merged` — both of which test ancestry — refuse the branch every single time. Ancestry cannot prove a squash merge. Prove it with **content** instead, then delete on that proof.

Substitute every value by hand: run a command, read its output, paste the literal SHA or name into the next command.

#### Stage 1: Preconditions

```bash
git -C "${WORK_ROOT}" rev-parse --verify --quiet refs/heads/<head-branch>
```

- Prints nothing and exits non-zero → the branch is **absent**. Normal after a fresh clone, and also normal if an earlier `gh pr merge --delete-branch` on another machine already removed it. Record "absent — nothing to delete" and go to Step 6b. This is not an error.
- Prints a SHA → record it as `BRANCH_HEAD` and continue.

**Refresh the worktree map before using it.** The copy taken in Step 1 is stale: Step 3 switched away from the head branch, so a run that started on the feature branch would otherwise see it as still checked out and keep it forever — the exact failure this skill exists to fix.

```bash
git -C "${WORK_ROOT}" worktree list --porcelain
```

Rebuild `WORKTREE_BRANCHES` from this output. If `<head-branch>` is in the refreshed set, record "kept — checked out in a worktree" and go to Step 6b. A branch checked out in any worktree is never deleted, whatever the content evidence says.

If `CAP_FETCH` is false, record "kept — unverified (remote unreachable)" and go to Step 6b.

If `SHALLOW = true`:

```bash
git -C "${WORK_ROOT}" fetch --deepen 200 "${BASE_REMOTE}"
```

Fetch fails → record "kept — unverified (shallow history)" and go to Step 6b. Never delete on absent evidence.

#### Stage 2: Gather Evidence

`SQUASH_SHA` comes from Step 2. On a resumed run where Step 2 was skipped, read it from the PR (`mergeCommit.oid` / `merge_commit_sha`). If the API returns nothing — it can lag right after a merge — fall back to a message search, since GitHub's default squash subject ends with the PR number:

```bash
git -C "${WORK_ROOT}" log --fixed-strings --grep "(#<number>)" --max-count 1 --format=%H "${TARGET_BRANCH}"
```

Neither source yields a SHA → record "kept — unverified (no squash commit found)" and go to Step 6b.

Confirm the squash commit is in local history:

```bash
git -C "${WORK_ROOT}" merge-base --is-ancestor <squash-sha> "${TARGET_BRANCH}"
```

Exit 0 → present. Non-zero → run `git -C "${WORK_ROOT}" fetch "${BASE_REMOTE}" "${TARGET_BRANCH}"` and retry once. Still non-zero → record "kept — unverified (squash commit not in local history)".

Fetch the PR head from `BASE_REMOTE` — the base repository serves `refs/pull/<N>/head` for fork PRs too, which is why verification never needs the fork's own remote:

```bash
git -C "${WORK_ROOT}" fetch "${BASE_REMOTE}" "refs/pull/<number>/head:refs/prheads/<number>"
```

Fails → record "kept — unverified (PR head unavailable)" and go to Step 6b.

```bash
git -C "${WORK_ROOT}" rev-parse refs/prheads/<number>
```

Record as `PR_HEAD`. **If `PR_HEAD` differs from `BRANCH_HEAD`, stop evaluating this branch for deletion.** The local branch holds commits the PR never carried, or trails behind it; either way the merge is not evidence about the local branch's content. Record "kept — local branch diverges from the merged PR head" and show the difference:

```bash
git -C "${WORK_ROOT}" log --oneline refs/prheads/<number>..refs/heads/<head-branch>
```

When the heads match, compute the merge base:

```bash
git -C "${WORK_ROOT}" merge-base <branch-head> "${TARGET_BRANCH}"
```

Record as `MERGE_BASE`, then take both patch ids:

```bash
git -C "${WORK_ROOT}" diff <merge-base> <branch-head> | git patch-id --verbatim
```
```bash
git -C "${WORK_ROOT}" diff <squash-sha>^ <squash-sha> | git patch-id --verbatim
```

Each prints `<patch-id> <commit-id>`. Compare **only the first field** — the second is a commit id, is all zeros for a plain diff, and never matches.

`--verbatim` is required. Plain `git patch-id` **strips whitespace**, so an equal id under the default algorithm does not prove equal content: indentation carries meaning in Python, YAML, Makefiles, and string literals, and a whitespace-only difference is a real difference. `--verbatim` compares the patch as given. Note that `--verbatim` and `--stable` are mutually exclusive — pass only `--verbatim`.

These are the only pipes in this skill. Both sides are git, there is no shell variable and no `$()`, and the form is identical in bash and PowerShell. Both diffs are generated from the object database, so the working tree's line-ending configuration does not affect them.

#### Stage 3: Verdict

**Verbatim ids equal** → the branch content is exactly what landed on the target. Re-read the tip immediately before deleting, because time has passed since Stage 2:

```bash
git -C "${WORK_ROOT}" rev-parse refs/heads/<head-branch>
```

Differs from `BRANCH_HEAD` → the branch moved during verification. Keep it and report; do not delete on stale evidence. Re-check the worktree map at the same moment, since another worktree may have checked the branch out while you were verifying:

```bash
git -C "${WORK_ROOT}" worktree list --porcelain
```

Tip unchanged and the branch still free → delete:

```bash
git -C "${WORK_ROOT}" branch -D <head-branch>
```

`-D` is required: `-d` tests ancestry and refuses every squash-merged branch. Verbatim patch-id equality, the worktree check, and the tip re-check together are what make `-D` safe — never run it without all three. Runtimes that prefer an atomic compare-and-delete may use `git -C "${WORK_ROOT}" update-ref -d "refs/heads/<head-branch>" <verified-sha>`, which deletes only if the ref still holds that SHA; it has no checked-out-branch guard of its own, so the worktree check stays mandatory.

**Verbatim ids differ** → do not delete. Determine whether the difference is real or whitespace-only:

```bash
git -C "${WORK_ROOT}" diff <merge-base> <branch-head> | git patch-id --stable
```
```bash
git -C "${WORK_ROOT}" diff <squash-sha>^ <squash-sha> | git patch-id --stable
```

- Stable ids match → the branch and the squash commit differ **only in whitespace**. Report it as "whitespace-only difference — review before deleting" and leave the decision to the user.
- Stable ids also differ → substantive difference. Keep the branch and report what is unaccounted for:

```bash
git -C "${WORK_ROOT}" log --oneline "${TARGET_BRANCH}..<head-branch>"
```
```bash
git -C "${WORK_ROOT}" diff --stat "${TARGET_BRANCH}...<head-branch>"
```

Remove the temporary ref either way, including after a failed verification:

```bash
git -C "${WORK_ROOT}" update-ref -d "refs/prheads/<number>"
```

---

### Step 6b: Repo-Wide Branch Sweep

The PR's own branch is not the only branch that goes stale. A branch pointing at the same head under a different name, or a one-commit branch that never got a PR, is invisible to Step 6 and accumulates silently. Three kinds of state need separate handling: **local branches**, **remote branches**, and **stale remote-tracking refs**.

#### Stale remote-tracking refs

Remote-tracking refs for branches deleted on the server linger until pruned. They are not branches and hold no work:

```bash
git -C "${WORK_ROOT}" remote prune --dry-run "${BASE_REMOTE}"
```

Report what it would remove, then prune only with the user's agreement:

```bash
git -C "${WORK_ROOT}" remote prune "${BASE_REMOTE}"
```

#### Local branches

```bash
git -C "${WORK_ROOT}" for-each-ref --format="%(refname:short) %(objectname)" refs/heads
```

Two branches printing the same object name are two names for one head. Classify the first, then apply the identical verdict to the other — this is how a branch pointing at some PR's head under an unrelated name gets reconciled.

Build the protected set first. These are never deleted, whatever the content says:

- every branch in the **refreshed** `WORKTREE_BRANCHES` from Step 6 — never the Step 1 copy, which predates the checkout in Step 3
- `TARGET_BRANCH` and the default branch
- integration branches: anything matching `main`, `master`, `develop`, `staging`, `release/*`, or `hotfix/*`
- every branch with an open PR (see the GitHub Access table; page until the listing is exhausted)

Classify each remaining branch:

| Class | Test | Action |
|-------|------|--------|
| (a) Ancestor of target | `git -C "${WORK_ROOT}" merge-base --is-ancestor <branch-sha> "${TARGET_BRANCH}"` exits 0 | Delete with `git -C "${WORK_ROOT}" branch -d <branch>` — ancestry is proof on its own, and `-d` re-verifies it |
| (b) Squashed into target | Verbatim patch-id equality, or exact tree equality for every path the branch touched | Delete with `-D` after the tip re-check |
| (c) Unique content | Neither test passes | Keep, and report the commits and files the target does not carry |
| (d) Protected | In the protected set above | Keep, always — do not evaluate its content |

**Branches that map to a PR.** Fetch the merged PR list from the GitHub Access table, paging until the oldest listed PR predates the oldest unclassified branch's last commit — a single unpaged page silently misclassifies older branches as unique. Match a branch to a PR by, in order:

1. `headRefName` equals the branch name.
2. `headRefOid` equals the branch's object name from `for-each-ref` — this catches a branch that was never the PR's branch but points at the same commit.

On a match, run Stage 2 and Stage 3 with that PR's number and merge commit, then delete the temporary ref.

**Branches with no PR at all.** There is no squash commit to compare against, so compare the branch's tree against the target directly. Get the full change list with statuses — a name-only listing hides deletions, renames, and mode changes, and a branch whose only content is a deletion would otherwise look empty and be wrongly deleted:

```bash
git -C "${WORK_ROOT}" diff --name-status --find-renames "${TARGET_BRANCH}...<branch>"
```

Every entry must be accounted for before the branch can be deleted:

| Status | Meaning | Accounted for when |
|--------|---------|--------------------|
| `A` / `M` | Added or modified | The blob hash matches on the target (below) |
| `D` | Deleted on the branch | The path is also absent from the target |
| `R` | Renamed | Both the old path's absence and the new path's blob match on the target |
| `T` | Mode change | `git ls-tree` reports the same mode on both sides |

Compare blobs and modes per path:

```bash
git -C "${WORK_ROOT}" ls-tree <branch> -- <path>
```
```bash
git -C "${WORK_ROOT}" ls-tree "${TARGET_BRANCH}" -- <path>
```

`ls-tree` prints mode, type, and object hash together, so one command per side settles both content and mode. Identical mode and hash means the file is already on the target exactly.

- Every entry accounted for → class (b). The work reached the target under a different commit. Delete with `-D` after the tip re-check.
- Anything unaccounted for → class (c). Keep the branch and report every path that did not match. When a path looks superseded rather than lost — the target carries a rewritten or relocated version of it — say exactly that, name both locations, and let the user decide. Never delete on your own judgment that content "looks superseded".

#### Remote branches

Local cleanup says nothing about the server. List remote branches that no longer have an open PR and **report** them:

```bash
git -C "${WORK_ROOT}" for-each-ref --format="%(refname:short)" "refs/remotes/${BASE_REMOTE}"
```

Remote-tracking refs can be stale, so never delete a remote branch on their evidence. Delete one only when the user asks, and only the way Step 2 does it: read the live tip with `git -C "${WORK_ROOT}" ls-remote`, confirm it against the SHA you verified, and push the deletion under a `--force-with-lease` on that SHA through the remote that owns the branch. The head branch of the PR merged in this run was already handled in Step 2.

Report each deletion and each retention as you go, with the evidence that decided it.

---

### Step 7: Report

State what was completed and what was not. Both halves are required.

**Completed:**

- Which PR was merged (number and title) and the squash commit SHA — or that the merge was already complete when the run started
- Which docs were updated, or "No doc updates needed" — and if they went to a follow-up PR, its URL
- The merged branch's outcome: deleted (with the matching verbatim patch id), absent, or kept with the reason
- Remote branch and remote-tracking ref outcomes

**Outstanding:**

- Every capability that was missing and every step it blocked — an unpushed docs commit, a skipped branch deletion, a remote branch nobody could delete
- Any remote head branch kept because it moved after the merge, naming the commits that arrived since — this is work someone else pushed, and nobody else is watching for it
- Any documentation left unwritten because `WORK_ROOT` could not be made clean
- Every branch left unverified, with the reason
- Any MCP tool substitutions made under `GH_MODE = mcp`

**Branch inventory** — every local branch in this checkout and why it is still there:

| Branch | Class | Evidence | Kept because |
|--------|-------|----------|--------------|
| `main` | protected | — | Target branch |
| `feat/sender-rules` | unique content | 2 commits, 3 files not on target | Not merged anywhere |
| `wip/spike` | protected | worktree at `../spike` | Checked out in a worktree |
| `codex/logo` | unverified | PR head unavailable | Could not prove content landed |

List every branch, including the obviously fine ones. A branch left out of this table is a branch nobody notices for another ten merges.

**Scope the inventory honestly.** It describes *this* checkout only. A container's inventory says nothing about branches on the user's laptop or any other clone. State which checkout it covers, and never present it as a repository-wide branch census.

---

## Rules

- Never delete a branch without content proof — verbatim patch-id equality against the squash commit, exact blob-and-mode equality for every path the branch touched, or plain ancestry
- `-D` is permitted only after that proof, the protected-set check, and a tip re-check taken immediately before deletion; `-d` alone can never delete a squash-merged branch, because it tests ancestry and a squash merge breaks ancestry by design
- Always pass `--verbatim` to `git patch-id` for deletion evidence — the default strips whitespace, and whitespace changes behavior. A default-algorithm match with a verbatim mismatch is a whitespace-only difference: report it, do not act on it
- Never pass `--delete-branch` to `gh pr merge` — it deletes the local branch too, before any verification
- A successful `gh pr merge` is not a merged PR — confirm `state` is `MERGED` before verifying or documenting anything. Auto-merge and merge queues leave it `OPEN`
- Never delete a branch that is protected, checked out in a worktree, or carrying commits the merged PR did not have. Re-read the worktree map after Step 3 and again before deleting — the Step 1 copy is stale the moment the target branch is checked out
- Never delete a remote branch on the strength of the merge alone. A merged PR proves what `MERGED_HEAD_SHA` held, not where the branch points now: check the live tip, then delete under `--force-with-lease` on that SHA. A `(stale info)` rejection means someone pushed after the merge — keep the branch and report it
- Never delete on absent evidence — an unreachable remote, a missing squash commit, or an un-deepened shallow clone means "keep and mark unverified"
- A branch missing from a fresh clone is "absent", not an error
- Compare only the first field of `git patch-id` output; the second field is a commit id and never matches
- Delete `refs/prheads/*` temporary refs after every verification, including failed ones
- Probe GitHub access, fetch, push, and local-checkout capabilities separately — never infer one from another
- Resolve repositories once and then actually use them: `--repo "${BASE_REPO}"` on every `gh` command, `BASE_REMOTE` or `HEAD_REMOTE` on every git command that touches a remote. A bare PR number or a hardcoded `origin` resolves against whatever the current directory points at, which is the wrong repository in a fork checkout
- Delete the head branch only through `HEAD_REMOTE`, the remote that actually holds it. `HEAD_REMOTE = none` means the branch is not deletable from here — report it. Working in your own fork is not a reason to skip cleanup; pointing a deletion at the wrong remote is
- All of Steps 3-6b run against `WORK_ROOT`, which Step 3 may move to another worktree. Re-check cleanliness wherever it lands — Step 1 only vouched for `PROJECT_ROOT`
- Re-entry after a successful merge is expected — an already-merged PR resumes at Step 3, it does not stop the skill
- A rejected push on a protected branch means a follow-up PR, not a failure
- Every local branch appears in the Step 7 inventory, and the inventory states which checkout it describes
- Report outstanding work explicitly — a step that was skipped for a missing capability must be named
- Do NOT run build commands — these are doc-only updates after the merge
- Do NOT modify any source code files during the doc update step
- Do NOT create new documentation files — only update existing ones
- Always use `git add <specific files>` — never `git add -A` or `git add .`
- Read files before editing them
- **Never use `cd`** — use `git -C` with the resolved root and absolute paths: `PROJECT_ROOT` in Steps 1-2, `WORK_ROOT` from Step 3 onward
- **Never use `$()` or shell variables** — run each command standalone and paste the literal value into the next one
- **Never pipe** except the `git diff ... | git patch-id ...` verification commands
