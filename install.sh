#!/usr/bin/env bash
# dotai — one-command installer (native runtime, no containers)
#
# What it does:
#   1. Checks your .env is filled in.
#   2. Downloads the github-mcp-server Go binary into bin/ for your OS/arch.
#   3. Verifies that `uv` (uvx) is installed; if not, prints the one-line install command.
#   4. Detects which AI coding tools you have and writes the matching MCP config
#      file with REPO_ROOT and tokens substituted in.
#   5. Wires up the skills/ folder for each tool.
#
# Usage:
#   ./install.sh                 # interactive: prompts before overwriting
#   ./install.sh --yes           # non-interactive: overwrite without prompting
#   ./install.sh --dry-run       # show what would happen, don't write anything
#   ./install.sh --tool=cursor   # only install for one tool
#                                # (claude|cursor|vscode|codex|antigravity|windsurf)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
export REPO_ROOT
DRY_RUN=0
YES=0
ONLY_TOOL=""
GH_MCP_VERSION="${GH_MCP_VERSION:-latest}"   # pin by setting e.g. v0.18.0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) YES=1 ;;
    --tool=*) ONLY_TOOL="${arg#--tool=}" ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_blue=$'\033[34m'

say()  { printf "%s\n" "$*"; }
ok()   { printf "${c_green}✓${c_reset} %s\n" "$*"; }
warn() { printf "${c_yellow}!${c_reset} %s\n" "$*"; }
err()  { printf "${c_red}✗${c_reset} %s\n" "$*" >&2; }
step() { printf "\n${c_bold}${c_blue}»${c_reset} ${c_bold}%s${c_reset}\n" "$*"; }

# ─── 1. .env ────────────────────────────────────────────────────────────
step "Pre-flight checks"

if [[ ! -f "$REPO_ROOT/.env" ]]; then
  if [[ -f "$REPO_ROOT/.env.example" ]]; then
    warn ".env not found. Copy .env.example to .env and fill in your tokens:"
    say  "    cp .env.example .env && \$EDITOR .env"
    exit 1
  else
    err ".env and .env.example both missing — is this the dotai repo root?"
    exit 1
  fi
fi
ok ".env present"

# Load env vars from .env so envsubst can use them
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

# Warn on obvious placeholders
warned_placeholder=0
for v in GITHUB_PERSONAL_ACCESS_TOKEN JIRA_API_TOKEN CONFLUENCE_API_TOKEN; do
  val="${!v:-}"
  if [[ -z "$val" || "$val" == *replace_me* ]]; then
    warn "$v still has a placeholder value — the MCP server will fail to authenticate until you fix it."
    warned_placeholder=1
  fi
done
[[ $warned_placeholder -eq 0 ]] && ok "tokens look filled in"

# ─── 2. github-mcp-server binary ────────────────────────────────────────
step "GitHub MCP server binary"

# OS/arch detection mapped to release asset names used by github-mcp-server.
uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Darwin) gh_os="Darwin" ;;
  Linux)  gh_os="Linux"  ;;
  MINGW*|MSYS*|CYGWIN*) gh_os="Windows" ;;
  *)      err "unsupported OS: $uname_s"; exit 1 ;;
esac
case "$uname_m" in
  x86_64|amd64) gh_arch="x86_64" ;;
  arm64|aarch64) gh_arch="arm64" ;;
  *) err "unsupported arch: $uname_m"; exit 1 ;;
esac

bin_dir="$REPO_ROOT/bin"
bin_path="$bin_dir/github-mcp-server"
if [[ "$gh_os" == "Windows" ]]; then bin_path="$bin_path.exe"; fi

if [[ -x "$bin_path" ]]; then
  ok "github-mcp-server already present at $bin_path"
