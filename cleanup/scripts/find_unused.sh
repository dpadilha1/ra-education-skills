#!/usr/bin/env bash
# find_unused.sh: files nothing mentions, exact duplicates, versioned siblings, junk, empties.
# Usage: find_unused.sh [repo_root] [skip_regex] [archive_dirs]   (skip_regex: protected paths, extended regex;
#   archive_dirs: one folder, or several separated by commas; left out of every section but junk)
set -u

# show non-ASCII paths as they are (git quotes them by default)
git() { command git -c core.quotepath=off "$@"; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
{ [ -n "$root" ] && cd "$root"; } || { echo "ERROR: not a git repo"; exit 1; }
SKIP="${2:-}"
EXCL=()
# archive folders: archived files are unused on purpose, and a mention inside one is history
ARCH_RE=""
IFS=',' read -r -a _arch <<< "${3:-}"
for a in ${_arch[@]+"${_arch[@]}"}; do
  a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"; a="${a#./}"; a="${a%/}"
  [ -n "$a" ] || continue
  e="$(printf '%s' "$a" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"; ARCH_RE="${ARCH_RE:+$ARCH_RE|}$e"
  EXCL+=(":(exclude)$a")
done
noarch() { if [ -n "$ARCH_RE" ]; then grep -vE "^($ARCH_RE)/"; else cat; fi; }
MAX="${CLEANUP_MAX:-50}"   # lines per section; CLEANUP_MAX=<n> shows more
case "$MAX" in ""|*[!0-9]*) MAX=50 ;; esac

cap() { awk -v max="$MAX" 'NR<=max{print} END{if(NR>max) printf "... %d more\n", NR-max; if(NR==0) print "none"}'; }

tmp="$(mktemp "${TMPDIR:-/tmp}/unused.XXXXXX")"
trap 'rm -f "$tmp" "$tmp".*' EXIT

# never "unused" by design: docs for people/agents, entry points, config, dotfiles, tests, migrations
ALWAYS='(^|/)(README|LICENSE|CHANGELOG|CLAUDE|AGENTS|GEMINI|SKILL)[^/]*$|(^|/)(index|main|app|server|worker)\.[a-z]+$|(^|/)(package|tsconfig|jsconfig|wrangler|vercel|netlify|vite\.config|next\.config|tailwind\.config|postcss\.config|eslint|prettier)[^/]*$|(^|/)\.[^/]+$|(^|/)(test|tests|__tests__|migrations|\.github|\.claude|\.agents|\.codex|\.gemini)/|\.(test|spec)\.[a-z]+$|(^|/)(favicon|robots|sitemap|manifest)'

all_files() { git ls-files; git ls-files --others --exclude-standard; }
files() { all_files | noarch; }

ROLL="${CLEANUP_ROLL:-10}"   # a folder with more unused files than this prints as one line
# files directly inside each folder, to print "N unused of M"
files | awk '{ d=$0; if (!sub(/\/[^\/]*$/, "", d)) d="(root)"; n[d]++ } END { for (d in n) print d "\t" n[d] }' > "$tmp.tot"
echo "== files nothing else mentions (path, last commit, name searched; a folder with over $ROLL is one line) =="
# name to search per file: code is often imported without its extension, everything else by full name
files | grep -vE "$ALWAYS" | { if [ -n "$SKIP" ]; then grep -vE "$SKIP"; else cat; fi; } \
  | while IFS= read -r f; do
      b="${f##*/}"; s="${b%.*}"
      case "$b" in
        *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.py|*.vue|*.svelte|*.html|*.htm)
          if [ ${#s} -ge 4 ]; then q="$s"; else q="$b"; fi ;;
        *) q="$b" ;;
      esac
      printf '%s\t%s\n' "$q" "$f"
    done > "$tmp.map"
cp "$tmp.map" "$tmp.map2"
cut -f1 "$tmp.map" | sort -u > "$tmp.q"
# one search for all names at once: path:match for every mention
: > "$tmp.hits"
[ -s "$tmp.q" ] && git grep -oIF --untracked -f "$tmp.q" -- . ${EXCL[@]+"${EXCL[@]}"} > "$tmp.hits" 2>/dev/null
# a name counts as used when it shows up in any file other than its own
awk -F'\t' '
  FILENAME==ARGV[1] { own[$1]=own[$1] SUBSEP $2 SUBSEP; next }
  FILENAME==ARGV[2] { i=index($0, ":"); p=substr($0, 1, i-1); m=substr($0, i+1)
                      if (index(own[m], SUBSEP p SUBSEP)==0) used[m]=1; next }
  !($1 in used) { print $2 "\t" $1 }' "$tmp.map" "$tmp.hits" "$tmp.map2" \
  | while IFS=$'\t' read -r f q; do
      d="$(git log -1 --format=%cs -- "$f" 2>/dev/null)"
      printf '%s\t%s\t%s\n' "$f" "${d:-untracked}" "$q"
    done \
  | awk -F'\t' -v roll="$ROLL" 'FNR==NR { tot[$1]=$2; next } {
      d=$1; if (!sub(/\/[^\/]*$/, "", d)) d="(root)"
      n[d]++; row[d, n[d]]=$0
      if ($2=="untracked") u[d]++
      else { if (!(d in lo) || $2<lo[d]) lo[d]=$2; if (!(d in hi) || $2>hi[d]) hi[d]=$2 } }
    END { for (d in n) {
      if (n[d] <= roll) { for (i=1; i<=n[d]; i++) print row[d, i]; continue }
      c=(d in lo) ? "last commits " lo[d] " to " hi[d] : "no commits"
      if (u[d]) c=c ", " u[d] " untracked"
      printf "%s/\t%d unused of %d files, rolled up\t%s\n", d, n[d], tot[d], c } }' "$tmp.tot" - \
  | sort | cap

