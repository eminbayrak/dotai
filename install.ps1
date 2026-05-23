#Requires -Version 5.1
<#
.SYNOPSIS
    orch — Windows installer (PowerShell). Native runtime, no containers.

.DESCRIPTION
    Downloads the github-mcp-server.exe binary, verifies uv (uvx),
    detects which AI coding tools are installed, and writes the matching
    MCP config file for each with your tokens and REPO_ROOT substituted in.

.PARAMETER DryRun
    Show what would happen, don't write anything.

.PARAMETER Yes
    Overwrite existing configs without prompting.

.PARAMETER Tool
    Only install for one tool: claude, cursor, vscode, codex, antigravity, or windsurf.

.PARAMETER GhMcpVersion
    Pin a specific github-mcp-server release tag (default: latest).

.EXAMPLE
    .\install.ps1
    .\install.ps1 -DryRun
    .\install.ps1 -Yes -Tool cursor
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Yes,
    [ValidateSet('claude','cursor','vscode','codex','antigravity','windsurf','')]
    [string]$Tool = '',
    [string]$GhMcpVersion = 'latest'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:REPO_ROOT = $RepoRoot

function Step($msg) { Write-Host ""; Write-Host "» $msg" -ForegroundColor Blue }
function Ok($msg)   { Write-Host "✓ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "! $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "✗ $msg" -ForegroundColor Red }
function Say($msg)  { Write-Host $msg }

# ─── 1. .env ────────────────────────────────────────────────────────────
Step "Pre-flight checks"

$EnvFile = Join-Path $RepoRoot '.env'
$EnvExample = Join-Path $RepoRoot '.env.example'

if (-not (Test-Path $EnvFile)) {
    if (Test-Path $EnvExample) {
        Warn ".env not found. Copy .env.example to .env and fill in your tokens:"
        Say  "    Copy-Item .env.example .env ; notepad .env"
        exit 1
    } else {
        Err ".env and .env.example both missing — is this the orch repo root?"
        exit 1
    }
}
Ok ".env present"

# Parse .env (KEY=VALUE per line, # for comments)
$EnvVars = @{}
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim('"').Trim("'")
            $EnvVars[$key] = $val
            Set-Item -Path "env:$key" -Value $val
        }
    }
}

# Warn on placeholders
$WarnedPlaceholder = $false
foreach ($v in 'GITHUB_PERSONAL_ACCESS_TOKEN','JIRA_API_TOKEN','CONFLUENCE_API_TOKEN') {
    $val = $EnvVars[$v]
    if (-not $val -or $val -match 'replace_me') {
        Warn "$v still has a placeholder value — the MCP server will fail to authenticate until you fix it."
        $WarnedPlaceholder = $true
    }
}
if (-not $WarnedPlaceholder) { Ok "tokens look filled in" }

# ─── 2. github-mcp-server binary ────────────────────────────────────────
Step "GitHub MCP server binary"

# Detect arch
$Arch = if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x86_64' }
} else { 'x86_64' }

$BinDir = Join-Path $RepoRoot 'bin'
$BinPath = Join-Path $BinDir 'github-mcp-server.exe'

if (Test-Path $BinPath) {
    Ok "github-mcp-server.exe already present at $BinPath"
} elseif ($DryRun) {
    Say "  (dry-run) would download github-mcp-server $GhMcpVersion for Windows/$Arch"
} else {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    if ($GhMcpVersion -eq 'latest') {
        $AssetUrl = "https://github.com/github/github-mcp-server/releases/latest/download/github-mcp-server_Windows_${Arch}.zip"
    } else {
        $stripped = $GhMcpVersion.TrimStart('v')
        $AssetUrl = "https://github.com/github/github-mcp-server/releases/download/$GhMcpVersion/github-mcp-server_${stripped}_Windows_${Arch}.zip"
    }
    Say "  downloading $AssetUrl"
    $Tmp = Join-Path $env:TEMP "orch-gh-mcp-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
    $ZipPath = Join-Path $Tmp 'gh-mcp.zip'
    try {
        Invoke-WebRequest -Uri $AssetUrl -OutFile $ZipPath -UseBasicParsing
        Expand-Archive -Path $ZipPath -DestinationPath $Tmp -Force
        $Found = Get-ChildItem -Path $Tmp -Recurse -Filter 'github-mcp-server.exe' | Select-Object -First 1
        if ($Found) {
            Move-Item -Path $Found.FullName -Destination $BinPath -Force
            Ok "installed $BinPath"
        } else {
            Warn "could not locate github-mcp-server.exe inside the downloaded archive"
        }
    } catch {
        Warn "download failed: $_"
        Say  "    grab the .zip manually from https://github.com/github/github-mcp-server/releases"
        Say  "    and place github-mcp-server.exe at $BinPath"
    } finally {
        Remove-Item -Recurse -Force -Path $Tmp -ErrorAction SilentlyContinue
    }
}

