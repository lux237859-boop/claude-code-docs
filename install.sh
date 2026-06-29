#!/bin/bash
set -euo pipefail

# Claude Code Docs Installer v0.3.3 - Changelog integration and compatibility improvements
# This script installs/migrates claude-code-docs to ~/.claude-code-docs

echo "Claude Code Docs Installer v0.3.3"
echo "==============================="

# Fixed installation location
INSTALL_DIR="$HOME/.claude-code-docs"

# Branch to use for installation
INSTALL_BRANCH="main"

# GitHub repository (change this to your fork if needed)
GITHUB_REPO="lux237859-boop/claude-code-docs"
UPSTREAM_REPO="ericbuess/claude-code-docs"  # Original upstream for attribution

# Detect OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    echo "✓ Detected macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
    echo "✓ Detected Linux"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    OS_TYPE="windows"
    echo "✓ Detected Windows (Git Bash/MSYS)"
else
    echo "❌ Error: Unsupported OS type: $OSTYPE"
    echo "This installer supports macOS, Linux, and Windows (Git Bash)"
    echo "For Windows PowerShell, use: irm https://raw.githubusercontent.com/$GITHUB_REPO/main/install.ps1 | iex"
    exit 1
fi

# Check dependencies
echo "Checking dependencies..."

# jq fallback: use python if jq is not available (common on Windows)
if ! command -v jq &> /dev/null; then
    if command -v python3 &> /dev/null; then
        PY_CMD="python3"
    elif command -v python &> /dev/null; then
        PY_CMD="python"
    else
        echo "❌ Error: jq or python is required but neither is installed"
        echo "Please install jq (https://jqlang.github.io/jq/) or python and try again"
        exit 1
    fi
    echo "  ℹ️  jq not found, using Python for JSON operations"

    # Create a small Python helper for settings.json manipulation
    JSON_HELPER=$(mktemp)
    trap 'rm -f "$JSON_HELPER"' EXIT
    cat > "$JSON_HELPER" << 'PYEOF'
#!/usr/bin/env python3
"""Minimal jq replacement for claude-code-docs installer."""
import json, sys

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    if action == "list-hook-commands":
        # Equivalent: jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' FILE
        filepath = sys.argv[2]
        try:
            with open(filepath) as f:
                data = json.load(f)
            hooks = data.get("hooks", {}).get("PreToolUse", [])
            for hook_group in hooks:
                for h in hook_group.get("hooks", []):
                    cmd = h.get("command", "")
                    if cmd:
                        print(cmd)
        except Exception:
            pass

    elif action == "remove-and-add-hook":
        # Equivalent to:
        #   jq 'select(contains("claude-code-docs") | not)' | jq 'add new hook'
        # Removes all hooks with "claude-code-docs" in command, then adds new hook
        filepath = sys.argv[2]
        new_cmd = sys.argv[3]
        try:
            with open(filepath) as f:
                data = json.load(f)
        except Exception:
            data = {}

        # Ensure structure
        if "hooks" not in data:
            data["hooks"] = {}
        if "PreToolUse" not in data["hooks"]:
            data["hooks"]["PreToolUse"] = []

        # Remove hooks containing "claude-code-docs"
        data["hooks"]["PreToolUse"] = [
            group for group in data["hooks"]["PreToolUse"]
            if not any(
                "claude-code-docs" in h.get("command", "")
                for h in group.get("hooks", [])
            )
        ]

        # Add new hook
        new_hook = {
            "matcher": "Read",
            "hooks": [
                {
                    "type": "command",
                    "command": new_cmd
                }
            ]
        }
        data["hooks"]["PreToolUse"].append(new_hook)

        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)

    elif action == "create-settings":
        # Equivalent to: jq -n --arg cmd CMD '{...}'
        filepath = sys.argv[2]
        new_cmd = sys.argv[3]
        data = {
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Read",
                        "hooks": [
                            {
                                "type": "command",
                                "command": new_cmd
                            }
                        ]
                    }
                ]
            }
        }
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)

    elif action == "cleanup-hooks":
        # For uninstall: remove hooks and clean empty structures
        filepath = sys.argv[2]
        try:
            with open(filepath) as f:
                data = json.load(f)
        except Exception:
            data = {}

        if "hooks" in data and "PreToolUse" in data["hooks"]:
            data["hooks"]["PreToolUse"] = [
                group for group in data["hooks"]["PreToolUse"]
                if not any(
                    "claude-code-docs" in h.get("command", "")
                    for h in group.get("hooks", [])
                )
            ]
            if not data["hooks"]["PreToolUse"]:
                del data["hooks"]["PreToolUse"]
            if not data["hooks"]:
                del data["hooks"]

        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)

