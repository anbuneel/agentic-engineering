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

`/merge [<PR number or URL>]`

- On a branch with an open PR, or with a PR number or URL from anywhere in the repository
- To squash-merge and update docs in one step
- To finish an interrupted run — re-entry after a successful merge is expected, not an error

## Prerequisites

**git**, and **GitHub access**: either `gh` (authenticated) or GitHub MCP tools. Stop only if neither is available.

Everything else is a capability, not a prerequisite. Step 1 records what is present; missing capabilities degrade the run and are reported as outstanding work.

---

## Why the Obvious Approach Fails

Four traps sit in this workflow. The steps reference these by name rather than re-explaining.

- **Ancestry cannot prove a squash merge.** A squash merge writes a *new* commit, so the branch head never becomes an ancestor of the target. `git branch -d` and `git branch --merged` both test ancestry, so both refuse every squash-merged branch forever. Deletion must rest on **content proof** instead.
- **The default patch-id strips whitespace.** Indentation carries meaning in Python, YAML, and Makefiles, so a default-algorithm match does not prove equal content. Evidence is `git patch-id --verbatim`; a default match with a verbatim mismatch is a whitespace-only difference to report, not act on. (`--verbatim` and `--stable` are mutually exclusive.)
- **A merge is a statement about the past.** `gh pr merge --delete-branch` deletes the *local* branch too, before verification. A successful merge command may only have queued the PR. And a merged PR proves what the head commit *was*, not where the branch points now. Confirm state, and delete remotes under an expected-SHA lease.
- **Implicit remotes follow tracking config.** In a fork checkout that means the fork, not the repository the PR merged into. Name the remote and refspec every time; pass `--repo` to every `gh` call.

---

## Runtime Adapter

Use the primary driver's native file-read and file-edit capabilities for documentation updates, and standalone shell commands for git operations. Claude Code may use Read/Write/Edit/Bash; Codex may use native file/edit/shell tools. Do not require subagents.

Commands are grouped in blocks for brevity. **Run each line as its own command** — never chain them — and paste literal values from one into the next.

## Capabilities

GitHub API access, fetch, push, and local checkout are **separate**. A container with GitHub MCP tools can merge through the API and still be unable to `git push`. Probe each, store it, never infer one from another.

| Capability | Probe | If absent |
|------------|-------|-----------|
| `CAP_GITHUB` | `gh auth status`, else GitHub MCP tools in the runtime tool list | Stop — the skill cannot run |
| `CAP_FETCH` | `git -C "${PROJECT_ROOT}" ls-remote --exit-code "${BASE_REMOTE}" HEAD` | Keep every branch, marked unverified |
| `CAP_PUSH` | Unknown until first use; classify the failure at Step 2 or 5 as auth, permission, or branch protection | Commit locally, report the unpushed commit |
| `CAP_LOCAL` | `git -C "${PROJECT_ROOT}" rev-parse --is-bare-repository` returns `false` | Skip Steps 3-6b; report that only the merge was performed |

## GitHub Access Modes

`gh` is absent in Claude Code on the web and other remote containers, which expose GitHub MCP tools instead. Detect the mode once in Step 1, store it as `GH_MODE`, and use the matching column.

| Operation | `GH_MODE = cli` | `GH_MODE = mcp` |
|-----------|-----------------|-----------------|
| PR by number | `gh pr view <number> --repo "${BASE_REPO}" --json number,title,state,mergeable,mergeStateStatus,baseRefName,headRefName,headRefOid,headRepositoryOwner,headRepository,isCrossRepository,mergeCommit` | `pull_request_read` with `method: "get"` |
| PR for current branch | `gh pr view --json <same fields>` — no `--repo`, see 1b | `list_pull_requests` with `state: "open"` and `head: "<head-owner>:<branch>"`, then `pull_request_read` |
| Repo identity / default branch | `gh repo view --repo "${BASE_REPO}" --json nameWithOwner,defaultBranchRef` | Remote URLs (1a), then `git -C "${PROJECT_ROOT}" symbolic-ref --quiet "refs/remotes/${BASE_REMOTE}/HEAD"`; if that fails, the PR's base branch |
| Squash-merge | `gh pr merge <number> --repo "${BASE_REPO}" --squash` | `merge_pull_request` with `merge_method: "squash"` |
| Confirm merged | `gh pr view <number> --repo "${BASE_REPO}" --json state,mergeCommit` | `pull_request_read` — read `merged` and `merge_commit_sha` |
| Merged PR list | `gh pr list --repo "${BASE_REPO}" --state merged --limit 100 --json number,headRefName,headRefOid,mergeCommit` | `list_pull_requests` with `state: "closed"`, paged with `page`/`perPage`, keeping entries whose `merged_at` is set |
| Open PR list | `gh pr list --repo "${BASE_REPO}" --state open --limit 100 --json number,headRefName` | `list_pull_requests` with `state: "open"`, paged |

