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

AGENTMONITOR_PAYLOAD="$payload" AGENTMONITOR_TTY="$tty_value" python3 - <<'PYEOF' | curl --noproxy '*' -s -X POST "http://localhost:${port}/hooks/codex" -H 'Content-Type: application/json' -d @- > /dev/null 2>&1
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

json.dump(data, sys.stdout, ensure_ascii=False)
PYEOF
