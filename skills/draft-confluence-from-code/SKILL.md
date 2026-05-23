---
name: draft-confluence-from-code
description: Draft a Confluence documentation page from a Jira story plus the code that implements it. Trigger when the user asks to "document" or "write up" a finished feature, or to "draft a Confluence page" for a story.
---

# Draft a Confluence page from code + ticket

## When to use this skill

The user wants documentation for a feature that has already been built. Phrasings:

- "draft a Confluence page for PROJ-68"
- "write up the cancellation flow we just shipped"
- "document this feature for the team"

## Steps

1. **Pull the source material**:
   - Jira story via `atlassian` MCP (summary, description, ACs, linked pages).
   - Merged PRs that closed the story via `github` MCP (read the diff and the PR description).
   - Any existing Confluence page on the same topic — if one exists, prefer **updating** it over creating a duplicate. Always ask before overwriting.

2. **Decide the page structure**. Use the team's existing template if you can find one in the same Confluence space. Otherwise use this default:

   - **Overview** — one paragraph: what this feature is, who it's for, the story key.
   - **How it works** — request flow, key endpoints, key state transitions. Use a Mermaid block if the flow has branches.
   - **APIs / interfaces** — endpoint signatures, request/response shape, error codes. Pull from the merged diff, not from your memory.
   - **Configuration** — env vars, feature flags, any new infra.
   - **Operational notes** — known failure modes, what to check when oncall, links to dashboards if referenced.
   - **Open questions** — anything the code left ambiguous. Better to list than to invent.

3. **Cite the source of every claim**. Inline link to the PR file + line for technical claims, the Jira story for behavioral claims, prior Confluence pages for design context.

4. **Create or update the page** via the `atlassian` MCP server's Confluence create/update tool. Use the space and parent page the user specifies. If the user didn't say, ask.

5. **Link back from Jira**. Add the new page URL to the story (either as a comment or a "documentation" link).

## Anti-patterns

- Don't write generic "this feature lets users do X" prose. Be concrete: name the endpoints, the queue topics, the exact env vars.
- Don't invent details the code doesn't show. If you can't tell whether the retry is exponential or linear, say "see `RetryPolicy` in `cancel.ts:120`" rather than asserting.
- Don't publish without showing the user a preview of the page body for sign-off.
