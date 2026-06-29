# Claude Code Documentation Mirror - PowerShell Uninstaller
# Dynamically finds and removes all installations

$ErrorActionPreference = "Stop"

# GitHub repository (change this to your fork if needed)
$GITHUB_REPO = "lux237859-boop/claude-code-docs"

Write-Output "Claude Code Documentation Mirror - Uninstaller (PowerShell)"
Write-Output "==========================================================="
Write-Output ""

# Function to find all installations from configs
function Find-AllInstallations {
    $paths = @()

    # From command file
    $cmdFile = Join-Path $env:USERPROFILE ".claude\commands\docs.md"
    if (Test-Path $cmdFile) {
        $content = Get-Content $cmdFile -Raw
        if ($content -match 'Execute:.*claude-code-docs') {
            $match = [regex]::Match($content, '([^\s"]*claude-code-docs[^\s"]*)')
            if ($match.Success) {
                $path = $match.Groups[1].Value -replace '~', $env:USERPROFILE
                $dir = Split-Path $path -Parent
                if ($dir -and (Test-Path $dir)) {
                    $paths += $dir
                }
                if (Test-Path $path) {
                    $paths += $path
                }
            }
        }
    }

    # From hooks in settings.json
    $settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
            if ($settings.hooks -and $settings.hooks.PreToolUse) {
                foreach ($hook in $settings.hooks.PreToolUse) {
                    if ($hook.hooks) {
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
            }
        } catch {
            # Ignore JSON parse errors
        }
    }

    # Deduplicate
    return ($paths | Select-Object -Unique)
}

# Main uninstall logic
$installations = @(Find-AllInstallations)

if ($installations.Count -gt 0) {
    Write-Output "Found installations at:"
    foreach ($path in $installations) {
        Write-Output "  📁 $path"
    }
    Write-Output ""
}

Write-Output "This will remove:"
Write-Output "  • The /docs command from ~\.claude\commands\docs.md"
Write-Output "  • All claude-code-docs hooks from ~\.claude\settings.json"
if ($installations.Count -gt 0) {
    Write-Output "  • Installation directories (if safe to remove)"
}
Write-Output ""

$response = Read-Host "Continue? (y/N)"
if ($response -notmatch '^[Yy]') {
    Write-Output "Cancelled."
    exit 0
}

# Remove command file
$cmdFile = Join-Path $env:USERPROFILE ".claude\commands\docs.md"
if (Test-Path $cmdFile) {
    Remove-Item $cmdFile -Force
    Write-Output "✓ Removed /docs command"
}

# Remove hooks from settings.json
$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $settingsFile) {
    # Create backup
    $backupFile = "$settingsFile.backup"
    Copy-Item $settingsFile $backupFile -Force

    # Use Python for reliable JSON manipulation (PowerShell 5.1 ConvertTo-Json loses nested data)
    $pyCmd = $null
    if (Get-Command python3 -ErrorAction SilentlyContinue) { $pyCmd = "python3" }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $pyCmd = "python" }
    else {
        Write-Output "❌ Error: python is required for settings.json manipulation"
        exit 1
    }

    # Write a temporary Python helper script
    $jsonHelper = Join-Path $env:TEMP "claude-docs-uninstall-helper.py"
    @'
import json, sys

def main():
    settings_file = sys.argv[1]

    try:
        with open(settings_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return

    # Remove hooks containing claude-code-docs
    if "hooks" in data and "PreToolUse" in data["hooks"]:
        data["hooks"]["PreToolUse"] = [
            group for group in data["hooks"]["PreToolUse"]
            if not any(
                "claude-code-docs" in h.get("command", "")
                for h in group.get("hooks", [])
            )
        ]

        # Remove empty PreToolUse
        if not data["hooks"]["PreToolUse"]:
            del data["hooks"]["PreToolUse"]

        # Remove empty hooks object
        if not data["hooks"]:
            del data["hooks"]

    # Write back preserving ALL existing keys
    with open(settings_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')

if __name__ == "__main__":
    main()
'@ | Set-Content -Path $jsonHelper -Encoding UTF8

    & $pyCmd $jsonHelper $settingsFile
    if ($LASTEXITCODE -eq 0) {
        Write-Output "✓ Removed hooks (backup: $backupFile)"
    } else {
        Write-Output "❌ Failed to remove hooks"
    }

    # Clean up temp helper
    Remove-Item $jsonHelper -Force -ErrorAction SilentlyContinue
}

# Remove directories
if ($installations.Count -gt 0) {
    Write-Output ""
    foreach ($path in $installations) {
        if (-not (Test-Path $path)) { continue }

        $gitDir = Join-Path $path ".git"
        if (Test-Path $gitDir) {
            Push-Location $path
            try {
                $status = & git status --porcelain 2>$null
                Pop-Location
                if (-not $status) {
                    Remove-Item -Recurse -Force $path
                    Write-Output "✓ Removed $path (clean git repo)"
                } else {
                    Write-Output "⚠️  Preserved $path (has uncommitted changes)"
                }
            } catch {
                Pop-Location
                Write-Output "⚠️  Preserved $path (error during removal)"
            }
        } else {
            Write-Output "⚠️  Preserved $path (not a git repo)"
        }
    }
}

Write-Output ""
Write-Output "✅ Uninstall complete!"
Write-Output ""
Write-Output "To reinstall:"
Write-Output "Invoke-WebRequest -Uri `"https://raw.githubusercontent.com/$GITHUB_REPO/main/install.ps1`" -UseBasicParsing | Invoke-Expression"
