# MCP config templates

Each file is a template for a specific AI coding tool. `install.sh` reads your `.env`, substitutes the placeholders, and writes the rendered file to the location that tool expects.

| Tool | Template | Installed to |
|------|----------|--------------|
| Claude Code | `claude-code.json` | `<repo>/.mcp.json` (project scope) |
| Cursor | `cursor.json` | `<repo>/.cursor/mcp.json` |
| VS Code (Copilot / Continue) | `vscode.json` | `<repo>/.vscode/mcp.json` |
| Codex CLI | `codex.toml` | `<repo>/.codex/config.toml` |
| Google Antigravity | `antigravity.json` | `<repo>/.antigravity/mcp_config.json` |
| Windsurf | `cursor.json` (same schema) | `<repo>/.codeium/windsurf/mcp_config.json` |

All five templates wire up the same two MCP servers, both running natively (no containers):

- **`github`** — the official [GitHub MCP server](https://github.com/github/github-mcp-server) as a prebuilt Go binary. `install.sh` downloads it into `<repo>/bin/github-mcp-server` for your OS and arch.
- **`atlassian`** — [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian) via `uvx mcp-atlassian`. `uvx` fetches and caches the Python package on first run.

## Placeholders

The templates use two kinds of placeholders that `install.sh` substitutes:

- `${REPO_ROOT}` — the absolute path of this repo on the current machine.
- `${GITHUB_PERSONAL_ACCESS_TOKEN}`, `${JIRA_URL}`, etc. — values from your `.env`.

VS Code's template uses `${env:VAR}` for tokens instead, which VS Code resolves at runtime — slightly nicer because the rendered file doesn't contain the literal token.

## Want OAuth / remote servers instead?

If you'd rather use the hosted servers (no local install, OAuth instead of tokens), swap each server block for:

```json
"github":    { "type": "http", "url": "https://api.githubcopilot.com/mcp/" }
"atlassian": { "type": "http", "url": "https://mcp.atlassian.com/v1/mcp/authv2" }
```

Each tool will prompt you to authorize in a browser the first time. Trade-off: no `.env`, but every teammate has to re-authorize on each device.
