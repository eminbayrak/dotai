---
name: pr-review-against-story
description: Review a GitHub pull request against its linked Jira story and Confluence specs. Trigger when the user shares a PR URL or PR number and asks for review, acceptance-criteria check, or whether it's ready to merge.
---

# Review a PR against its linked story

## When to use this skill

The user shares a GitHub PR (URL, number, or "the PR I just opened") and asks whether it satisfies the linked Jira story. Phrasings:

- "review PR #123"
- "does this PR cover the story"
- "is this ready to merge"
- "what's missing from this PR vs the ticket"

## Steps

1. **Fetch the PR** via the `github` MCP server:
   - Title, description, base/head branches
   - File diff (request the patch, not just the file list)
   - Linked issues from the PR body (`Closes PROJ-123`, `Fixes #456`)
   - Existing review comments and CI status

2. **Find the linked Jira story**. Look in this order:
   - Explicit ticket key in PR title or body
   - Branch name (e.g., `feature/PROJ-123-...`)
   - First commit message
   - If still unclear, ask the user.

3. **Fetch the story and any linked Confluence pages** via the `atlassian` MCP server. Pull the same fields as in `verify-story-against-code`: acceptance criteria, linked specs, components.

4. **Diff-by-AC review**. For each acceptance criterion, scan the diff for the file(s) that should implement it. Note:
   - Hits (file path, hunk, brief explanation of how it satisfies the AC)
   - Misses (the AC has no corresponding change in the diff)
   - Risks (the change is there but looks wrong — naming, edge case missing, no error handling)

5. **Check for cross-service ripple**. If the story spans multiple services (schedule / cancel / complete), confirm the PR either touches all relevant ones or has companion PRs. If companions are missing, flag it.

6. **Tests**. Verify each new behavior has a test. Flag PRs that modify business logic without adding tests.

7. **Comment-ready output**. Format the review so it can be pasted into the PR conversation:

```
## Story coverage: PROJ-123
- [x] AC1 — <one-line confirmation> (`src/foo.ts:42`)
- [ ] AC2 — not implemented in this PR
- [!] AC3 — implemented but missing null-check on `appointment.id` (`src/bar.ts:88`)

## Tests
- Missing test for the empty-state branch in `cancel.ts`.

## Suggested follow-ups
- ...
```

## Anti-patterns

- Don't approve a PR just because CI is green and the diff is small. Always map back to ACs.
- Don't review only the changed files in isolation — open the surrounding code if the change interacts with it.
- Don't speculate that "the rest is probably in another PR" without checking.