Parse all JSON natively — never pipe to `jq`. MCP calls take `owner`, `repo`, and `pullNumber` from Step 1. If a tool name here is missing from the runtime, use the closest equivalent and record the substitution in Step 7.

---

## Agent Instructions

Execute the following steps sequentially.

---

### Step 1: Preflight and Resolve

```bash
git rev-parse --is-inside-work-tree
git rev-parse --show-toplevel
gh auth status
```

Store the toplevel path as `PROJECT_ROOT`, and again as `WORK_ROOT` — the root every later git command and file edit runs against, which Step 3 may move. **Shell safety rules for the entire skill:**

- **Never use `cd`** — use `git -C` with the resolved root and absolute paths
- **Never use `$()`** or shell variables. Read each command's output and paste the literal value — SHA, branch name, PR number — into the next. Names such as `${WORK_ROOT}` are placeholders you substitute yourself
- **Never pipe**, except the `git diff ... | git patch-id ...` commands in Steps 6 and 6b. Both sides are git, and the form is identical in bash and PowerShell

`gh auth status` succeeds → `GH_MODE = cli`. `gh` missing or unauthenticated, but GitHub MCP tools present → `GH_MODE = mcp`. Neither → stop: "No GitHub access. Run `gh auth login`, or enable the GitHub MCP server."

**Resolve in this order.** Each stage depends only on the ones before it: probing reachability needs `BASE_REMOTE`, which needs `BASE_REPO`, which needs the PR.

#### 1a. Repository

| Invocation | How `BASE_REPO` is determined |
|------------|-------------------------------|
| `/merge <URL>` | Parse `<owner>/<repo>` and the number from the URL — authoritative |
| `/merge <number>` | A bare number does not name a repository, and the same number is a different PR in a fork. Resolve from the remotes and state which repository you used |
| `/merge` | Deferred to 1b, where branch inference resolves repository and PR together |

Run `git -C "${PROJECT_ROOT}" remote -v` and parse each URL natively into `<owner>/<repo>`. All remotes pointing at one repository → that is `BASE_REPO`. Several (a fork checkout) → the base is the parent, so confirm rather than guess with `gh repo view --repo <candidate> --json isFork,parent`. `isFork` false → that candidate is `BASE_REPO`. If every candidate is a fork, use the `parent` of the repository the current branch tracks. Still ambiguous → stop and ask; resolving a bare number against the wrong repository merges an unrelated PR.

#### 1b. Pull request

With a number or URL, read the PR with `--repo "${BASE_REPO}"`. With no argument, infer from the current branch via `git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD`:

- `HEAD` → detached. Stop: "Detached HEAD — re-run as `/merge <PR number>`."
- Equals the default branch → stop: "Switch to the feature branch, or re-run as `/merge <PR number>`."

Otherwise run `gh pr view --json <fields from the GitHub Access table>`. This is the only `gh` call that omits `--repo`, because it is how the repository gets discovered here — `gh` rejects the combination with "argument required when using the --repo flag". MCP mode has no branch inference: `list_pull_requests` needs an owner and repo up front, so a no-argument invocation must resolve the repository through 1a first.

Store:

| Value | Source | Note |
|-------|--------|------|
| `PR_NUMBER` | `number` | |
| `TARGET_BRANCH` | `baseRefName` | May differ from the default branch in release/hotfix flows |
| `HEAD_BRANCH` | `headRefName` | |
| `HEAD_REPO` | `headRepositoryOwner.login` + `headRepository.name` | `headRepository.nameWithOwner` comes back empty — compose the two |
| `BASE_REPO` | base repo `nameWithOwner` | Confirms or corrects 1a. The PR's own answer wins |
| `MERGED_HEAD_SHA` | `headRefOid` | The commit the PR merged. Step 2 needs it to delete the head branch safely |
| `PR_STATE` | `state` | |

