#!/usr/bin/env bash
# Install the QQ /model interactive picker patch into a Hermes Agent checkout.
#
# Usage:
#   ./install.sh                 # apply patch + self-check
#   ./install.sh --restart       # apply patch + self-check + restart the gateway
#   ./install.sh --check         # only report whether the patch is applied
#   HERMES_DIR=/path ./install.sh
#
# Environment:
#   HERMES_DIR   Hermes checkout (default: ~/.hermes/hermes-agent)
#   PATCH        Patch file (default: <repo>/patches/qqbot-model-picker.patch)

set -euo pipefail

HERMES_DIR="${HERMES_DIR:-$HOME/.hermes/hermes-agent}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="${PATCH:-$HERE/patches/qqbot-model-picker.patch}"
RESTART=0
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=1 ;;
    --check)   CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'x %s\n' "$*" >&2; exit 1; }

[ -d "$HERMES_DIR" ] || fail "Hermes checkout not found: $HERMES_DIR (set HERMES_DIR=...)"
[ -f "$PATCH" ]      || fail "patch not found: $PATCH"
git -C "$HERMES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "not a git checkout: $HERMES_DIR (this patch needs git apply)"

ADAPTER="$HERMES_DIR/plugins/platforms/qqbot/adapter.py"
KEYBOARDS="$HERMES_DIR/plugins/platforms/qqbot/keyboards.py"
[ -f "$ADAPTER" ] || fail "QQ Bot plugin not found: $ADAPTER"

cd "$HERMES_DIR"

if git apply --check --reverse "$PATCH" >/dev/null 2>&1; then
  say "= patch already applied"
  ALREADY=1
else
  ALREADY=0
fi

if [ "$CHECK_ONLY" = "1" ]; then
  [ "$ALREADY" = "1" ] && { say "status: applied"; exit 0; }
  say "status: not applied"
  exit 1
fi

if [ "$ALREADY" = "0" ]; then
  say "> checking patch against $HERMES_DIR"
  git apply --check "$PATCH" || fail "patch does not apply cleanly (upstream changed?). Try: git apply --3way $PATCH"
  say "> applying patch"
  git apply "$PATCH"
  say "+ patched plugins/platforms/qqbot/{adapter.py,keyboards.py}"
else
  say "> skipping apply (already patched)"
fi

# Self-check: the adapter must expose the gateway contract, and the keyboard
# builder must produce a valid payload. Uses the checkout's own interpreter.
PY=""
for cand in "$HERMES_DIR/venv/bin/python" "$HERMES_DIR/venv/Scripts/python.exe" \
            "$HERMES_DIR/.venv/bin/python" "$(command -v python3 || true)" "$(command -v python || true)"; do
  [ -n "$cand" ] && [ -x "$cand" ] && { PY="$cand"; break; }
done
[ -n "$PY" ] || fail "no python interpreter found to run the self-check"

say "> self-check ($PY)"
"$PY" - "$HERMES_DIR" <<'PYEOF'
import ast
import sys

root = sys.argv[1]
adapter_path = root + "/plugins/platforms/qqbot/adapter.py"
keyboards_path = root + "/plugins/platforms/qqbot/keyboards.py"

# 1) Static: both files parse, and the new symbols are present.
adapter_src = open(adapter_path, encoding="utf-8").read()
keyboards_src = open(keyboards_path, encoding="utf-8").read()
ast.parse(adapter_src)
ast.parse(keyboards_src)
for needle in ("async def send_model_picker", "def _handle_model_pick_interaction",
               "parse_model_pick_button_data", "build_model_picker_keyboard"):
    if needle not in adapter_src and needle not in keyboards_src:
        sys.exit("  x static check failed: %r missing" % needle)

# 2) Dynamic: load keyboards.py by path (its package __init__ pulls the whole
#    adapter stack, which needs the venv's deps). keyboards.py itself is stdlib-only,
#    so this verifies the real keyboard payload even on a bare interpreter.
import importlib.util

spec = importlib.util.spec_from_file_location("qq_model_picker_keyboards", keyboards_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod          # dataclasses resolve cls.__module__ via sys.modules
spec.loader.exec_module(mod)
build_model_picker_keyboard = mod.build_model_picker_keyboard
parse_model_pick_button_data = mod.parse_model_pick_button_data

sk = "agent:main:qqbot:c2c:SELFTEST"
items = [("custom", "deepseek-v4.1-flash-1017", "deepseek-v4.1-flash-1017"),
         ("openrouter", "anthropic/claude-fable-5.1", "claude-fable-5.1")]
rows = build_model_picker_keyboard(items, sk, current=("custom", "deepseek-v4.1-flash-1017")).to_dict()["content"]["rows"]
assert rows, "empty keyboard"
assert len(rows) <= 5, "keyboard must fit QQ's 5-row limit"
parsed = parse_model_pick_button_data(rows[0]["buttons"][0]["action"]["data"])
assert parsed and parsed[0] == "m", "button_data round-trip failed: %r" % (parsed,)

# 3) Optional: the full adapter needs the venv's dependencies (ruamel, etc.).
try:
    from plugins.platforms.qqbot.adapter import QQAdapter
    if not hasattr(QQAdapter, "send_model_picker"):
        sys.exit("  x QQAdapter.send_model_picker missing")
    adapter_note = "adapter import ok"
except Exception as exc:  # noqa: BLE001 - missing deps is not a patch failure
    adapter_note = "adapter import skipped (%s)" % type(exc).__name__

print("  ok: keyboard rows=%d, button_data round-trip ok, %s" % (len(rows), adapter_note))
PYEOF

say ""
say "done. next: restart the gateway so the new adapter code loads:"
say "  hermes gateway restart"
say "  # or: systemctl --user restart hermes-gateway.service"
say "then send /model in QQ."

if [ "$RESTART" = "1" ]; then
  say ""
  say "> restarting hermes-gateway.service"
  if systemctl --user restart hermes-gateway.service 2>/dev/null; then
    sleep 3
    systemctl --user is-active hermes-gateway.service || fail "gateway did not come back up"
    say "+ gateway restarted"
  else
    say "! systemctl --user not available here; run: hermes gateway restart"
  fi
fi
