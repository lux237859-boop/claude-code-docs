# Claude Code Docs Installer v0.3.3 - PowerShell Edition
# This script installs/migrates claude-code-docs to ~\.claude-code-docs

$ErrorActionPreference = "Stop"

Write-Output "Claude Code Docs Installer v0.3.3 (PowerShell)"
Write-Output "==============================================="

# Fixed installation location
$INSTALL_DIR = Join-Path $env:USERPROFILE ".claude-code-docs"

# Branch to use for installation
$INSTALL_BRANCH = "main"

# GitHub repository (change this to your fork if needed)
$GITHUB_REPO = "lux237859-boop/claude-code-docs"
$UPSTREAM_REPO = "ericbuess/claude-code-docs"  # Original upstream for attribution

# Check if running on Windows
if ($env:OS -ne "Windows_NT") {
    Write-Output "❌ Error: This installer is for Windows only"
    Write-Output "For macOS/Linux, use: curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash"
    exit 1
}

Write-Output "✓ Detected Windows"

# Check dependencies
Write-Output "Checking dependencies..."
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitPath) {
    Write-Output "❌ Error: git is required but not installed"
    Write-Output "Please install Git for Windows: https://git-scm.com/download/win"
    exit 1
}
Write-Output "✓ All dependencies satisfied"