# ─── 3. uv / uvx ────────────────────────────────────────────────────────
Step "uv (uvx) for the Atlassian MCP server"

if (Get-Command uvx -ErrorAction SilentlyContinue) {
    $uvxVer = (& uvx --version 2>$null | Select-Object -First 1)
    Ok "uvx on PATH ($uvxVer)"
} elseif (Get-Command uv -ErrorAction SilentlyContinue) {
    Ok "uv on PATH; uvx ships with it"
} else {
    Warn "uv (uvx) not found."
    Say  "    Install it with one of:"
    Say  "      powershell -c 'irm https://astral.sh/uv/install.ps1 | iex'   # official one-liner"
    Say  "      winget install --id=astral-sh.uv -e"
    Say  "      scoop install uv"
    Say  "      pipx install uv"
    Say  "    Then re-run .\install.ps1 — the MCP configs are already written."
}

if (-not $DryRun -and (Get-Command uvx -ErrorAction SilentlyContinue)) {
    try {
        $null = & uvx mcp-atlassian --help 2>&1
        if ($LASTEXITCODE -eq 0) { Ok "uvx cached mcp-atlassian" }
        else { Warn "uvx mcp-atlassian --help failed (network blocked, or PyPI unreachable)" }
    } catch { Warn "uvx mcp-atlassian probe failed: $_" }
}

# ─── 4. Render configs ──────────────────────────────────────────────────
# Path going into JSON. Forward slashes work on Windows and avoid backslash escaping.
$RepoRootForward = $RepoRoot -replace '\\','/'

function Render-Template {
    param([string]$Src, [string]$Dst)
    $content = Get-Content -Raw -Path $Src
    # Substitute ${REPO_ROOT} with the forward-slash version
    $content = $content -replace '\$\{REPO_ROOT\}', [Regex]::Escape($RepoRootForward).Replace('\','\\')
    # Actually, simpler: direct string replace (avoids regex pitfalls)
    $content = (Get-Content -Raw -Path $Src)
    $content = $content.Replace('${REPO_ROOT}', $RepoRootForward)
    foreach ($k in $EnvVars.Keys) {
        $content = $content.Replace('${' + $k + '}', $EnvVars[$k])
    }
    Install-File -Content $content -Dst $Dst
}

function Install-File {
    param([string]$Content, [string]$Dst)
    if ($DryRun) { Say "  (dry-run) would write $Dst"; return }
    $dstDir = Split-Path -Parent $Dst
    if ($dstDir) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    if (Test-Path $Dst) {
        if (-not $Yes) {
            $ans = Read-Host "  $Dst exists. Overwrite? [y/N]"
            if ($ans -notmatch '^[Yy]$') { Warn "skipped $Dst"; return }
        }
        Copy-Item -Path $Dst -Destination "$Dst.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())" -Force
    }
    Set-Content -Path $Dst -Value $Content -NoNewline -Encoding UTF8
    Ok "wrote $Dst"
}

function Want-Tool($name) { return ($Tool -eq '' -or $Tool -eq $name) }

# ─── 5. Detect & install per tool ───────────────────────────────────────
Step "Detecting AI coding tools"

# Claude Code
$claudeDir = Join-Path $env:USERPROFILE '.claude'
if ((Want-Tool 'claude') -and ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path $claudeDir))) {
    Ok "Claude Code detected"
    Render-Template (Join-Path $RepoRoot 'mcp\claude-code.json') (Join-Path $RepoRoot '.mcp.json')
    if (Test-Path $claudeDir) {
        $skillsTarget = Join-Path $claudeDir 'skills'
        New-Item -ItemType Directory -Force -Path $skillsTarget | Out-Null
        Get-ChildItem (Join-Path $RepoRoot 'skills') -Directory | ForEach-Object {
            $link = Join-Path $skillsTarget $_.Name
            if ($DryRun) { Say "  (dry-run) would link $($_.FullName) -> $link" }
            else {
                if (Test-Path $link) { Remove-Item -Recurse -Force $link }
                # SymbolicLink requires admin or Developer Mode on Windows; fall back to copy
                try {
                    New-Item -ItemType SymbolicLink -Path $link -Target $_.FullName -ErrorAction Stop | Out-Null
                    Ok "linked skill $link"
                } catch {
                    Copy-Item -Recurse -Path $_.FullName -Destination $link -Force
                    Ok "copied skill $link (symlink needs Developer Mode)"
                }
            }
        }
    }
}