echo "== exact duplicates (count, then paths; files under 64 bytes skipped) =="
# what is on disk now, not the staged copy (an edited file is no longer a duplicate); untracked files count too
# (regular files only: a symlink and its target are not duplicates, and archiving the target would break the link)
files | while IFS= read -r f; do [ -f "$f" ] && [ ! -L "$f" ] && { [ -r "$f" ] && printf '%s\n' "$f" || echo "$f" >> "$tmp.unr"; }; done > "$tmp.ex"
tr '\n' '\0' < "$tmp.ex" | xargs -0 wc -c -- 2>/dev/null \
  | awk '{ n=$1; sub(/^ *[0-9]+ /, ""); if ($0 != "total" && n >= 64) print }' > "$tmp.big"
if [ ! -s "$tmp.big" ]; then
  echo "none"
elif git hash-object --no-filters --stdin-paths < "$tmp.big" > "$tmp.h" 2>/dev/null \
  && [ "$(wc -l < "$tmp.h" | tr -d ' ')" = "$(wc -l < "$tmp.big" | tr -d ' ')" ]; then
  # raw bytes, no git filters (CRLF and LF copies differ); one hash per path or no grouping at all
  paste "$tmp.h" "$tmp.big" \
    | awk -F'\t' '{ g[$1]=g[$1] "\t" $2; n[$1]++ } END { for (k in g) if (n[k]>1) print n[k] g[k] }' | sort -rn | cap
else
  echo "not checked: git could not hash every file"
fi
[ -s "$tmp.unr" ] && echo "not checked: $(wc -l < "$tmp.unr" | tr -d ' ') unreadable file(s) left out of the duplicate check"

echo "== versioned siblings (same name, different version: keep the live one) =="
files | awk '{
  b=$0; sub(/.*\//, "", b); d=substr($0, 1, length($0)-length(b))
  e=""; if (match(b, /\.[^.]+$/)) e=substr(b, RSTART)
  k=tolower(substr(b, 1, length(b)-length(e)))
  gsub(/([-_ ]?(v[0-9]+|copy|final|old|backup|bak|draft|new|[(][0-9]+[)]))+$/, "", k)
  key=d k e; g[key]=g[key] "\t" $0; n[key]++ }
  END { for (k in g) if (n[k]>1) print n[k] g[k] }' | sort -rn | cap

echo "== junk (OS and editor leftovers, tracked or not ignored) =="
all_files | grep -E '(^|/)(\.DS_Store|Thumbs\.db|desktop\.ini|~\$[^/]*|\.~lock[^/]*)$|\.(log|tmp|swp|swo|orig|rej|bak)$|~$' | cap

echo "== empty files tracked =="
git ls-files -s | awk -F'\t' '{ split($1, a, " ") } a[2]=="e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" { print $2 }' | noarch | cap

echo "== empty folders on disk (not ignored) =="
find . -type d -empty -not -path './.git/*' -not -path '*/node_modules/*' | sed 's|^\./||' \
  | while IFS= read -r d; do git check-ignore -q "$d/" || echo "$d"; done | cap