From here on, every `gh` command carries `--repo "${BASE_REPO}"`.

#### 1c. Remotes

Map the resolved repositories back onto remotes: `BASE_REMOTE` matches `BASE_REPO` and carries every fetch, pull, and push involving the target branch plus `refs/pull/<N>/head`; `HEAD_REMOTE` matches `HEAD_REPO` and is used only to delete the head branch.

In a fork checkout `origin` is usually the fork and `upstream` the base, so `BASE_REMOTE` is `upstream` and `HEAD_REMOTE` is `origin`; in a same-repository PR both are `origin`. No remote matches `BASE_REPO` → stop: this clone is not connected to the repository the PR merges into. No remote matches `HEAD_REPO` → `HEAD_REMOTE = none`; the head branch is not deletable from here, which is reported, not worked around.

`isCrossRepository` true is not a reason to refuse cleanup — in your own fork the head branch is yours. The rule is only that deletion goes through `HEAD_REMOTE`, never a remote pointing elsewhere. Verification is unaffected: `refs/pull/<N>/head` is served by `BASE_REPO`.

#### 1d. Capabilities and local state

```bash
git -C "${PROJECT_ROOT}" ls-remote --exit-code "${BASE_REMOTE}" HEAD
git -C "${PROJECT_ROOT}" status --porcelain
git -C "${PROJECT_ROOT}" worktree list --porcelain
git -C "${PROJECT_ROOT}" rev-parse --is-shallow-repository
```

- `ls-remote` fails → `CAP_FETCH = false`. The merge can still proceed through the API, but no branch may be deleted in Step 6 or 6b
- `status` non-empty → stop: "Working tree is not clean. Commit or stash changes first." Skip when `CAP_LOCAL` is false
- Record every `branch refs/heads/<name>` line as `WORKTREE_BRANCHES`. Step 6 refreshes this; the copy here serves Step 3's checkout decision
- Shallow `true` → `SHALLOW = true`. Step 6 deepens history before verifying and keeps whatever it cannot verify

#### Branch on PR state

This is what makes the skill resumable:

- `OPEN` → check mergeability (`CONFLICTING` → stop: "PR has merge conflicts. Resolve them before merging."), then Step 2
- `MERGED` → the merge already happened, here or elsewhere. Skip Step 2, record "merge already complete", continue at Step 3. This is the normal path after an interrupted run
- `CLOSED` and not merged → stop: "PR #<number> was closed without merging."

Present the PR number, title, target branch, resolved repositories and remotes, `GH_MODE`, and capabilities, then proceed.

---

### Step 2: Squash-Merge

```bash
gh pr merge <number> --repo "${BASE_REPO}" --squash
gh pr view <number> --repo "${BASE_REPO}" --json state,mergeCommit
```

Never add `--delete-branch` — it deletes the local branch before verification. In MCP mode, call `merge_pull_request` with `merge_method: "squash"`.

The second command confirms the merge, because a successful merge command is not a merged PR:

- `MERGED` with a `mergeCommit.oid` → store it as `SQUASH_SHA` and continue
- Still `OPEN` → auto-merge or a merge queue took it; no squash commit exists yet. Stop: "PR #<number> is queued for merge, not merged. Re-run `/merge <number>` once GitHub reports it merged — this skill resumes from there." Do NOT continue to Step 3

Do not bypass a merge queue on your own initiative. Mention `--admin` only if the user asks, and warn that it bypasses branch protection.

If the merge fails: a **conflict** stops the run with the details reported and no attempt to resolve it; **failing checks** are reported by name with a recommendation to wait; **any other error** is reported verbatim and stops.

**Delete the remote branch**, but only the commit that was actually merged. Skip entirely when `HEAD_REMOTE` is `none`. Otherwise read the live tip with `git -C "${PROJECT_ROOT}" ls-remote "${HEAD_REMOTE}" "refs/heads/<head-branch>"`:

- No output → already gone (the repository auto-deletes merged branches). Continue
- Differs from `MERGED_HEAD_SHA` → someone pushed after the merge. **Keep it** and report the new commits as outstanding work
- Equals `MERGED_HEAD_SHA` → delete under a lease, so it still fails if the branch moves between check and push:

```bash
git -C "${PROJECT_ROOT}" push --force-with-lease="refs/heads/<head-branch>:<merged-head-sha>" "${HEAD_REMOTE}" --delete "refs/heads/<head-branch>"
```

git reports a stale lease as `! [rejected] (delete) -> <branch> (stale info)` with a non-zero exit, leaving the branch intact. That is "keep and report", never a reason to retry without the lease. Permission denied → `CAP_PUSH = false`; list the remote branch as outstanding.

---

### Step 3: Switch to Target Branch

Skip Steps 3-6b when `CAP_LOCAL` is false; report that only the merge was performed.

If `TARGET_BRANCH` is checked out in a **different** worktree, do not check it out here — git will refuse, and forcing it would disturb that worktree. Adopt that worktree instead, re-running `git -C "<that worktree path>" status --porcelain` because Step 1 only vouched for `PROJECT_ROOT`. Empty → set `WORK_ROOT` to that path; Steps 3-6b and all documentation edits apply there. Non-empty → committing docs there would sweep up its uncommitted work, so leave it alone, skip to Step 6, and report that documentation needs to run from that worktree once clean.

Otherwise `WORK_ROOT` stays `PROJECT_ROOT`:

```bash
git -C "${WORK_ROOT}" checkout "${TARGET_BRANCH}"
git -C "${WORK_ROOT}" pull --ff-only "${BASE_REMOTE}" "${TARGET_BRANCH}"
git -C "${WORK_ROOT}" log --oneline -1
```

If the branch does not exist locally — normal in a single-branch or fresh container clone — create it from the base remote first:

```bash
git -C "${WORK_ROOT}" fetch "${BASE_REMOTE}" "${TARGET_BRANCH}:refs/remotes/${BASE_REMOTE}/${TARGET_BRANCH}"
git -C "${WORK_ROOT}" checkout -b "${TARGET_BRANCH}" "${BASE_REMOTE}/${TARGET_BRANCH}"
```

`--ff-only` refuses → the local target branch has diverged from the base repository. Stop and report; do not merge or rebase it to force it through. The `log` line confirms the squash commit is present.

---

### Step 4: Update Documentation

Read each file before editing. Only update files that exist — do NOT create new files in this step.

**README.md** — If the merged PR added, removed, or changed a feature that the README describes, update the relevant sections. Skip if the PR was an internal refactor with no user-facing changes.

**CHANGELOG.md** — If the file exists, add an entry under the appropriate section (Added, Changed, Fixed, Removed). Use the PR title and number as the entry. Skip if no CHANGELOG exists.

**Agent guidance docs** — If the merged PR introduced new patterns, conventions, architectural decisions, or learnings, update existing guidance files such as `AGENTS.md`, `CLAUDE.md`, or equivalent local agent docs. Skip if nothing changed.

**Other tracking docs** — If the project has a roadmap, TODO, or project board doc, update it to reflect the completed work.

---

### Step 5: Commit and Push Doc Updates

Only if files were actually modified in Step 4. If no docs needed updating, skip this step entirely — do NOT create empty commits.

```bash
git -C "${WORK_ROOT}" add <specific files changed>
git -C "${WORK_ROOT}" commit -m "docs: update project docs after merging PR #<number>"
git -C "${WORK_ROOT}" push "${BASE_REMOTE}" "HEAD:refs/heads/${TARGET_BRANCH}"
```

**If the push is rejected**, classify it — do not retry blindly:

| Rejection | Meaning | Do this |
|-----------|---------|---------|
| Protected branch / "changes must be made through a pull request" | The target rejects direct pushes | Open a follow-up docs PR, below |
| Authentication or permission denied | No push credentials here | `CAP_PUSH = false`. Leave the commit locally and report it — do not discard it |
| Non-fast-forward | The target moved while you worked | `git -C "${WORK_ROOT}" pull --rebase "${BASE_REMOTE}" "${TARGET_BRANCH}"`, then push once more with the same explicit refspec. Still rejected → stop and report |

**Follow-up docs PR** — a normal outcome on repositories that require PRs, not an error. Push the commit to its own branch and open a PR against `TARGET_BRANCH`:

