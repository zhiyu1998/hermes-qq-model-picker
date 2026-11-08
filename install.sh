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
#   PATCH        Patch file (default: picked automatically from the layout)
#
# The QQ Bot plugin lives in one of two places depending on the Hermes version,
# so both are probed and the matching patch is used:
#   plugins/platforms/qqbot/   newer builds (v0.20+)
#   gateway/platforms/qqbot/   older builds (v0.18.x and earlier)

set -euo pipefail

HERMES_DIR="${HERMES_DIR:-$HOME/.hermes/hermes-agent}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_OVERRIDE="${PATCH:-}"
RESTART=0
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=1 ;;
    --check)   CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'x %s\n' "$*" >&2; exit 1; }

[ -d "$HERMES_DIR" ] || fail "Hermes checkout not found: $HERMES_DIR (set HERMES_DIR=...)"
git -C "$HERMES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "not a git checkout: $HERMES_DIR (this patch needs git apply)"

# Locate the QQ Bot plugin instead of assuming a single upstream layout.
QQ_REL=""
for base in plugins/platforms/qqbot gateway/platforms/qqbot; do
  if [ -f "$HERMES_DIR/$base/adapter.py" ] && [ -f "$HERMES_DIR/$base/keyboards.py" ]; then
    QQ_REL="$base"
    break
  fi
done
if [ -z "$QQ_REL" ]; then
  fail "QQ Bot plugin not found in $HERMES_DIR (looked for plugins/platforms/qqbot and gateway/platforms/qqbot)"
fi

case "$QQ_REL" in
  plugins/platforms/*) DEFAULT_PATCH="$HERE/patches/qqbot-model-picker.patch" ;;
  *)                   DEFAULT_PATCH="$HERE/patches/qqbot-model-picker-legacy.patch" ;;
esac
PATCH="${PATCH_OVERRIDE:-$DEFAULT_PATCH}"
[ -f "$PATCH" ] || fail "patch not found: $PATCH"

say "= layout: $QQ_REL"
say "= patch:  ${PATCH#"$HERE"/}"

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
  # Safety copy first: a fuzzy apply that fails half-way should be reversible.
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="$HOME/.hermes/qq-model-picker-backup"
  mkdir -p "$BACKUP_DIR"
  for f in "$QQ_REL/adapter.py" "$QQ_REL/keyboards.py"; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/$(basename "$f").preinstall.$stamp"
  done
  say "= backup: $BACKUP_DIR/*.preinstall.$stamp"

  if git apply --check "$PATCH" >/dev/null 2>&1; then
    say "> applying patch"
    git apply "$PATCH"
  elif git apply --check -C1 --recount "$PATCH" >/dev/null 2>&1; then
    # Upstream may add imports or lines right next to our insertion points.
    say "! strict apply failed; applying with reduced context (-C1)"
    git apply -C1 --recount "$PATCH"
  elif command -v patch >/dev/null 2>&1 \
       && patch -p1 --dry-run --forward --batch --fuzz=3 --no-backup-if-mismatch <"$PATCH" >/dev/null 2>&1; then
    # Last resort: GNU patch tolerates up to 3 lines of drifted context.
    say "! context drifted; applying with GNU patch (fuzz 3)"
    patch -p1 --forward --batch --fuzz=3 --no-backup-if-mismatch <"$PATCH" \
      || fail "GNU patch failed; restore with: git checkout -- $QQ_REL"
  else
    say "x patch does not apply to this checkout (nothing was modified)."
    say "  layout:  $QQ_REL"
    say "  version: $(git describe --tags --always 2>/dev/null || echo unknown)"
    say "  please open an issue with the version and layout above."
    exit 1
  fi
  say "+ patched $QQ_REL/{adapter.py,keyboards.py}"
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
"$PY" - "$HERMES_DIR" "$QQ_REL" <<'PYEOF'
import ast
import importlib
import importlib.util
import sys

root, qq_rel = sys.argv[1], sys.argv[2]
adapter_path = root + "/" + qq_rel + "/adapter.py"
keyboards_path = root + "/" + qq_rel + "/keyboards.py"

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
spec = importlib.util.spec_from_file_location("qq_model_picker_keyboards", keyboards_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod          # dataclasses resolve cls.__module__ via sys.modules
spec.loader.exec_module(mod)
build_model_picker_keyboard = mod.build_model_picker_keyboard
parse_model_pick_button_data = mod.parse_model_pick_button_data

sk = "agent:main:qqbot:c2c:SELFTEST"
items = [("custom", "Custom endpoint", "deepseek-v4.1-flash-1017"),
         ("openrouter", "OpenRouter", "anthropic/claude-fable-5.1")]
rows = build_model_picker_keyboard(items, sk, current=("custom", "deepseek-v4.1-flash-1017")).to_dict()["content"]["rows"]
assert rows, "empty keyboard"
assert len(rows) <= 5, "keyboard must fit QQ's 5-row limit"
labels = [b["render_data"]["label"] for b in rows[0]["buttons"]]
assert labels and labels[0].startswith("✓1."), "first button should be the numbered current model: %r" % (labels,)
assert len(labels[0]) <= 20, "button label exceeds the 20-char budget: %r" % (labels[0],)
parsed = parse_model_pick_button_data(rows[0]["buttons"][0]["action"]["data"])
assert parsed and parsed[0] == "m", "button_data round-trip failed: %r" % (parsed,)

# 3) Optional: the full adapter needs the venv's dependencies (ruamel, etc.).
module_name = qq_rel.replace("/", ".") + ".adapter"
sys.path.insert(0, root)
try:
    adapter_spec = importlib.util.find_spec(module_name)
except Exception as exc:  # noqa: BLE001 - deps of the package __init__ may be missing
    adapter_spec = "error:" + type(exc).__name__
if adapter_spec is None:
    sys.exit("  x cannot resolve module %s under %s (layout mismatch?)" % (module_name, root))
try:
    adapter_mod = importlib.import_module(module_name)
    QQAdapter = getattr(adapter_mod, "QQAdapter", None)
    if QQAdapter is None or not hasattr(QQAdapter, "send_model_picker"):
        sys.exit("  x QQAdapter.send_model_picker missing")
    adapter_note = "adapter import ok"
except ModuleNotFoundError as exc:  # noqa: BLE001 - missing deps is not a patch failure
    adapter_note = "adapter import skipped (missing dep %s)" % (exc.name or "?")
except Exception as exc:  # noqa: BLE001 - missing deps is not a patch failure
    adapter_note = "adapter import skipped (%s)" % type(exc).__name__

print("  ok: layout=%s, keyboard rows=%d, button_data round-trip ok, %s"
      % (qq_rel, len(rows), adapter_note))
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