# Cursor
$cursorDir = Join-Path $env:USERPROFILE '.cursor'
$cursorAppData = Join-Path $env:APPDATA 'Cursor'
if ((Want-Tool 'cursor') -and ((Get-Command cursor -ErrorAction SilentlyContinue) -or (Test-Path $cursorDir) -or (Test-Path $cursorAppData))) {
    Ok "Cursor detected"
    Render-Template (Join-Path $RepoRoot 'mcp\cursor.json') (Join-Path $RepoRoot '.cursor\mcp.json')
    $rulesDir = Join-Path $RepoRoot '.cursor\rules'
    New-Item -ItemType Directory -Force -Path $rulesDir | Out-Null
    @'
---
description: orch — story verification, PR review, Confluence drafting, test plans
alwaysApply: false
---
This project ships four skills in the `skills/` folder. When the user asks to
verify a story, review a PR against a story, draft Confluence docs, or build a
test plan, read the matching `skills/<name>/SKILL.md` and follow its steps. Use
the `github` and `atlassian` MCP servers configured in `.cursor/mcp.json`.
'@ | Set-Content -Path (Join-Path $rulesDir 'orch-skills.mdc') -Encoding UTF8
    Ok "wrote .cursor\rules\orch-skills.mdc"
}

# VS Code
$vscodeAppData = Join-Path $env:APPDATA 'Code'
if ((Want-Tool 'vscode') -and ((Get-Command code -ErrorAction SilentlyContinue) -or (Test-Path $vscodeAppData))) {
    Ok "VS Code detected"
    Render-Template (Join-Path $RepoRoot 'mcp\vscode.json') (Join-Path $RepoRoot '.vscode\mcp.json')
    $ghDir = Join-Path $RepoRoot '.github'
    New-Item -ItemType Directory -Force -Path $ghDir | Out-Null
    @'
# Copilot custom instructions — orch

This repo wires up two MCP servers in `.vscode/mcp.json`: `github` and
`atlassian`. It also ships four skills in `skills/`:

- `verify-story-against-code` — given Jira story IDs, check the code.
- `pr-review-against-story` — review a PR against its linked story.
- `draft-confluence-from-code` — write a Confluence page from code + ticket.
- `story-to-test-plan` — turn a story into concrete test cases.

When the user's request matches one of these, open the corresponding
`skills/<name>/SKILL.md` and follow its steps. Always cite GitHub and
Atlassian URLs for the claims you make.
'@ | Set-Content -Path (Join-Path $ghDir 'copilot-instructions.md') -Encoding UTF8
    Ok "wrote .github\copilot-instructions.md"
}

# Codex CLI
$codexDir = Join-Path $env:USERPROFILE '.codex'
if ((Want-Tool 'codex') -and ((Get-Command codex -ErrorAction SilentlyContinue) -or (Test-Path $codexDir))) {
    Ok "Codex CLI detected"
    Render-Template (Join-Path $RepoRoot 'mcp\codex.toml') (Join-Path $RepoRoot '.codex\config.toml')
    @'
# Agent instructions — orch

This repo configures two MCP servers (`github`, `atlassian`) via
`.codex/config.toml`. It ships four skills in `skills/`:

- `verify-story-against-code`
- `pr-review-against-story`
- `draft-confluence-from-code`
- `story-to-test-plan`

When a user request matches one of these, read `skills/<name>/SKILL.md` and
follow its steps. Always cite GitHub and Atlassian URLs for the claims you
make.
'@ | Set-Content -Path (Join-Path $RepoRoot 'AGENTS.md') -Encoding UTF8
    Ok "wrote AGENTS.md"
}

# Antigravity
$antigravityAppData = Join-Path $env:APPDATA 'Antigravity'
$antigravityLocal = Join-Path $env:LOCALAPPDATA 'Antigravity'
if ((Want-Tool 'antigravity') -and ((Get-Command antigravity -ErrorAction SilentlyContinue) -or (Test-Path $antigravityAppData) -or (Test-Path $antigravityLocal))) {
    Ok "Antigravity detected"
    Render-Template (Join-Path $RepoRoot 'mcp\antigravity.json') (Join-Path $RepoRoot '.antigravity\mcp_config.json')
    $agDir = Join-Path $RepoRoot '.antigravity'
    New-Item -ItemType Directory -Force -Path $agDir | Out-Null
    @'
# Antigravity rules — orch

MCP servers configured in `.antigravity/mcp_config.json`: `github`, `atlassian`.
Skills live in `skills/`. When the user's request maps to one of:
verify-story-against-code, pr-review-against-story, draft-confluence-from-code,
story-to-test-plan — read `skills/<name>/SKILL.md` and follow it.
'@ | Set-Content -Path (Join-Path $agDir 'rules.md') -Encoding UTF8
    Ok "wrote .antigravity\rules.md"
}

# Windsurf
$windsurfDir = Join-Path $env:USERPROFILE '.codeium\windsurf'
if ((Want-Tool 'windsurf') -and ((Get-Command windsurf -ErrorAction SilentlyContinue) -or (Test-Path $windsurfDir))) {
    Ok "Windsurf detected"
    Render-Template (Join-Path $RepoRoot 'mcp\cursor.json') (Join-Path $RepoRoot '.codeium\windsurf\mcp_config.json')
}

Step "Done"
Say "Open this repo in your AI coding tool and ask:"
Say "    `"verify story PROJ-68 against the code`""
Say ""
Say "If your tool wasn't detected, force it:"
Say "    .\install.ps1 -Tool cursor"