```bash
git -C "${WORK_ROOT}" push "${BASE_REMOTE}" "HEAD:refs/heads/docs/pr-<number>-followup"
```

Refused for permission rather than protection → you cannot write to the base repository at all; push to your own fork instead with `git -C "${WORK_ROOT}" push "${HEAD_REMOTE}" "HEAD:refs/heads/docs/pr-<number>-followup"`. Then `gh pr create --repo "${BASE_REPO}" --base "${TARGET_BRANCH}" --head <owner>:docs/pr-<number>-followup --body-file <file>`, and report its URL. `HEAD_REMOTE = none` too → nowhere to push; report the commit as outstanding and leave it.

---

### Step 6: Verify and Delete the Merged Branch

Ancestry cannot prove a squash merge, so prove it with content.

#### Stage 1: Preconditions

```bash
git -C "${WORK_ROOT}" rev-parse --verify --quiet refs/heads/<head-branch>
git -C "${WORK_ROOT}" worktree list --porcelain
```

- `rev-parse` prints nothing and exits non-zero → **absent**. Normal after a fresh clone, or if `--delete-branch` on another machine already removed it. Record "absent — nothing to delete" and go to Step 6b. Not an error
- A SHA → record it as `BRANCH_HEAD`
- **Rebuild `WORKTREE_BRANCHES` from this fresh listing.** The Step 1 copy is stale — Step 3 switched away from the head branch, so a run that started on the feature branch would otherwise see it as checked out and keep it forever. `<head-branch>` in the refreshed set → "kept — checked out in a worktree", go to Step 6b, whatever the content evidence says

`CAP_FETCH` false → "kept — unverified (remote unreachable)". `SHALLOW = true` → deepen with `git -C "${WORK_ROOT}" fetch --deepen 200 "${BASE_REMOTE}"` first, and if that fails, "kept — unverified (shallow history)". Never delete on absent evidence.

#### Stage 2: Gather Evidence

`SQUASH_SHA` comes from Step 2; on a resumed run read it from the PR. If the API returns nothing — it can lag right after a merge — fall back to a message search, since GitHub's default squash subject ends with the PR number. Neither source yields a SHA → "kept — unverified (no squash commit found)".

```bash
git -C "${WORK_ROOT}" log --fixed-strings --grep "(#<number>)" --max-count 1 --format=%H "${TARGET_BRANCH}"
git -C "${WORK_ROOT}" merge-base --is-ancestor <squash-sha> "${TARGET_BRANCH}"
git -C "${WORK_ROOT}" fetch "${BASE_REMOTE}" "refs/pull/<number>/head:refs/prheads/<number>"
git -C "${WORK_ROOT}" rev-parse refs/prheads/<number>
```

- `--is-ancestor` exit 0 → the squash commit is in local history. Non-zero → `git -C "${WORK_ROOT}" fetch "${BASE_REMOTE}" "${TARGET_BRANCH}"` and retry once; still non-zero → "kept — unverified (squash commit not in local history)"
- The fetch fails → "kept — unverified (PR head unavailable)", go to Step 6b
- Record the PR head as `PR_HEAD`. **`PR_HEAD` differing from `BRANCH_HEAD` stops the evaluation** — the local branch holds commits the PR never carried, or trails it, so the merge is not evidence about local content. Record "kept — local branch diverges from the merged PR head" and show it with `git -C "${WORK_ROOT}" log --oneline refs/prheads/<number>..refs/heads/<head-branch>`

When the heads match, compute the merge base and take both patch ids:

```bash
git -C "${WORK_ROOT}" merge-base <branch-head> "${TARGET_BRANCH}"
git -C "${WORK_ROOT}" diff <merge-base> <branch-head> | git patch-id --verbatim
git -C "${WORK_ROOT}" diff <squash-sha>^ <squash-sha> | git patch-id --verbatim
```

Each patch-id prints `<patch-id> <commit-id>`. Compare **only the first field** — the second is all zeros for a plain diff and never matches. Both diffs come from the object database, so working-tree line endings do not affect them.

#### Stage 3: Verdict

**Verbatim ids equal** → the content is exactly what landed. Re-read the tip and the worktree map immediately before deleting, since time has passed since Stage 2:

```bash
git -C "${WORK_ROOT}" rev-parse refs/heads/<head-branch>
git -C "${WORK_ROOT}" worktree list --porcelain
git -C "${WORK_ROOT}" branch -D <head-branch>
```

Tip differs from `BRANCH_HEAD`, or the branch is now checked out → keep and report; never delete on stale evidence, and do not run the third command. Proof, protected-set check, and tip re-check together are what make `-D` safe — never run it without all three. Runtimes preferring an atomic compare-and-delete may use `git -C "${WORK_ROOT}" update-ref -d "refs/heads/<head-branch>" <verified-sha>`, which deletes only if the ref still holds that SHA; it has no checked-out-branch guard, so the worktree check stays mandatory.

**Verbatim ids differ** → do not delete. Establish whether the difference is real:

```bash
git -C "${WORK_ROOT}" diff <merge-base> <branch-head> | git patch-id --stable
git -C "${WORK_ROOT}" diff <squash-sha>^ <squash-sha> | git patch-id --stable
```

- Stable ids match → whitespace-only difference. Report "review before deleting" and leave the decision to the user
- Stable ids differ → substantive. Keep, and report what is unaccounted for with `git -C "${WORK_ROOT}" log --oneline "${TARGET_BRANCH}..<head-branch>"` and `git -C "${WORK_ROOT}" diff --stat "${TARGET_BRANCH}...<head-branch>"`

Remove the temporary ref either way, including after a failed verification: `git -C "${WORK_ROOT}" update-ref -d "refs/prheads/<number>"`.

---

### Step 6b: Repo-Wide Branch Sweep

The PR's own branch is not the only one that goes stale. A branch sharing a head under a different name, or a one-commit branch that never got a PR, is invisible to Step 6. Three kinds of state need separate handling.

**Stale remote-tracking refs** linger after the server-side branch is gone and hold no work. Report what `git -C "${WORK_ROOT}" remote prune --dry-run "${BASE_REMOTE}"` would remove, then run `git -C "${WORK_ROOT}" remote prune "${BASE_REMOTE}"` only with the user's agreement.

**Local branches** come from `git -C "${WORK_ROOT}" for-each-ref --format="%(refname:short) %(objectname)" refs/heads`. Two branches printing the same object name are two names for one head: classify the first, apply the same verdict to the other. Build the protected set — never deleted, whatever the content says:

- every branch in the **refreshed** `WORKTREE_BRANCHES` from Step 6, never the Step 1 copy
- `TARGET_BRANCH` and the default branch
- integration branches: `main`, `master`, `develop`, `staging`, `release/*`, `hotfix/*`
- every branch with an open PR (page until the listing is exhausted)

| Class | Test | Action |
|-------|------|--------|
| (a) Ancestor of target | `git -C "${WORK_ROOT}" merge-base --is-ancestor <branch-sha> "${TARGET_BRANCH}"` exits 0 | `git -C "${WORK_ROOT}" branch -d <branch>` — ancestry is proof on its own, and `-d` re-verifies it |
| (b) Squashed into target | Verbatim patch-id equality, or exact tree equality for every path touched | `-D` after the tip re-check |
| (c) Unique content | Neither test passes | Keep; report the commits and files the target lacks |
| (d) Protected | In the set above | Keep, always — do not evaluate content |

**Branches mapping to a PR.** Fetch the merged PR list, paging until the oldest listed PR predates the oldest unclassified branch's last commit — one unpaged page silently misclassifies older branches as unique. Match by `headRefName` equal to the branch name, then by `headRefOid` equal to the branch's object name, which catches a branch that was never the PR's branch but points at the same commit. On a match, run Stage 2 and Stage 3 with that PR's number and merge commit, then delete the temporary ref.

**Branches with no PR.** No squash commit exists to compare against, so compare trees directly. A name-only listing hides deletions, renames, and mode changes — a branch whose only content is a deletion would look empty and be wrongly deleted:

```bash
git -C "${WORK_ROOT}" diff --name-status --find-renames "${TARGET_BRANCH}...<branch>"
git -C "${WORK_ROOT}" ls-tree <branch> -- <path>
git -C "${WORK_ROOT}" ls-tree "${TARGET_BRANCH}" -- <path>
```

