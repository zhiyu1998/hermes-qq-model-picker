#!/usr/bin/env bash
# Remove the QQ /model interactive picker patch from a Hermes Agent checkout.
#
# Usage:
#   ./uninstall.sh              # restore the two patched files
#   ./uninstall.sh --restart    # restore and restart the gateway
#
# Environment:
#   HERMES_DIR   Hermes checkout (default: ~/.hermes/hermes-agent)
#
# Works with both upstream layouts (plugins/platforms/qqbot and the older
# gateway/platforms/qqbot) by probing for the plugin directory first.

set -euo pipefail

HERMES_DIR="${HERMES_DIR:-$HOME/.hermes/hermes-agent}"
RESTART=0

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=1 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'x %s\n' "$*" >&2; exit 1; }

[ -d "$HERMES_DIR" ] || fail "Hermes checkout not found: $HERMES_DIR (set HERMES_DIR=...)"
git -C "$HERMES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "not a git checkout: $HERMES_DIR (set HERMES_DIR=...)"
cd "$HERMES_DIR"

# Probe both upstream layouts; older Hermes keeps the plugin under gateway/.
QQ_REL=""
for base in plugins/platforms/qqbot gateway/platforms/qqbot; do
  if [ -f "$HERMES_DIR/$base/adapter.py" ] && [ -f "$HERMES_DIR/$base/keyboards.py" ]; then
    QQ_REL="$base"
    break
  fi
done
if [ -z "$QQ_REL" ]; then
  say "= QQ Bot plugin not found (nothing to restore)"
  exit 0
fi

FILES="$QQ_REL/adapter.py $QQ_REL/keyboards.py"
say "= layout: $QQ_REL"

dirty=$(git status --porcelain -- $FILES || true)
if [ -z "$dirty" ]; then
  say "= nothing to restore (files already match upstream)"
else
  say "> restoring: $FILES"
  # Keep a safety copy in case local edits outside this patch existed.
  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$HOME/.hermes/qq-model-picker-backup"
  for f in $FILES; do
    [ -f "$f" ] && cp "$f" "$HOME/.hermes/qq-model-picker-backup/$(basename "$f").$stamp"
  done
  git checkout -- $FILES
  say "+ restored (backup in ~/.hermes/qq-model-picker-backup)"
fi

say "done. restart the gateway to drop the picker:"
say "  hermes gateway restart"
say "  # or: systemctl --user restart hermes-gateway.service"

if [ "$RESTART" = "1" ]; then
  if systemctl --user restart hermes-gateway.service 2>/dev/null; then
    sleep 3
    systemctl --user is-active hermes-gateway.service || fail "gateway did not come back up"
    say "+ gateway restarted"
  else
    say "! systemctl --user not available here; run: hermes gateway restart"
  fi
fi