else
  if [[ $DRY_RUN -eq 1 ]]; then
    say "  ${c_dim}(dry-run)${c_reset} would download github-mcp-server $GH_MCP_VERSION for $gh_os/$gh_arch"
  else
    mkdir -p "$bin_dir"
    # Windows ships as .zip, Linux/macOS as .tar.gz
    if [[ "$gh_os" == "Windows" ]]; then
      ext="zip"
    else
      ext="tar.gz"
    fi
    if [[ "$GH_MCP_VERSION" == "latest" ]]; then
      asset_url="https://github.com/github/github-mcp-server/releases/latest/download/github-mcp-server_${gh_os}_${gh_arch}.${ext}"
    else
      asset_url="https://github.com/github/github-mcp-server/releases/download/${GH_MCP_VERSION}/github-mcp-server_${GH_MCP_VERSION#v}_${gh_os}_${gh_arch}.${ext}"
    fi
    say "  downloading $asset_url"
    tmp="$(mktemp -d)"
    archive="$tmp/gh-mcp.$ext"
    if curl -fsSL "$asset_url" -o "$archive"; then
      if [[ "$ext" == "zip" ]]; then
        if command -v unzip >/dev/null 2>&1; then
          unzip -q "$archive" -d "$tmp"
        else
          err "unzip not found. Install it or use install.ps1 on Windows."
          rm -rf "$tmp"; exit 1
        fi
      else
        tar -xzf "$archive" -C "$tmp"
      fi
      # find the binary in the extracted tree
      found=$(find "$tmp" -type f \( -name 'github-mcp-server' -o -name 'github-mcp-server.exe' \) | head -1)
      if [[ -n "$found" ]]; then
        mv "$found" "$bin_path"
        chmod +x "$bin_path"
        ok "installed $bin_path"
      else
        warn "could not locate github-mcp-server binary inside the downloaded archive"
      fi
    else
      warn "download failed. You can install manually:"
      say  "    brew install github-mcp-server   # macOS"
      say  "    or grab the release archive from https://github.com/github/github-mcp-server/releases"
      say  "    and drop it at $bin_path"
    fi
    rm -rf "$tmp"
  fi
fi

# ─── 3. uv / uvx for the Atlassian MCP server ───────────────────────────
step "uv (uvx) for the Atlassian MCP server"

if command -v uvx >/dev/null 2>&1; then
  ok "uvx on PATH ($(uvx --version 2>/dev/null | head -1))"
elif command -v uv >/dev/null 2>&1; then
  ok "uv on PATH; uvx ships with it"
else
  warn "uv (uvx) not found."
  say  "    Install it with one of:"
  say  "      curl -LsSf https://astral.sh/uv/install.sh | sh    # official one-liner"
  say  "      brew install uv                                    # macOS"
  say  "      pipx install uv                                    # any platform with pipx"
  say  "      python3 -m pip install --user uv                   # plain pip"
  say  "    Then re-run ./install.sh — the MCP configs are already written."
fi

# Pre-warm the uvx cache so the first MCP call doesn't time out fetching the package.
if [[ $DRY_RUN -eq 0 ]] && command -v uvx >/dev/null 2>&1; then
  if uvx mcp-atlassian --help >/dev/null 2>&1; then
    ok "uvx cached mcp-atlassian"
  else
    warn "uvx mcp-atlassian --help failed (network blocked, or PyPI unreachable)"
  fi
fi

# ─── 4. Render configs ──────────────────────────────────────────────────
have_envsubst=1
command -v envsubst >/dev/null 2>&1 || have_envsubst=0

render() {
  # render <input-file> <output-file>
  local in="$1" out="$2" tmp
  tmp="$(mktemp)"
  if [[ $have_envsubst -eq 1 ]]; then
    envsubst < "$in" > "$tmp"
  else
    cp "$in" "$tmp"
    for v in REPO_ROOT \
             GITHUB_PERSONAL_ACCESS_TOKEN \
             JIRA_URL JIRA_USERNAME JIRA_API_TOKEN \
             CONFLUENCE_URL CONFLUENCE_USERNAME CONFLUENCE_API_TOKEN \
             JIRA_PROJECTS_FILTER CONFLUENCE_SPACES_FILTER; do
      val="${!v:-}"
      safe=$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')
      sed -i.bak "s|\${$v}|$safe|g" "$tmp" && rm -f "$tmp.bak"
    done
  fi
  install_file "$tmp" "$out"
  rm -f "$tmp"
}

install_file() {
  local src="$1" dst="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "  ${c_dim}(dry-run)${c_reset} would write $dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" ]]; then
    if [[ $YES -eq 0 ]]; then
      read -r -p "  $dst exists. Overwrite? [y/N] " ans
      [[ "$ans" =~ ^[Yy]$ ]] || { warn "skipped $dst"; return; }
    fi
    cp "$dst" "$dst.bak.$(date +%s)"
  fi
  cp "$src" "$dst"
  ok "wrote $dst"
}

# ─── 5. Detect & install per tool ───────────────────────────────────────
step "Detecting AI coding tools"

want_tool() {
  [[ -z "$ONLY_TOOL" || "$ONLY_TOOL" == "$1" ]]
}

# Claude Code
if want_tool claude && (command -v claude >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]); then
  ok "Claude Code detected"
  render "$REPO_ROOT/mcp/claude-code.json" "$REPO_ROOT/.mcp.json"
  if [[ -d "$HOME/.claude" ]]; then
    mkdir -p "$HOME/.claude/skills"
    for d in "$REPO_ROOT/skills/"*/; do
      name=$(basename "$d")
      [[ "$name" == "README.md" ]] && continue
      if [[ $DRY_RUN -eq 1 ]]; then
        say "  ${c_dim}(dry-run)${c_reset} would symlink $d -> ~/.claude/skills/$name"
      else
        ln -sfn "$d" "$HOME/.claude/skills/$name"
        ok "linked skill ~/.claude/skills/$name"
      fi
    done
  fi