`ls-tree` prints mode, type, and hash together, so one command per side settles content and mode at once. Every entry from `--name-status` must be accounted for before deletion: `A`/`M` when the blob hash matches on the target, `D` when the path is absent from both, `R` when the old path is absent and the new path's blob matches, `T` when both sides report the same mode.

- Every entry accounted for → class (b); the work reached the target under a different commit. Delete with `-D` after the tip re-check
- Anything unaccounted for → class (c). Keep, and report every path that did not match. When a path looks superseded rather than lost — the target carries a rewritten or relocated version — say exactly that, name both locations, and let the user decide. Never delete on your own judgment that content "looks superseded"

**Remote branches.** Local cleanup says nothing about the server. List them with `git -C "${WORK_ROOT}" for-each-ref --format="%(refname:short)" "refs/remotes/${BASE_REMOTE}"` and **report** those with no open PR. Remote-tracking refs can be stale, so never delete a remote branch on their evidence: delete only when the user asks, and only the way Step 2 does — read the live tip with `ls-remote`, confirm it against the SHA you verified, and push the deletion under a `--force-with-lease` on that SHA through the remote that owns the branch.

Report each deletion and retention as you go, with the evidence that decided it.

---

### Step 7: Report

Both halves are required.

**Completed:** which PR was merged (number and title) and the squash commit SHA — or that the merge was already complete when the run started; which docs were updated, or "No doc updates needed", with the follow-up PR URL if they went there; the merged branch's outcome (deleted with the matching verbatim patch id, absent, or kept with the reason); and remote branch and remote-tracking ref outcomes.

**Outstanding:**

- Every missing capability and the steps it blocked — an unpushed docs commit, a skipped deletion, a remote branch nobody could delete
- Any remote head branch kept because it moved after the merge, naming the commits that arrived since — that is work someone else pushed, and nobody else is watching for it
- Any documentation left unwritten because no clean `WORK_ROOT` was available
- Every branch left unverified, with the reason
- Any MCP tool substitutions made under `GH_MODE = mcp`

**Branch inventory** — every local branch in this checkout and why it is still there:

| Branch | Class | Evidence | Kept because |
|--------|-------|----------|--------------|
| `main` | protected | — | Target branch |
| `feat/sender-rules` | unique content | 2 commits, 3 files not on target | Not merged anywhere |
| `codex/logo` | unverified | PR head unavailable | Could not prove content landed |

List every branch, including the obviously fine ones — a branch left out of this table is a branch nobody notices for another ten merges. State which checkout the inventory covers: it describes *this* one only, and a container's inventory says nothing about branches on the user's laptop.

---

## Rules

- Never delete a branch without content proof — verbatim patch-id equality, exact blob-and-mode equality for every path touched, or plain ancestry
- `-D` only after that proof, the protected-set check, and a tip re-check taken immediately before deleting. Never delete a branch that is protected, checked out in any worktree, or carrying commits the merged PR did not have
- Never delete on absent evidence — an unreachable remote, a missing squash commit, or an un-deepened shallow clone means "keep and mark unverified"
- Never delete a remote branch on the strength of the merge alone; check the live tip and use a `--force-with-lease` on the SHA you verified
- Never pass `--delete-branch` to `gh pr merge`, and never treat a successful merge command as a merged PR
- Never run a bare `git pull`, `git push`, or `git fetch`, and pass `--repo "${BASE_REPO}"` to every `gh` command — the sole exception is the branch-inference lookup in 1b, which cannot take it
- Resolve in dependency order: repository, then PR, then remotes, then capabilities
- Probe GitHub access, fetch, push, and local checkout separately — never infer one from another
- Steps 3-6b run against `WORK_ROOT`, which Step 3 may move; re-check cleanliness wherever it lands
- Report outstanding work explicitly, and put every local branch in the Step 7 inventory
- Do NOT run build commands — these are doc-only updates after the merge
- Do NOT modify source code files during the doc update step
- Do NOT create new documentation files — only update existing ones
- If the merge fails for ANY reason, STOP and report — do not retry or work around it
- Always `git add <specific files>` — never `git add -A` or `git add .`
- Read files before editing them
- **Never use `cd`**, **never use `$()` or shell variables**, and **never pipe** except `git diff ... | git patch-id ...`