if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$JSON_HELPER"
else
    PY_CMD=""
    JSON_HELPER=""
fi

# Wrapper functions for settings.json operations
settings_list_hooks() {
    if [[ -n "$PY_CMD" ]]; then
        "$PY_CMD" "$JSON_HELPER" list-hook-commands "$1"
    else
        jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' "$1" 2>/dev/null
    fi
}

settings_remove_and_add_hook() {
    if [[ -n "$PY_CMD" ]]; then
        "$PY_CMD" "$JSON_HELPER" remove-and-add-hook "$1" "$2"
    else
        jq '.hooks.PreToolUse = [(.hooks.PreToolUse // [])[] | select(.hooks[0].command | contains("claude-code-docs") | not)]' "$1" > "${1}.tmp"
        jq --arg cmd "$2" '.hooks.PreToolUse = [(.hooks.PreToolUse // [])[]] + [{"matcher": "Read", "hooks": [{"type": "command", "command": $cmd}]}]' "${1}.tmp" > "$1"
        rm -f "${1}.tmp"
    fi
}

settings_create_new() {
    if [[ -n "$PY_CMD" ]]; then
        "$PY_CMD" "$JSON_HELPER" create-settings "$1" "$2"
    else
        jq -n --arg cmd "$2" '{
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Read",
                        "hooks": [
                            {
                                "type": "command",
                                "command": $cmd
                            }
                        ]
                    }
                ]
            }
        }' > "$1"
    fi
}

settings_cleanup_hooks() {
    if [[ -n "$PY_CMD" ]]; then
        "$PY_CMD" "$JSON_HELPER" cleanup-hooks "$1"
    else
        jq '.hooks.PreToolUse = [(.hooks.PreToolUse // [])[] | select(.hooks[0].command | contains("claude-code-docs") | not)]' "$1" > "${1}.tmp"
        jq 'if .hooks.PreToolUse == [] then .hooks |= if . == {PreToolUse: []} then {} else del(.PreToolUse) end else . end | if .hooks == {} then del(.hooks) else . end' "${1}.tmp" > "${1}.tmp2"
        mv "${1}.tmp2" "$1"
        rm -f "${1}.tmp"
    fi
}

for cmd in git curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Error: $cmd is required but not installed"
        echo "Please install $cmd and try again"
        exit 1
    fi
done

# column fallback for Windows
if ! command -v column &> /dev/null; then
    column() { cat; }
fi

echo "✓ All dependencies satisfied"