fi

# Cursor
if want_tool cursor && (command -v cursor >/dev/null 2>&1 || [[ -d "$HOME/.cursor" ]] || [[ -d "$HOME/Library/Application Support/Cursor" ]]); then
  ok "Cursor detected"
  render "$REPO_ROOT/mcp/cursor.json" "$REPO_ROOT/.cursor/mcp.json"
  mkdir -p "$REPO_ROOT/.cursor/rules"
  cat > "$REPO_ROOT/.cursor/rules/dotai-skills.mdc" <<'MDC'
---
description: dotai — story verification, PR review, Confluence drafting, test plans
alwaysApply: false
---
This project ships four skills in the `skills/` folder. When the user asks to
verify a story, review a PR against a story, draft Confluence docs, or build a
test plan, read the matching `skills/<name>/SKILL.md` and follow its steps. Use
the `github` and `atlassian` MCP servers configured in `.cursor/mcp.json`.
MDC
  ok "wrote .cursor/rules/dotai-skills.mdc"
fi

# VS Code
if want_tool vscode && (command -v code >/dev/null 2>&1 || [[ -d "$HOME/Library/Application Support/Code" ]] || [[ -d "$HOME/.config/Code" ]]); then
  ok "VS Code detected"
  render "$REPO_ROOT/mcp/vscode.json" "$REPO_ROOT/.vscode/mcp.json"
  mkdir -p "$REPO_ROOT/.github"
  cat > "$REPO_ROOT/.github/copilot-instructions.md" <<'MD'
# Copilot custom instructions — dotai

This repo wires up two MCP servers in `.vscode/mcp.json`: `github` and
`atlassian`. It also ships four skills in `skills/`:

- `verify-story-against-code` — given Jira story IDs, check the code.
- `pr-review-against-story` — review a PR against its linked story.
- `draft-confluence-from-code` — write a Confluence page from code + ticket.
- `story-to-test-plan` — turn a story into concrete test cases.

When the user's request matches one of these, open the corresponding
`skills/<name>/SKILL.md` and follow its steps. Always cite GitHub and
Atlassian URLs for the claims you make.
MD
  ok "wrote .github/copilot-instructions.md"
fi

# Codex CLI
if want_tool codex && (command -v codex >/dev/null 2>&1 || [[ -d "$HOME/.codex" ]]); then
  ok "Codex CLI detected"
  render "$REPO_ROOT/mcp/codex.toml" "$REPO_ROOT/.codex/config.toml"
  cat > "$REPO_ROOT/AGENTS.md" <<'MD'
# Agent instructions — dotai

This repo configures two MCP servers (`github`, `atlassian`) via
`.codex/config.toml`. It ships four skills in `skills/`:

- `verify-story-against-code`
- `pr-review-against-story`
- `draft-confluence-from-code`
- `story-to-test-plan`

When a user request matches one of these, read `skills/<name>/SKILL.md` and
follow its steps. Always cite GitHub and Atlassian URLs for the claims you
make.
MD
  ok "wrote AGENTS.md"
fi

# Antigravity
if want_tool antigravity && (command -v antigravity >/dev/null 2>&1 || [[ -d "$HOME/Library/Application Support/Antigravity" ]] || [[ -d "$HOME/.antigravity" ]]); then
  ok "Antigravity detected"
  render "$REPO_ROOT/mcp/antigravity.json" "$REPO_ROOT/.antigravity/mcp_config.json"
  mkdir -p "$REPO_ROOT/.antigravity"
  cat > "$REPO_ROOT/.antigravity/rules.md" <<'MD'
# Antigravity rules — dotai

MCP servers configured in `.antigravity/mcp_config.json`: `github`, `atlassian`.
Skills live in `skills/`. When the user's request maps to one of:
verify-story-against-code, pr-review-against-story, draft-confluence-from-code,
story-to-test-plan — read `skills/<name>/SKILL.md` and follow it.
MD
  ok "wrote .antigravity/rules.md"
fi

# Windsurf
if want_tool windsurf && (command -v windsurf >/dev/null 2>&1 || [[ -d "$HOME/.codeium/windsurf" ]]); then
  ok "Windsurf detected"
  render "$REPO_ROOT/mcp/cursor.json" "$REPO_ROOT/.codeium/windsurf/mcp_config.json"
fi

step "Done"
say "Open this repo in your AI coding tool and ask:"
say "    ${c_bold}\"verify story PROJ-68 against the code\"${c_reset}"
say ""
say "If your tool wasn't detected, force it:"
say "    ./install.sh --tool=cursor"
