#!/bin/bash
set -euo pipefail

# Claude Code Documentation Mirror - Smart Uninstaller
# Dynamically finds and removes all installations

# GitHub repository (change this to your fork if needed)
GITHUB_REPO="lux237859-boop/claude-code-docs"

echo "Claude Code Documentation Mirror - Uninstaller"
echo "=============================================="
echo ""

# jq fallback: use python if jq is not available (common on Windows)
if ! command -v jq &> /dev/null; then
    if command -v python3 &> /dev/null; then
        PY_CMD="python3"
    elif command -v python &> /dev/null; then
        PY_CMD="python"
    else
        echo "❌ Error: jq or python is required but neither is installed"
        exit 1
    fi
    echo "  ℹ️  jq not found, using Python for JSON operations"

    JSON_HELPER=$(mktemp)
    trap 'rm -f "$JSON_HELPER"' EXIT
    cat > "$JSON_HELPER" << 'PYEOF'
#!/usr/bin/env python3
import json, sys

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    if action == "list-hook-commands":
        filepath = sys.argv[2]
        try:
            with open(filepath) as f:
                data = json.load(f)
            for group in data.get("hooks", {}).get("PreToolUse", []):
                for h in group.get("hooks", []):
                    cmd = h.get("command", "")
                    if cmd:
                        print(cmd)
        except Exception:
            pass

    elif action == "cleanup-hooks":
        filepath = sys.argv[2]
        try:
            with open(filepath) as f:
                data = json.load(f)
        except Exception:
            data = {}

        if "hooks" in data and "PreToolUse" in data["hooks"]:
            data["hooks"]["PreToolUse"] = [
                g for g in data["hooks"]["PreToolUse"]
                if not any("claude-code-docs" in h.get("command", "") for h in g.get("hooks", []))
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

settings_list_hooks() {
    if [[ -n "$PY_CMD" ]]; then
        "$PY_CMD" "$JSON_HELPER" list-hook-commands "$1"
    else
        jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' "$1" 2>/dev/null
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

# Find all installations from configs
find_all_installations() {
    local paths=()
    
    # From command file
    if [[ -f ~/.claude/commands/docs.md ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ Execute:.*claude-code-docs ]]; then
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
    
    # From hooks
    if [[ -f ~/.claude/settings.json ]]; then
        local hooks=$(settings_list_hooks ~/.claude/settings.json)
        while IFS= read -r cmd; do
            if [[ "$cmd" =~ claude-code-docs ]]; then
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
    
    # Deduplicate - handle empty array case
    if [[ ${#paths[@]} -gt 0 ]]; then
        printf '%s\n' "${paths[@]}" | sort -u
    fi
}

# Main uninstall logic
installations=()
while IFS= read -r line; do
    installations+=("$line")
done < <(find_all_installations)

if [[ ${#installations[@]} -gt 0 ]]; then
    echo "Found installations at:"
    for path in "${installations[@]}"; do
        echo "  📁 $path"
    done
    echo ""
fi

echo "This will remove:"
echo "  • The /docs command from ~/.claude/commands/docs.md"
echo "  • All claude-code-docs hooks from ~/.claude/settings.json"
if [[ ${#installations[@]} -gt 0 ]]; then
    echo "  • Installation directories (if safe to remove)"
fi
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Remove command file
if [[ -f ~/.claude/commands/docs.md ]]; then
    rm -f ~/.claude/commands/docs.md
    echo "✓ Removed /docs command"
fi

# Remove hooks
if [[ -f ~/.claude/settings.json ]]; then
    cp ~/.claude/settings.json ~/.claude/settings.json.backup

    # Remove all claude-code-docs hooks and clean up empty structures
    settings_cleanup_hooks ~/.claude/settings.json
    echo "✓ Removed hooks (backup: ~/.claude/settings.json.backup)"
fi

# Remove directories
if [[ ${#installations[@]} -gt 0 ]]; then
    echo ""
    for path in "${installations[@]}"; do
        if [[ ! -d "$path" ]]; then
            continue
        fi
        
        if [[ -d "$path/.git" ]]; then
            # Save current directory
            local current_dir=$(pwd)
            cd "$path"
            
            if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
                cd "$current_dir"
                rm -rf "$path"
                echo "✓ Removed $path (clean git repo)"
            else
                cd "$current_dir"
                echo "⚠️  Preserved $path (has uncommitted changes)"
            fi
        else
            echo "⚠️  Preserved $path (not a git repo)"
        fi
    done
fi

echo ""
echo "✅ Uninstall complete!"
echo ""
echo "To reinstall:"
echo "curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash"