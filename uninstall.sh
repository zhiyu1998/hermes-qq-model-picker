#!/usr/bin/env bash
# Remove the QQ /model interactive picker patch from a Hermes Agent checkout.
#
# Usage:
#   ./uninstall.sh              # restore the two patched files
#   ./uninstall.sh --restart    # restore and restart the gateway
#
# Environment:
#   HERMES_DIR   Hermes checkout (default: ~/.hermes/hermes-agent)

set -euo pipefail

HERMES_DIR="${HERMES_DIR:-$HOME/.hermes/hermes-agent}"
RESTART=0

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=1 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'x %s\n' "$*" >&2; exit 1; }

git -C "$HERMES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "not a git checkout: $HERMES_DIR (set HERMES_DIR=...)"
cd "$HERMES_DIR"

FILES="plugins/platforms/qqbot/adapter.py plugins/platforms/qqbot/keyboards.py"

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