# Function to find existing installations from configs
find_existing_installations() {
    local paths=()
    
    # Check command file for paths
    if [[ -f ~/.claude/commands/docs.md ]]; then
        # Look for paths in the command file
        # v0.1 format: LOCAL DOCS AT: /path/to/claude-code-docs/docs/
        # v0.2+ format: Execute: /path/to/claude-code-docs/helper.sh
        while IFS= read -r line; do
            # v0.1 format
            if [[ "$line" =~ LOCAL\ DOCS\ AT:\ ([^[:space:]]+)/docs/ ]]; then
                local path="${BASH_REMATCH[1]}"
                path="${path/#\~/$HOME}"
                [[ -d "$path" ]] && paths+=("$path")
            fi
            # v0.2+ format
            if [[ "$line" =~ Execute:.*claude-code-docs ]]; then
                # Extract path from various formats
                local path=$(echo "$line" | grep -o '[^ "]*claude-code-docs[^ "]*' | head -1)
                path="${path/#\~/$HOME}"
                
                # Get directory part
                if [[ -d "$path" ]]; then
                    paths+=("$path")
                elif [[ -d "$(dirname "$path")" ]] && [[ "$(basename "$(dirname "$path")")" == "claude-code-docs" ]]; then
                    paths+=("$(dirname "$path")")
                fi
            fi
        done < ~/.claude/commands/docs.md
    fi
    
    # Check settings.json hooks for paths
    if [[ -f ~/.claude/settings.json ]]; then
        local hooks=$(settings_list_hooks ~/.claude/settings.json)
        while IFS= read -r cmd; do
            if [[ "$cmd" =~ claude-code-docs ]]; then
                # Extract paths from v0.1 complex hook format
                # Look for patterns like: "/path/to/claude-code-docs/.last_check"
                local v01_paths=$(echo "$cmd" | grep -o '"[^"]*claude-code-docs[^"]*"' | sed 's/"//g' || true)
                while IFS= read -r path; do
                    [[ -z "$path" ]] && continue
                    # Extract just the directory part
                    if [[ "$path" =~ (.*/claude-code-docs)(/.*)?$ ]]; then
                        path="${BASH_REMATCH[1]}"
                        path="${path/#\~/$HOME}"
                        [[ -d "$path" ]] && paths+=("$path")
                    fi
                done <<< "$v01_paths"
                
                # Also try v0.2+ simpler format
                local found=$(echo "$cmd" | grep -o '[^ "]*claude-code-docs[^ "]*' || true)
                while IFS= read -r path; do
                    [[ -z "$path" ]] && continue
                    path="${path/#\~/$HOME}"
                    # Clean up path to get the claude-code-docs directory
                    if [[ "$path" =~ (.*/claude-code-docs)(/.*)?$ ]]; then
                        path="${BASH_REMATCH[1]}"
                    fi
                    [[ -d "$path" ]] && paths+=("$path")
                done <<< "$found"
            fi
        done <<< "$hooks"
    fi
    
    # Also check current directory if running from an installation
    if [[ -f "./docs/docs_manifest.json" && "$(pwd)" != "$INSTALL_DIR" ]]; then
        paths+=("$(pwd)")
    fi
    
    # Deduplicate and exclude new location
    if [[ ${#paths[@]} -gt 0 ]]; then
        printf '%s\n' "${paths[@]}" | grep -v "^$INSTALL_DIR$" | sort -u
    fi
}

# Function to migrate from old location
migrate_installation() {
    local old_dir="$1"
    
    echo "📦 Found existing installation at: $old_dir"
    echo "   Migrating to: $INSTALL_DIR"
    echo ""
    
    # Check if old dir has uncommitted changes
    local should_preserve=false
    if [[ -d "$old_dir/.git" ]]; then
        cd "$old_dir"
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            should_preserve=true
            echo "⚠️  Uncommitted changes detected in old installation"
        fi
        cd - >/dev/null
    fi
    
    # Fresh install at new location
    echo "Installing fresh at ~/.claude-code-docs..."
    git clone -b "$INSTALL_BRANCH" https://github.com/$GITHUB_REPO.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Remove old directory if safe
    if [[ "$should_preserve" == "false" ]]; then
        echo "Removing old installation..."
        rm -rf "$old_dir"
        echo "✓ Old installation removed"
    else
        echo ""
        echo "ℹ️  Old installation preserved at: $old_dir"
        echo "   (has uncommitted changes)"
    fi
    
    echo ""
    echo "✅ Migration complete!"
}

# Function to safely update git repository
safe_git_update() {
    local repo_dir="$1"
    cd "$repo_dir"
    
    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    # Determine which branch to use - always use installer's target branch
    local target_branch="$INSTALL_BRANCH"
    
    # Note: Simplified branch switching - no longer need v0.3.1 upgrade detection
    
    # If we're on a different branch or have conflicts, we need to switch
    if [[ "$current_branch" != "$target_branch" ]]; then
        echo "  Switching from $current_branch to $target_branch branch..."
    else
        echo "  Updating $target_branch branch..."
    fi
    
    # Set git config for pull strategy if not set
    if ! git config pull.rebase >/dev/null 2>&1; then
        git config pull.rebase false
    fi
    
    echo "Updating to latest version..."
    
    # Note: Old v0.3.1 upgrade logic removed - new branch switching logic handles all cases
    
    # Try regular pull first (use target branch)
    if git pull --quiet origin "$target_branch" 2>/dev/null; then
        return 0
    fi
    
    # If pull failed, try more aggressive approach
    echo "  Standard update failed, trying harder..."
    
    # Fetch latest
    if ! git fetch origin "$target_branch" 2>/dev/null; then
        echo "  ⚠️  Could not fetch from GitHub (offline?)"
        return 1
    fi
    
    # If we're switching branches, skip the change detection - just force clean
    if [[ "$current_branch" != "$target_branch" ]]; then
        echo "  Branch switch detected, forcing clean state..."
        local needs_user_confirmation=false
    else
        # Check what kind of changes we have (only when staying on same branch)
        local has_conflicts=false
        local has_local_changes=false
        local has_untracked=false
        local needs_user_confirmation=false
        
        # Check for merge conflicts (but ignore conflicts on docs_manifest.json - that's expected)
        local non_manifest_conflicts=$(git status --porcelain | grep "^UU\|^AA\|^DD" | grep -v "docs/docs_manifest.json" 2>/dev/null)
        if [[ -n "$non_manifest_conflicts" ]]; then
            has_conflicts=true
            needs_user_confirmation=true
        fi
        
        # Check for uncommitted changes (but ignore docs_manifest.json - that's expected)
        local non_manifest_changes=$(git status --porcelain | grep -v "docs/docs_manifest.json" 2>/dev/null)
        if [[ -n "$non_manifest_changes" ]]; then
            has_local_changes=true
            needs_user_confirmation=true
        fi
        
        # Check for untracked files (but ignore common temp files)
        if git status --porcelain | grep "^??" | grep -v -E "\.(tmp|log|swp)$" | grep -q . 2>/dev/null; then
            has_untracked=true
            needs_user_confirmation=true
        fi
    fi
    
    # If we have significant changes, ask user for confirmation
    if [[ "$needs_user_confirmation" == "true" ]]; then
        echo ""
        echo "⚠️  WARNING: Local changes detected in your installation:"
        if [[ "$has_conflicts" == "true" ]]; then
            echo "  • Merge conflicts need resolution"
        fi
        if [[ "$has_local_changes" == "true" ]]; then
            echo "  • Modified files (other than docs_manifest.json)"
        fi
        if [[ "$has_untracked" == "true" ]]; then
            echo "  • Untracked files"
        fi
        echo ""
        echo "The installer will reset to a clean state, discarding these changes."
        echo "Note: Changes to docs_manifest.json are handled automatically."
        echo ""
        read -p "Continue and discard local changes? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled. Your local changes are preserved."
            echo "To proceed later, either:"
            echo "  1. Manually resolve the issues, or"
            echo "  2. Run the installer again and choose 'y' to discard changes"
            return 1
        fi
        echo "  Proceeding with clean installation..."
    else
        # If only manifest changes/conflicts (or no changes), proceed silently
        local manifest_only_changes=$(git status --porcelain | grep "docs/docs_manifest.json" 2>/dev/null)
        if [[ -n "$manifest_only_changes" ]]; then
            local conflict_type=$(echo "$manifest_only_changes" | grep "^UU")
            if [[ -n "$conflict_type" ]]; then
                echo "  Resolving manifest file conflicts automatically..."
            else
                echo "  Handling manifest file updates automatically..."
            fi
        fi
    fi
    
    # Force clean state - handle any conflicts, merges, or messy states
    if [[ "$needs_user_confirmation" == "true" ]]; then
        echo "  Forcing clean update (discarding local changes)..."
    else
        echo "  Updating to clean state..."
    fi
    
    # Abort any in-progress merge/rebase
    git merge --abort >/dev/null 2>&1 || true
    git rebase --abort >/dev/null 2>&1 || true
    
    # Clear any stale index
    git reset >/dev/null 2>&1 || true
    
    # Force checkout target branch (handles detached HEAD, wrong branch, etc.)
    git checkout -B "$target_branch" "origin/$target_branch" >/dev/null 2>&1
    
    # Reset to clean state (discards all local changes - user confirmed if needed)
    git reset --hard "origin/$target_branch" >/dev/null 2>&1
    
    # Clean any untracked files that might interfere
    git clean -fd >/dev/null 2>&1 || true
    
    echo "  ✓ Updated successfully to clean state"
    
    return 0
}

# Function to cleanup old installations
cleanup_old_installations() {
    # Use the global OLD_INSTALLATIONS array that was populated before config updates
    if [[ ${#OLD_INSTALLATIONS[@]} -eq 0 ]]; then
        return
    fi
    
    echo ""
    echo "Cleaning up old installations..."
    echo "Found ${#OLD_INSTALLATIONS[@]} old installation(s) to remove:"
    
    for old_dir in "${OLD_INSTALLATIONS[@]}"; do
        # Skip empty paths
        if [[ -z "$old_dir" ]]; then
            continue
        fi
        
        echo "  - $old_dir"
        
        # Check if it has uncommitted changes
        if [[ -d "$old_dir/.git" ]]; then
            cd "$old_dir"
            if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
                cd - >/dev/null
                rm -rf "$old_dir"
                echo "    ✓ Removed (clean)"
            else
                cd - >/dev/null
                echo "    ⚠️  Preserved (has uncommitted changes)"
            fi
        else
            echo "    ⚠️  Preserved (not a git repo)"
        fi
    done
}

# Main installation logic
echo ""

# Always find old installations first (before any config changes)
echo "Checking for existing installations..."
existing_installs=()
while IFS= read -r line; do
    [[ -n "$line" ]] && existing_installs+=("$line")
done < <(find_existing_installations)
if [[ ${#existing_installs[@]} -gt 0 ]]; then
    OLD_INSTALLATIONS=("${existing_installs[@]}")  # Save for later cleanup
else
    OLD_INSTALLATIONS=()  # Initialize empty array
fi

if [[ ${#existing_installs[@]} -gt 0 ]]; then
    echo "Found ${#existing_installs[@]} existing installation(s):"
    for install in "${existing_installs[@]}"; do
        echo "  - $install"
    done
    echo ""
fi

# Check if already installed at new location
if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/docs/docs_manifest.json" ]]; then
    echo "✓ Found installation at ~/.claude-code-docs"
    echo "  Updating to latest version..."
    
    # Update it safely
    safe_git_update "$INSTALL_DIR"
    cd "$INSTALL_DIR"
else
    # Need to install at new location
    if [[ ${#existing_installs[@]} -gt 0 ]]; then
        # Migrate from old location
        old_install="${existing_installs[0]}"
        migrate_installation "$old_install"
    else
        # Fresh installation
        echo "No existing installation found"
        echo "Installing fresh to ~/.claude-code-docs..."
        
        git clone -b "$INSTALL_BRANCH" https://github.com/$GITHUB_REPO.git "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi
fi

# Now we're in $INSTALL_DIR, set up the new script-based system
echo ""
echo "Setting up Claude Code Docs v0.3.3..."

# Copy helper script from template
echo "Installing helper script..."
if [[ -f "$INSTALL_DIR/scripts/claude-docs-helper.sh.template" ]]; then
    cp "$INSTALL_DIR/scripts/claude-docs-helper.sh.template" "$INSTALL_DIR/claude-docs-helper.sh"
    chmod +x "$INSTALL_DIR/claude-docs-helper.sh"
    echo "✓ Helper script installed"
else
    echo "  ⚠️  Template file missing, attempting recovery..."
    # Try to fetch just the template file
    if curl -fsSL "https://raw.githubusercontent.com/$GITHUB_REPO/$INSTALL_BRANCH/scripts/claude-docs-helper.sh.template" -o "$INSTALL_DIR/claude-docs-helper.sh" 2>/dev/null; then
        chmod +x "$INSTALL_DIR/claude-docs-helper.sh"
        echo "  ✓ Helper script downloaded directly"
    else
        echo "  ❌ Failed to install helper script"
        echo "  Please check your installation and try again"
        exit 1
    fi
fi

# Always update command (in case it points to old location)
echo "Setting up /docs command..."
mkdir -p ~/.claude/commands

# Remove old command if it exists
if [[ -f ~/.claude/commands/docs.md ]]; then
    echo "  Updating existing command..."
fi

# Create simplified docs command
cat > ~/.claude/commands/docs.md << 'EOF'
Execute the Claude Code Docs helper script at ~/.claude-code-docs/claude-docs-helper.sh

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

Execute: ~/.claude-code-docs/claude-docs-helper.sh "$ARGUMENTS"
EOF

echo "✓ Created /docs command"

# Always update hook (remove old ones pointing to wrong location)
echo "Setting up automatic updates..."

# Simple hook that just calls the helper script
HOOK_COMMAND="~/.claude-code-docs/claude-docs-helper.sh hook-check"

if [ -f ~/.claude/settings.json ]; then
    # Update existing settings.json
    echo "  Updating Claude settings..."

    # Remove all claude-code-docs hooks and add our new hook
    settings_remove_and_add_hook ~/.claude/settings.json "$HOOK_COMMAND"
    echo "✓ Updated Claude settings"
else
    # Create new settings.json
    echo "  Creating Claude settings..."
    settings_create_new ~/.claude/settings.json "$HOOK_COMMAND"
    echo "✓ Created Claude settings"
fi

# Note: Do NOT modify docs_manifest.json - it's tracked by git and would break updates

# Clean up old installations now that v0.3 is set up
cleanup_old_installations

# Success message
echo ""
echo "✅ Claude Code Docs v0.3.3 installed successfully!"
echo ""
echo "📚 Command: /docs (user)"
echo "📂 Location: ~/.claude-code-docs"
echo ""
echo "Usage examples:"
echo "  /docs hooks         # Read hooks documentation"
echo "  /docs -t           # Check when docs were last updated"
echo "  /docs what's new  # See recent documentation changes"
echo ""
echo "🔄 Auto-updates: Enabled - syncs automatically when GitHub has newer content"
echo ""
echo "Available topics:"
ls "$INSTALL_DIR/docs" | grep '\.md$' | sed 's/\.md$//' | sort | column -c 60
echo ""
echo "⚠️  Note: Restart Claude Code for auto-updates to take effect"