# Skills

Each subfolder is a portable Markdown skill. Any AI coding tool that supports skills (Claude Code, Cowork) or that can be pointed at a system-prompt file (Cursor Rules, VS Code Copilot custom instructions, Codex `AGENTS.md`, Antigravity `.antigravity/rules.md`) can use them.

The skill files are plain Markdown. They describe **when to use the skill** and **what steps to follow** — they call the GitHub and Atlassian MCP tools that `install.sh` wired up.

| Skill | When to use it |
|------|----------------|
| `verify-story-against-code` | Given one or more Jira story IDs, check the codebase and report whether the implementation is complete and correct. |
| `pr-review-against-story` | Given a GitHub PR, fetch the linked Jira story + Confluence specs and review whether the PR satisfies the acceptance criteria. |
| `draft-confluence-from-code` | Given a feature branch or set of commits and a Jira story, draft a Confluence page documenting what was built. |
| `story-to-test-plan` | Given a Jira story (and optionally the implementing code), produce a test plan with concrete cases. |

## How `install.sh` exposes these to each tool

- **Claude Code / Cowork**: copies the skill folders into `~/.claude/skills/` so they're auto-discovered.
- **Cursor**: writes a `.cursor/rules/orch-skills.mdc` file that links to the skill folder.
- **VS Code Copilot**: writes a `.github/copilot-instructions.md` that references the skill folder.
- **Codex CLI**: writes an `AGENTS.md` at the repo root.
- **Antigravity**: writes `.antigravity/rules.md`.

In every case the skill content stays in `skills/` — the per-tool file is a small pointer, so editing a skill once propagates to all tools.
