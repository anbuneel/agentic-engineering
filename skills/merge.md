# Merge & Document

Squash-merge the current PR and update all project documentation. Follow these steps exactly:

1. Identify the current branch and its associated PR
2. Squash-merge the PR branch into main using `gh pr merge --squash`
3. Switch to main and pull the latest changes
4. Update project progress docs (README, CHANGELOG, any tracking docs) to reflect the completed work
5. Update CLAUDE.md if any new patterns, conventions, or learnings emerged from the merged PR
6. Commit the doc updates with a message like "docs: update progress after merging PR #XX"
7. Push all changes to remote
8. Delete the merged branch locally if it still exists

Rules:
- Do NOT run build commands — these are doc-only updates after the merge
- Do NOT modify any source code files during the doc update step
- If the merge fails due to conflicts, STOP and report the conflicts — do not attempt to resolve them without user input
- If there is no CHANGELOG, skip that step
- Summarize what was merged and what docs were updated when done
