#!/usr/bin/env bash
# find_big.sh: big files now, big files in git history, heavy ignored folders.
# Usage: find_big.sh [repo_root] [min_kb]   (defaults: current git root, 1024)
set -u

# show non-ASCII paths as they are (git quotes them by default)
git() { command git -c core.quotepath=off "$@"; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
{ [ -n "$root" ] && cd "$root"; } || { echo "ERROR: not a git repo"; exit 1; }
MIN_KB="${2:-1024}"
MAX="${CLEANUP_MAX:-30}"   # lines per section; CLEANUP_MAX=<n> shows more
case "$MAX" in ""|*[!0-9]*) MAX=30 ;; esac

# keep a section short: first $MAX lines, then a count
cap() { awk -v max="$MAX" 'NR<=max{print} END{if(NR>max) printf "... %d more\n", NR-max; if(NR==0) print "none"}'; }

# first field in KB -> 1.2MB / 3.4GB
human() { awk '{ s=$1; u="KB"; if (s>=1024){s/=1024; u="MB"} if (s>=1024){s/=1024; u="GB"} $1=sprintf("%.1f%s", s, u); print }'; }

# NUL-separated paths on stdin -> kb<TAB>label<TAB>path, only those >= MIN_KB (disk blocks, so small files round up)
big() { xargs -0 -r du -sk 2>/dev/null | awk -F'\t' -v m="$MIN_KB" -v t="$1" '$1>=m {print $1 "\t" t "\t" $2}'; }

echo "== big files now (>= ${MIN_KB}KB) =="
{ git ls-files -z | big tracked; git ls-files -z --others --exclude-standard | big not-ignored; } \
  | sort -rn | human | cap

echo "== biggest files ever committed (>= ${MIN_KB}KB) =="
fmt="$(printf '%%(objecttype)\t%%(objectsize)\t%%(rest)')"
git rev-list --objects --all | git cat-file --batch-check="$fmt" \
  | awk -F'\t' -v m="$MIN_KB" '$1=="blob" && $2>=m*1024 {printf "%d\t%s\n", $2/1024, $3}' \
  | sort -rn | awk -F'\t' '!seen[$2]++' | head -n 100 \
  | while IFS=$'\t' read -r kb p; do
      if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then s=tracked
      elif [ -e "$p" ]; then s="history (file on disk, untracked)"
      else s=history-only; fi
      printf '%s\t%s\t%s\n' "$kb" "$s" "$p"
    done | human | cap

echo "== git history size =="
git count-objects -vH | awk -F': ' '/^size:/ { l=$2 } /^size-pack:/ { p=$2 } END { print "packed: " p " · loose: " l }'

echo "== ignored folders and files on disk (not in git: disk only, 0 tokens) =="
git ls-files -z --others --ignored --exclude-standard --directory | big ignored | sort -rn | human | cap

echo "== generated files tracked (usually rebuildable) =="
git ls-files | grep -E '(^|/)(dist|build|\.next|coverage)/|\.min\.(js|css)$|\.map$' | cap
