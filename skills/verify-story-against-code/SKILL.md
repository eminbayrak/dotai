---
name: verify-story-against-code
description: Verify whether a Jira user story is fully and correctly implemented across one or more GitHub repos. Trigger when the user names Jira story IDs (e.g., "check story 68" or "verify stories 68, 69, 70, 452") and asks whether the code matches.
---

# Verify a user story against the code

## When to use this skill

The user names one or more Jira story IDs and asks whether the implementation in GitHub matches what the story specifies. Typical phrasings:

- "verify story 68"
- "check stories 68, 69, 70, 452 across the schedule / cancel / complete services"
- "is this implemented yet"
- "does the code match the ticket"

## What this codebase looks like

The work spans split codebases. Common services include:

- a **schedule appointment** service
- a **cancel appointment** service
- a **complete appointment** service

Each story may touch one, two, or all three. Do not assume the story lives in a single repo.

## Steps

1. **Fetch the story** using the `atlassian` MCP server. For each ID, call the Jira "get issue" tool. Capture:
   - Summary and description
   - Acceptance criteria (often a section in the description or a custom field)
   - Linked issues (subtasks, blocks/is-blocked-by, "implements" links)
   - Linked Confluence pages — fetch those too via the Atlassian server
   - Labels, fix version, and components (these often name the service)

2. **Identify the candidate repos and services**. From the components/labels/links, decide which services the story should touch. If unclear, ask the user which repos to check. Do NOT guess silently.

3. **Search the code** using the `github` MCP server. For each candidate repo:
   - Use code search for keywords from the story (endpoint names, model names, feature flags, ticket ID in commit messages or PR titles).
   - List recent PRs and commits referencing the story ID (e.g., `PROJ-68`, `#68`, "story 68").
   - Read the relevant files end-to-end. Do not infer from filenames.

4. **Map each acceptance criterion to evidence**. Build a table:

   | AC # | Acceptance criterion | Where it's implemented | Status |
   |------|----------------------|------------------------|--------|
   | 1    | ...                  | repo/path:line         | done / partial / missing / cannot-tell |

   Use "cannot-tell" honestly when the code is ambiguous. Never mark something done without a concrete file:line reference.

5. **Check tests**. For each "done" item, confirm a test exists that exercises that behavior. Note tests that are missing.

6. **Report**. Lead with the overall verdict (complete / partial / not started), then the per-AC table, then a short list of concrete follow-ups. Link every claim to a GitHub URL or Jira/Confluence URL.

## Output format

```
## Story PROJ-68 — <summary>
**Verdict:** Partial — 3 of 5 acceptance criteria met.

### Per-AC findings
| AC # | Criterion | Evidence | Status |
| ...  | ...       | ...      | ...    |

### Test coverage
- ...

### Follow-ups
- [ ] ...
```

## Anti-patterns

- Don't trust the story title alone. Read the description and the linked Confluence pages.
- Don't claim a feature is missing just because a grep returned nothing — try alternate names, look at recent merged PRs, and search the other candidate repos.
- Don't summarise "looks good" without per-AC evidence.
