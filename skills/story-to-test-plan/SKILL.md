---
name: story-to-test-plan
description: Turn a Jira user story (and, if available, the implementing code) into a concrete test plan. Trigger when the user asks for test cases, a test plan, or QA scenarios for a story.
---

# Turn a story into a test plan

## When to use this skill

The user wants test coverage for an in-flight or shipped story. Phrasings:

- "write a test plan for PROJ-68"
- "what should QA test on the cancel flow"
- "give me test cases for stories 68 and 70"

## Steps

1. **Fetch the story** via `atlassian` MCP. Capture summary, description, ACs, linked Confluence specs.

2. **If implementing code exists**, fetch it via `github` MCP. Look at:
   - The endpoint signatures and request validation (these reveal edge cases).
   - Branching logic (each branch should have at least one positive and one negative test).
   - Error paths (every `throw` / `return error` is a test case).

3. **Build the plan as a table**. Group by AC, then list:

   | # | Case | Type | Preconditions | Steps | Expected | Priority |
   |---|------|------|---------------|-------|----------|----------|

   - **Type** = `unit` / `integration` / `e2e` / `manual`.
   - **Priority** = P0 (blocks merge), P1 (should pass for release), P2 (nice to have).
   - Include both **happy paths** and **edge cases**: empty input, max-length input, concurrent requests, auth missing, downstream service down, partial failure mid-transaction.

4. **Cross-service scenarios**. If the story touches schedule + cancel + complete, include at least one end-to-end case that exercises the full lifecycle, and one rollback case where a downstream step fails.

5. **Output**:

```
## Test plan — PROJ-68 <summary>

### AC1: <criterion>
| # | Case | Type | ... |

### AC2: <criterion>
...

### Cross-cutting / non-functional
- Auth: ...
- Performance: ...
- Observability: ...
```

6. **Offer to file the plan**. Ask whether the user wants this added as a comment on the Jira story, as a new Confluence page (use the `draft-confluence-from-code` skill's create step), or kept in chat.

## Anti-patterns

- Don't list test cases that map 1:1 to ACs with no edge cases. The point of a test plan is to surface what an AC implies but doesn't state.
- Don't assume framework. Ask whether tests will be in Jest / Vitest / pytest / Go's `testing` etc. if it affects how you phrase the "Steps" column.