# Function to find existing installations from configs
function Find-ExistingInstallations {
    $paths = @()

    # Check command file for paths
    $cmdFile = Join-Path $env:USERPROFILE ".claude\commands\docs.md"
    if (Test-Path $cmdFile) {
        $content = Get-Content $cmdFile -Raw
        # Look for paths in Execute line
        if ($content -match 'Execute:.*claude-code-docs') {
            $match = [regex]::Match($content, '([^\s"]*claude-code-docs[^\s"]*)')
            if ($match.Success) {
                $path = $match.Groups[1].Value -replace '~', $env:USERPROFILE
                $dir = Split-Path $path -Parent
                if (Test-Path $dir) {
                    $paths += $dir
                }
                if (Test-Path $path) {
                    $paths += $path
                }
            }
        }
    }

    # Check settings.json hooks for paths
    $settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
            if ($settings.hooks -and $settings.hooks.PreToolUse) {
                foreach ($hook in $settings.hooks.PreToolUse) {
                    foreach ($h in $hook.hooks) {
                        if ($h.command -match 'claude-code-docs') {
                            $match = [regex]::Match($h.command, '([^\s"]*claude-code-docs[^\s"]*)')
                            if ($match.Success) {
                                $path = $match.Groups[1].Value -replace '~', $env:USERPROFILE
                                if ($path -match '(.*claude-code-docs)') {
                                    $dir = $matches[1]
                                    if (Test-Path $dir) {
                                        $paths += $dir
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            # Ignore JSON parse errors
        }
    }

    # Deduplicate and exclude new location
    $unique = $paths | Select-Object -Unique | Where-Object { $_ -ne $INSTALL_DIR }
    return $unique
}

# Function to migrate from old location
function Migrate-Installation {
    param([string]$OldDir)

    Write-Output "📦 Found existing installation at: $OldDir"
    Write-Output "   Migrating to: $INSTALL_DIR"
    Write-Output ""

    # Check if old dir has uncommitted changes
    $shouldPreserve = $false
    $gitDir = Join-Path $OldDir ".git"
    if (Test-Path $gitDir) {
        Push-Location $OldDir
        try {
            $status = & git status --porcelain 2>$null
            if ($status) {
                $shouldPreserve = $true
                Write-Output "⚠️  Uncommitted changes detected in old installation"
            }
        } finally {
            Pop-Location
        }
    }

    # Fresh install at new location
    Write-Output "Installing fresh at ~\.claude-code-docs..."
    & git clone -b $INSTALL_BRANCH https://github.com/$GITHUB_REPO.git $INSTALL_DIR
    Push-Location $INSTALL_DIR
    Pop-Location

    # Remove old directory if safe
    if (-not $shouldPreserve) {
        Write-Output "Removing old installation..."
        Remove-Item -Recurse -Force $OldDir
        Write-Output "✓ Old installation removed"
    } else {
        Write-Output ""
        Write-Output "ℹ️  Old installation preserved at: $OldDir"
        Write-Output "   (has uncommitted changes)"
    }

    Write-Output ""
    Write-Output "✅ Migration complete!"
}

# Function to safely update git repository
function Safe-GitUpdate {
    param([string]$RepoDir)

    Push-Location $RepoDir
    try {
        $currentBranch = & git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $currentBranch) { $currentBranch = "unknown" }

        $targetBranch = $INSTALL_BRANCH

        if ($currentBranch -ne $targetBranch) {
            Write-Output "  Switching from $currentBranch to $targetBranch branch..."
        } else {
            Write-Output "  Updating $targetBranch branch..."
        }

        # Set git config for pull strategy if not set
        & git config pull.rebase 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & git config pull.rebase false 2>$null
        }

        Write-Output "Updating to latest version..."

        # Try regular pull first
        & git pull --quiet origin $targetBranch 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        # If pull failed, try harder
        Write-Output "  Standard update failed, trying harder..."

        & git fetch origin $targetBranch 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Output "  ⚠️  Could not fetch from GitHub (offline?)"
            return $false
        }

        $needsUserConfirmation = $false

        if ($currentBranch -ne $targetBranch) {
            Write-Output "  Branch switch detected, forcing clean state..."
        } else {
            # Check for conflicts (ignore docs_manifest.json)
            $status = & git status --porcelain 2>$null
            $nonManifestConflicts = $status | Where-Object { $_ -match '^(UU|AA|DD)' -and $_ -notmatch 'docs_manifest.json' }
            $nonManifestChanges = $status | Where-Object { $_ -notmatch 'docs_manifest.json' }

            if ($nonManifestConflicts -or $nonManifestChanges) {
                $needsUserConfirmation = $true
            }
        }

        if ($needsUserConfirmation) {
            Write-Output ""
            Write-Output "⚠️  WARNING: Local changes detected in your installation."
            Write-Output ""
            $response = Read-Host "Continue and discard local changes? [y/N]"
            if ($response -notmatch '^[Yy]') {
                Write-Output "Installation cancelled. Your local changes are preserved."
                return $false
            }
            Write-Output "  Proceeding with clean installation..."
        }

        # Force clean state
        & git merge --abort 2>$null
        & git rebase --abort 2>$null
        & git reset 2>$null
        & git checkout -B $targetBranch "origin/$targetBranch" 2>$null
        & git reset --hard "origin/$targetBranch" 2>$null
        & git clean -fd 2>$null

        Write-Output "  ✓ Updated successfully to clean state"
        return $true
    } finally {
        Pop-Location
    }
}

# Function to cleanup old installations
function Cleanup-OldInstallations {
    param([string[]]$OldInstallations)

    if ($OldInstallations.Count -eq 0) { return }

    Write-Output ""
    Write-Output "Cleaning up old installations..."
    Write-Output "Found $($OldInstallations.Count) old installation(s) to remove:"

    foreach ($oldDir in $OldInstallations) {
        if (-not $oldDir) { continue }
        Write-Output "  - $oldDir"

        $gitDir = Join-Path $oldDir ".git"
        if (Test-Path $gitDir) {
            Push-Location $oldDir
            try {
                $status = & git status --porcelain 2>$null
                if (-not $status) {
                    Pop-Location
                    Remove-Item -Recurse -Force $oldDir
                    Write-Output "    ✓ Removed (clean)"
                } else {
                    Pop-Location
                    Write-Output "    ⚠️  Preserved (has uncommitted changes)"
                }
            } catch {
                Pop-Location
                Write-Output "    ⚠️  Preserved (error during removal)"
            }
        } else {
            Write-Output "    ⚠️  Preserved (not a git repo)"
        }
    }
}

# Main installation logic
Write-Output ""

# Always find old installations first
Write-Output "Checking for existing installations..."
$existingInstalls = @(Find-ExistingInstallations)
$oldInstallations = $existingInstalls

if ($existingInstalls.Count -gt 0) {
    Write-Output "Found $($existingInstalls.Count) existing installation(s):"
    foreach ($install in $existingInstalls) {
        Write-Output "  - $install"
    }
    Write-Output ""
}

# Check if already installed at new location
$manifestFile = Join-Path $INSTALL_DIR "docs\docs_manifest.json"
if ((Test-Path $INSTALL_DIR) -and (Test-Path $manifestFile)) {
    Write-Output "✓ Found installation at ~\.claude-code-docs"
    Write-Output "  Updating to latest version..."

    Safe-GitUpdate -RepoDir $INSTALL_DIR | Out-Null
    Push-Location $INSTALL_DIR
    Pop-Location
} else {
    # Need to install at new location
    if ($existingInstalls.Count -gt 0) {
        # Migrate from old location
        $oldInstall = $existingInstalls[0]
        Migrate-Installation -OldDir $oldInstall
    } else {
        # Fresh installation
        Write-Output "No existing installation found"
        Write-Output "Installing fresh to ~\.claude-code-docs..."

        & git clone -b $INSTALL_BRANCH https://github.com/$GITHUB_REPO.git $INSTALL_DIR
        Push-Location $INSTALL_DIR
        Pop-Location
    }
}

# Now set up the script-based system
Write-Output ""
Write-Output "Setting up Claude Code Docs v0.3.3..."

# Copy helper script from template
Write-Output "Installing helper script..."
$templatePath = Join-Path $INSTALL_DIR "scripts\claude-docs-helper.ps1.template"
$helperPath = Join-Path $INSTALL_DIR "claude-docs-helper.ps1"

if (Test-Path $templatePath) {
    Copy-Item $templatePath $helperPath -Force
    Write-Output "✓ Helper script installed"
} else {
    Write-Output "  ⚠️  Template file missing, attempting recovery..."
    try {
        $templateUrl = "https://raw.githubusercontent.com/$GITHUB_REPO/$INSTALL_BRANCH/scripts/claude-docs-helper.ps1.template"
        Invoke-WebRequest -Uri $templateUrl -OutFile $helperPath -UseBasicParsing
        Write-Output "  ✓ Helper script downloaded directly"
    } catch {
        Write-Output "  ❌ Failed to install helper script"
        Write-Output "  Please check your installation and try again"
        exit 1
    }
}

# Always update command
Write-Output "Setting up /docs command..."
$cmdDir = Join-Path $env:USERPROFILE ".claude\commands"
if (-not (Test-Path $cmdDir)) {
    New-Item -ItemType Directory -Path $cmdDir -Force | Out-Null
}

$cmdFile = Join-Path $cmdDir "docs.md"
$docsCmdContent = @"
Execute the Claude Code Docs helper script at ~\.claude-code-docs\claude-docs-helper.ps1

Usage:
- /docs - List all available documentation topics
- /docs <topic> - Read specific documentation with link to official docs
- /docs -t - Check sync status without reading a doc
- /docs -t <topic> - Check freshness then read documentation
- /docs whats new - Show recent documentation changes (or "what's new")

Examples of expected output:

When reading a doc:
📚 COMMUNITY MIRROR: https://github.com/$GITHUB_REPO
📖 OFFICIAL DOCS: https://docs.anthropic.com/en/docs/claude-code

[Doc content here...]

📖 Official page: https://docs.anthropic.com/en/docs/claude-code/hooks

When showing what's new:
📚 Recent documentation updates:

• 5 hours ago:
  📎 https://github.com/$GITHUB_REPO/commit/eacd8e1
  📄 data-usage: https://docs.anthropic.com/en/docs/claude-code/data-usage
     ➕ Added: Privacy safeguards
  📄 security: https://docs.anthropic.com/en/docs/claude-code/security
     ✨ Data flow and dependencies section moved here

📎 Full changelog: https://github.com/$GITHUB_REPO/commits/main/docs
📚 COMMUNITY MIRROR - NOT AFFILIATED WITH ANTHROPIC

Every request checks for the latest documentation from GitHub (takes ~0.4s).
The helper script handles all functionality including auto-updates.

Execute: powershell -ExecutionPolicy Bypass -File ~\.claude-code-docs\claude-docs-helper.ps1 "$ARGUMENTS"
"@

Set-Content -Path $cmdFile -Value $docsCmdContent -Encoding UTF8
Write-Output "✓ Created /docs command"

# Always update hook
Write-Output "Setting up automatic updates..."

$hookCommand = "powershell -ExecutionPolicy Bypass -File ~\.claude-code-docs\claude-docs-helper.ps1 hook-check"

$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $settingsFile) {
    Write-Output "  Updating Claude settings..."

    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
    } catch {
        $settings = New-Object PSObject
    }

    # Ensure hooks structure exists
    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue (New-Object PSObject) -Force
    }
    if (-not $settings.hooks.PreToolUse) {
        $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
    }

    # Remove ALL hooks that contain "claude-code-docs"
    $filteredHooks = @($settings.hooks.PreToolUse | Where-Object {
        $keep = $true
        if ($_.hooks -and $_.hooks.Count -gt 0) {
            foreach ($h in $_.hooks) {
                if ($h.command -match 'claude-code-docs') {
                    $keep = $false
                }
            }
        }
        $keep
    })

    # Add our new hook
    $newHook = @{
        matcher = "Read"
        hooks = @(
            @{
                type = "command"
                command = $hookCommand
            }
        )
    } | ConvertTo-Json | ConvertFrom-Json

    $filteredHooks += $newHook
    $settings.hooks.PreToolUse = $filteredHooks

    # Write back
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
    Write-Output "✓ Updated Claude settings"
} else {
    Write-Output "  Creating Claude settings..."
    $settingsDir = Split-Path $settingsFile -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $newSettings = @{
        hooks = @{
            PreToolUse = @(
                @{
                    matcher = "Read"
                    hooks = @(
                        @{
                            type = "command"
                            command = $hookCommand
                        }
                    )
                }
            )
        }
    }

    $newSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
    Write-Output "✓ Created Claude settings"
}

# Clean up old installations
Cleanup-OldInstallations -OldInstallations $oldInstallations

# Success message
Write-Output ""
Write-Output "✅ Claude Code Docs v0.3.3 installed successfully!"
Write-Output ""
Write-Output "📚 Command: /docs (user)"
Write-Output "📂 Location: ~\.claude-code-docs"
Write-Output ""
Write-Output "Usage examples:"
Write-Output "  /docs hooks         # Read hooks documentation"
Write-Output "  /docs -t            # Check when docs were last updated"
Write-Output "  /docs what's new    # See recent documentation changes"
Write-Output ""
Write-Output "🔄 Auto-updates: Enabled - syncs automatically when GitHub has newer content"
Write-Output ""
Write-Output "Available topics:"
$docsDir = Join-Path $INSTALL_DIR "docs"
Get-ChildItem -Path $docsDir -Filter "*.md" | ForEach-Object { $_.BaseName } | Sort-Object | ForEach-Object { Write-Output "  $_" }
Write-Output ""
Write-Output "⚠️  Note: Restart Claude Code for auto-updates to take effect"
