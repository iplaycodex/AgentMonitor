#!/bin/bash
set -e

AGENTMONITOR_PORT="$(defaults read com.agentmonitor.app hookPort 2>/dev/null || true)"
if ! [[ "$AGENTMONITOR_PORT" =~ ^[0-9]+$ ]]; then
    AGENTMONITOR_PORT=17321
fi
AGENTMONITOR_URL="http://localhost:${AGENTMONITOR_PORT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Claude Code Hooks
# ============================================================

configure_claude_code() {
    local settings_path="$HOME/.claude/settings.json"
    local script_dir="$HOME/.agentmonitor"
    local notify_script="$script_dir/claude-notify.sh"
    local hook_cmd="${notify_script}"

    info "Configuring Claude Code hooks..."

    mkdir -p "$script_dir"

    cat > "$notify_script" << 'SCRIPTEOF'
#!/bin/bash
payload="$(cat)"
port="$(defaults read com.agentmonitor.app hookPort 2>/dev/null || true)"
if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    port=17321
fi
tty_name="$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ')"
if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
    tty_value="/dev/${tty_name}"
else
    tty_value="$(tty 2>/dev/null || true)"
fi

AGENTMONITOR_PAYLOAD="$payload" AGENTMONITOR_TTY="$tty_value" AGENTMONITOR_CWD="$PWD" python3 - <<'PYEOF' | curl --noproxy '*' -s -X POST "http://localhost:${port}/hooks/claude" -H 'Content-Type: application/json' -d @- > /dev/null 2>&1
import json
import os
import sys

try:
    data = json.loads(os.environ.get("AGENTMONITOR_PAYLOAD", "{}") or "{}")
except json.JSONDecodeError:
    data = {}

tty = (os.environ.get("AGENTMONITOR_TTY") or "").strip()
if tty and tty != "not a tty":
    data["agentmonitor_tty"] = tty

cwd = (os.environ.get("AGENTMONITOR_CWD") or "").strip()
if cwd and not data.get("cwd"):
    data["cwd"] = cwd

json.dump(data, sys.stdout, ensure_ascii=False)
PYEOF
SCRIPTEOF
    chmod +x "$notify_script"

    # Read existing settings or create new
    if [ -f "$settings_path" ]; then
        # Use python3 to safely modify JSON
        python3 - "$settings_path" "$hook_cmd" << 'PYEOF'
import json, sys

path = sys.argv[1]
hook_cmd = sys.argv[2]

with open(path, 'r') as f:
    settings = json.load(f)

if "hooks" not in settings:
    settings["hooks"] = {}

for event in [
    "Stop",
    "Notification",
    "StopFailure",
    "SessionStart",
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "UserPromptSubmit",
    "PermissionRequest",
    "PermissionDenied",
    "Elicitation",
    "SessionEnd",
    "CwdChanged",
]:
    hook_entry = {
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": hook_cmd
        }]
    }
    entries = settings["hooks"].get(event, [])
    entries = [
        entry for entry in entries
        if not any(hook.get("command") == hook_cmd for hook in entry.get("hooks", []))
    ]
    entries.append(hook_entry)
    settings["hooks"][event] = entries

with open(path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("OK")
PYEOF
    else
        warn "Claude Code settings.json not found at $settings_path"
        warn "Please run Claude Code at least once before installing hooks"
        return 1
    fi

    info "Claude Code hooks configured!"
}

# ============================================================
# Codex CLI Hooks
# ============================================================

configure_codex() {
    local codex_config_dir="$HOME/.codex"
    local codex_config="$codex_config_dir/config.toml"
    local script_dir="$HOME/.agentmonitor"
    local notify_script="$script_dir/codex-notify.sh"

    info "Configuring Codex CLI hooks..."

    mkdir -p "$codex_config_dir"
    mkdir -p "$script_dir"

    # Install the wrapper script (Codex passes data as arg, not stdin)
    cat > "$notify_script" << 'SCRIPTEOF'
#!/bin/bash
payload="$1"
port="$(defaults read com.agentmonitor.app hookPort 2>/dev/null || true)"
if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    port=17321
fi
tty_name="$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ')"
if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
    tty_value="/dev/${tty_name}"
else
    tty_value="$(tty 2>/dev/null || true)"
fi

AGENTMONITOR_PAYLOAD="$payload" AGENTMONITOR_TTY="$tty_value" AGENTMONITOR_CWD="$PWD" python3 - <<'PYEOF' | curl --noproxy '*' -s -X POST "http://localhost:${port}/hooks/codex" -H 'Content-Type: application/json' -d @- > /dev/null 2>&1
import json
import os
import sys

try:
    data = json.loads(os.environ.get("AGENTMONITOR_PAYLOAD", "{}") or "{}")
except json.JSONDecodeError:
    data = {}

tty = (os.environ.get("AGENTMONITOR_TTY") or "").strip()
if tty and tty != "not a tty":
    data["agentmonitor_tty"] = tty

cwd = (os.environ.get("AGENTMONITOR_CWD") or "").strip()
if cwd and not data.get("cwd"):
    data["cwd"] = cwd

json.dump(data, sys.stdout, ensure_ascii=False)
PYEOF
SCRIPTEOF
    chmod +x "$notify_script"

    # Build the notify line pointing to our wrapper script
    local notify_line="notify = [\"${notify_script}\"]"

    if [ -f "$codex_config" ]; then
        # Check if notify is already configured
        if grep -q "^notify\s*=" "$codex_config" 2>/dev/null; then
            warn "Codex notify hook already exists, updating..."
            sed -i.bak "s|^notify\s*=.*|${notify_line}|" "$codex_config"
            rm -f "${codex_config}.bak"
        else
            # Insert notify config before the first [section]
            local insert_line
            insert_line=$(grep -n "^\[" "$codex_config" | head -1 | cut -d: -f1)
            if [ -n "$insert_line" ]; then
                sed -i.bak "${insert_line}i\\
${notify_line}
" "$codex_config"
                rm -f "${codex_config}.bak"
            else
                echo "" >> "$codex_config"
                echo "$notify_line" >> "$codex_config"
            fi
        fi
    else
        cat > "$codex_config" << EOF
# AgentMonitor notification hook
${notify_line}
EOF
    fi

    info "Codex CLI hooks configured!"
}

# ============================================================
# Main
# ============================================================

main() {
    echo ""
    echo "╔═══════════════════════════════════╗"
    echo "║     AgentMonitor Hook Installer   ║"
    echo "╚═══════════════════════════════════╝"
    echo ""

    # Check if AgentMonitor is running
    if curl -s "${AGENTMONITOR_URL}/health" > /dev/null 2>&1; then
        info "AgentMonitor is running on port ${AGENTMONITOR_PORT}"
    else
        warn "AgentMonitor does not seem to be running on port ${AGENTMONITOR_PORT}"
        warn "Make sure to launch AgentMonitor app first"
        echo ""
    fi

    # Configure Claude Code
    if [ "$1" = "--codex-only" ]; then
        configure_codex
    elif [ "$1" = "--claude-only" ]; then
        configure_claude_code
    else
        configure_claude_code
        echo ""
        configure_codex
    fi

    echo ""
    info "All done! Hooks are configured."
    info "Restart any running Claude Code / Codex sessions for hooks to take effect."
    echo ""
}

main "$@"
