# orch

A portable connector pack that hooks any AI coding tool — Claude Code, Cursor, VS Code (Copilot / Continue), Codex CLI, Google Antigravity, Windsurf — into **GitHub**, **Jira**, and **Confluence**. Plus four pre-built skills for the workflows you actually do day to day.

No Docker. No Podman. The MCP servers run natively: a small Go binary for GitHub and `uvx mcp-atlassian` for Atlassian. Personal tokens come from your local `.env`.

Works on **macOS, Linux, and Windows**. Set it up once. Hand the repo to a teammate, they clone, fill in `.env`, run the installer for their OS, and they're done.

## What you get

**Two MCP servers**, configured identically across every tool:

- `github` — the official [GitHub MCP server](https://github.com/github/github-mcp-server). `install.sh` downloads the prebuilt Go binary into `bin/` for your OS and arch. Reads/writes repos, issues, PRs, commits.
- `atlassian` — [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian) via `uvx mcp-atlassian`. Covers Jira Cloud and Confluence Cloud with API-token auth.

**Four skills**, written as portable Markdown that any AI coding tool can read:

- `verify-story-against-code` — given Jira story IDs (the example: 68, 69, 70, 452 across the schedule / cancel / complete services), check whether the implementation matches.
- `pr-review-against-story` — given a PR, fetch its linked story and review the diff against the acceptance criteria.
- `draft-confluence-from-code` — generate a Confluence page from a merged story + the code that closed it.
- `story-to-test-plan` — turn a story into concrete test cases.

**Two installers** doing the same job, one per OS:

- `install.sh` for macOS / Linux / WSL / Git Bash
- `install.ps1` for native Windows PowerShell

Both auto-detect which AI tools you have, download the GitHub binary, verify `uv`, and write the right config file in the right place for each tool. No manual JSON-pasting per tool.

## Repo layout

```
orch/
├── README.md                   # you are here
├── .env.example                # tokens to fill in
├── install.sh                  # one-command setup
├── bin/                        # populated by installer (gitignored)
│   └── github-mcp-server       # downloaded binary
├── mcp/                        # MCP config templates, one per tool
│   ├── claude-code.json
│   ├── cursor.json
│   ├── vscode.json
│   ├── codex.toml
│   └── antigravity.json
└── skills/                     # portable skills used by all tools
    ├── verify-story-against-code/SKILL.md
    ├── pr-review-against-story/SKILL.md
    ├── draft-confluence-from-code/SKILL.md
    └── story-to-test-plan/SKILL.md
```

## Quick start

### 1. Prerequisites

- **`uv`** for the Atlassian MCP server. One-line install:
  - macOS / Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
  - Windows PowerShell: `irm https://astral.sh/uv/install.ps1 | iex`
  - or via your package manager: `brew install uv`, `winget install astral-sh.uv`, `scoop install uv`, `pipx install uv`.
- Whichever AI coding tool(s) you use, installed.
- A **GitHub Personal Access Token**. Create at https://github.com/settings/tokens. Scopes: `repo`, `read:org`, `workflow`.
- An **Atlassian API token**. Create at https://id.atlassian.com/manage-profile/security/api-tokens.

The GitHub MCP server binary is downloaded automatically by the installer. No separate install needed.

### 2. Clone and configure

macOS / Linux:
```bash
git clone <this repo> orch
cd orch
cp .env.example .env
$EDITOR .env          # paste your tokens
```

Windows (PowerShell):
```powershell
git clone <this repo> orch
cd orch
Copy-Item .env.example .env
notepad .env          # paste your tokens
```

### 3. Install

macOS / Linux / WSL / Git Bash:
```bash
./install.sh
```

Windows PowerShell:
```powershell
.\install.ps1
```

If PowerShell blocks the script with an execution-policy error, run it once with:
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

1. Verifies your `.env` is filled in.
2. Downloads the `github-mcp-server` Go binary into `bin/` for your OS and arch.
3. Confirms `uv` is installed; prints the install command if not.
4. Pre-warms the `uvx mcp-atlassian` cache.
5. Detects which AI coding tools are present.
6. Renders the right config file for each tool, with `REPO_ROOT` and your tokens substituted in.
7. Symlinks the `skills/` folder into wherever that tool looks for skills.

Options (both installers):

| bash | PowerShell | What it does |
|------|-----------|-------------|
| `--dry-run` | `-DryRun` | Show what would happen without writing anything. |
| `--yes` | `-Yes` | Overwrite existing configs without prompting. |
| `--tool=cursor` | `-Tool cursor` | Only install for one tool. |
| `GH_MCP_VERSION=v0.18.0 ./install.sh` | `.\install.ps1 -GhMcpVersion v0.18.0` | Pin to a specific GitHub MCP release. |

### 4. Try it

Open the repo in your AI tool and ask:

> verify story PROJ-68 against the code

or

> review PR #123 against its linked Jira story

The tool will load the matching skill and use the `github` / `atlassian` MCP servers to do the work.

## How each tool sees the skills

| Tool | MCP config | Skills exposed via |
|------|-----------|--------------------|
| Claude Code | `.mcp.json` | symlinks in `~/.claude/skills/` |
| Cursor | `.cursor/mcp.json` | `.cursor/rules/orch-skills.mdc` |
| VS Code (Copilot) | `.vscode/mcp.json` | `.github/copilot-instructions.md` |
| Codex CLI | `.codex/config.toml` | `AGENTS.md` at repo root |
| Antigravity | `.antigravity/mcp_config.json` | `.antigravity/rules.md` |
| Windsurf | `.codeium/windsurf/mcp_config.json` | (uses Cursor-style rules) |

The skill content stays in `skills/`. Each per-tool file is a small pointer, so editing a skill once propagates everywhere.

## Sharing with teammates

Push the repo to your team's GitHub org. The committed files are safe — they reference `${VAR}` placeholders, not real tokens, and `bin/`, `.env`, and the rendered per-tool configs are all gitignored. Each teammate:

```bash
git clone <repo>
cd <repo>
cp .env.example .env
$EDITOR .env
./install.sh
```

Personal tokens never leave the developer's machine.

## Customising

- **Add a new skill** — drop `skills/your-skill/SKILL.md` and re-run `./install.sh`. The auto-generated per-tool pointer files reference the whole folder, so new skills appear automatically.
- **Add a new MCP server** — append a server entry to each template in `mcp/` and re-run the installer. Examples: Linear, Slack, Sentry, Datadog.
- **Switch to OAuth / remote servers** — see `mcp/README.md`. Swap each server block for `{ "type": "http", "url": "..." }`.
- **Self-hosted Atlassian** — `sooperset/mcp-atlassian` supports Data Center too. Set `JIRA_URL` and `CONFLUENCE_URL` to your on-prem hostname; the API token field accepts PATs.

## Security notes

- `.env` is in `.gitignore`. Never commit real tokens.
- The Atlassian MCP server respects your account's existing project / space permissions — it can't see anything you can't.
- `JIRA_PROJECTS_FILTER` and `CONFLUENCE_SPACES_FILTER` in `.env` further restrict what the MCP server will expose to the AI.
- Skills tell the AI to **always cite** GitHub / Atlassian URLs for its claims, so you can trace anything it says back to a source.
- For VS Code, the rendered `.vscode/mcp.json` uses `${env:VAR}` references instead of inlining the token, so the token never lands in a config file.

## Troubleshooting

**`uvx: command not found`** — install `uv`: `curl -LsSf https://astral.sh/uv/install.sh | sh`. Then open a new shell or `source ~/.local/bin/env`.

**`github-mcp-server` failed to download** — check network, or grab the archive manually from https://github.com/github/github-mcp-server/releases and extract it to `bin/github-mcp-server`. On macOS you can also `brew install github-mcp-server` and the installer will pick that up next run.

**`401 Unauthorized` from Atlassian** — your API token has expired, or `JIRA_USERNAME` is wrong. Atlassian Cloud uses your **email**, not your display name. Regenerate at id.atlassian.com.

**`Bad credentials` from GitHub** — PAT expired or missing scopes. Recreate with `repo`, `read:org`, `workflow`.

**My AI tool didn't get detected** — run `./install.sh --tool=<name>` to force it. Supported: `claude`, `cursor`, `vscode`, `codex`, `antigravity`, `windsurf`.

**MCP server times out on first call** — the first `uvx mcp-atlassian` invocation downloads the package. The installer pre-warms it; if it failed, run `uvx mcp-atlassian --help` once manually.

**Windows: `install.ps1 cannot be loaded because running scripts is disabled`** — run with `powershell -ExecutionPolicy Bypass -File .\install.ps1`, or set the policy for your user once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

**Windows: skills folder shows up as a copy instead of a symlink** — Windows requires Developer Mode or admin rights to create symlinks. The installer falls back to copying. To re-link instead, enable Developer Mode (Settings → For developers) and re-run `install.ps1`.
