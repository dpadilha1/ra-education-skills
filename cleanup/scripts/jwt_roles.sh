#!/usr/bin/env bash
# jwt_roles.sh: the "role" claim of every JWT on one line of a file, one result per token, in order.
# Usage: jwt_roles.sh <file> <line>
# Prints the role, or "unknown" (no role, an unreadable token, or, without jq, more than one "role" key).
# Never prints the token itself.
set -u
f="${1:-}"; l="${2:-}"
case "$l" in ""|*[!0-9]*) f="" ;; esac
[ -f "$f" ] || { echo "usage: jwt_roles.sh <file> <line>" >&2; exit 1; }
sed -n "${l}p" "$f" | grep -oE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' | cut -d. -f2 | while IFS= read -r p; do
  json="$(printf '%s\n' "$p" | tr '_-' '/+' | awk '{ while (length($0)%4) $0=$0 "="; print }' | { base64 -d 2>/dev/null || base64 -D 2>/dev/null; })"
  if command -v jq >/dev/null 2>&1; then
    r="$(printf '%s' "$json" | jq -r '.role | strings' 2>/dev/null)"
  elif [ "$(printf '%s' "$json" | grep -oE '"role" *:' | wc -l | tr -d ' ')" = 1 ]; then
    r="$(printf '%s' "$json" | grep -oE '"role" *: *"[a-z_]+"' | sed -E 's/.*: *"([a-z_]+)"/\1/')"
  else
    r=""
  fi
  case "$r" in ""|*[!a-z_]*) echo unknown ;; *) echo "$r" ;; esac
done
