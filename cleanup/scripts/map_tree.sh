#!/usr/bin/env bash
# map_tree.sh: folder map and structure smells. Prints findings only.
# Usage: map_tree.sh [repo_root] [archive_dirs] [max_depth]   (defaults: git root, _archive, 5)
#   archive_dirs: one folder, or several separated by commas (docs/archive,app/docs/archive)
set -u

# show non-ASCII paths as they are (git quotes them by default)
git() { command git -c core.quotepath=off "$@"; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
{ [ -n "$root" ] && cd "$root"; } || { echo "ERROR: not a git repo"; exit 1; }
ARCH_LIST="${2:-_archive}"
# archive folders: one, or several separated by commas (one per area)
ARCHES=()
IFS=',' read -r -a _arch <<< "$ARCH_LIST"
for a in ${_arch[@]+"${_arch[@]}"}; do
  a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"; a="${a#./}"; a="${a%/}"
  [ -n "$a" ] && ARCHES+=("$a")
done
[ ${#ARCHES[@]} -gt 0 ] || ARCHES=(_archive)
esc() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
ARCH_RE="$(for a in "${ARCHES[@]}"; do esc "$a"; echo; done | paste -sd'|' -)"   # a1|a2, regex-escaped
DEPTH="${3:-5}"
MAX="${CLEANUP_MAX:-40}"   # lines per section; CLEANUP_MAX=<n> shows more
case "$MAX" in ""|*[!0-9]*) MAX=40 ;; esac

cap() { awk -v max="$MAX" 'NR<=max{print} END{if(NR>max) printf "... %d more\n", NR-max; if(NR==0) print "none"}'; }

umask 077   # the temp files hold repository paths and hashes: nobody else reads them
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tree.XXXXXX")" || exit 1   # a private folder: a planted symlink in a shared /tmp can't redirect a write
list="$tmpdir/list"; dirs="$list.dirs"; kids="$list.kids"
trap 'rm -rf "$tmpdir"' EXIT

# every file git sees (tracked + untracked not ignored), every folder above them
# archive contents left out: a tracked archive is judged by the archive check, not as live folders
{ git ls-files; git ls-files --others --exclude-standard; } | sort -u > "$list.all"
grep -vE "^($ARCH_RE)/" "$list.all" > "$list"
awk -F/ '{ p=""; for (i=1; i<NF; i++) { p=(i==1 ? $i : p "/" $i); if (!s[p]++) print p } }' "$list" > "$dirs"
# children per folder (files + subfolders): count<TAB>folder
awk -F/ '{ p=""; for (i=1; i<=NF; i++) { c=(i==1 ? $i : p "/" $i); k[p "\t" c]=1; p=c } }
  END { for (x in k) { split(x, a, "\t"); n[a[1]]++ } for (d in n) if (d!="") print n[d] "\t" d }' "$list" > "$kids"

echo "== top-level map (folder, files, deepest level) =="
awk -F/ '{ t=(NF>1) ? $1 "/" : "(root files)"; n[t]++; if (NF>d[t]) d[t]=NF }
  END { for (k in n) printf "%s\t%d files\tdepth %d\n", k, n[k], d[k] }' "$list.all" | sort

echo "== loose files at root (not a usual root file) =="
EXPECTED='^(README|LICENSE|CHANGELOG|CLAUDE|AGENTS|GEMINI|CONTRIBUTING|SECURITY)(\.[a-z]+)?$|^\.|^(package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|tsconfig[^/]*\.json|jsconfig\.json|wrangler\.(toml|jsonc?)|vercel\.json|netlify\.toml|Dockerfile|docker-compose[^/]*|Makefile|requirements[^/]*\.txt|pyproject\.toml|Pipfile(\.lock)?|[a-z.]+\.config\.(js|cjs|mjs|ts))$'
awk -F/ 'NF==1' "$list" | grep -vE "$EXPECTED" | cap

echo "== folders deeper than $DEPTH levels =="
awk -F/ -v m="$DEPTH" 'NF-1>m { sub(/\/[^\/]*$/, ""); print }' "$list" | sort -u | cap

echo "== folders with a single item (merge up?; a chain shows only its top folder) =="
awk -F'\t' 'FNR==NR { if ($1==1) s[$2]=1; next }
  $1==1 { p=$2; sub(/\/[^\/]*$/, "", p); if (p==$2 || !(p in s)) print $2 }' "$kids" "$kids" | sort | cap

echo "== crowded folders (over 50 items directly inside) =="
awk -F'\t' '$1>50 { print $1 " items\t" $2 }' "$kids" | sort -rn | cap

echo "== names with spaces, accents or other non-ASCII =="
cat "$dirs" "$list" | LC_ALL=C awk -F/ '$NF ~ / / || $NF ~ /[^ -~]/' | sort -u | cap

echo "== folders mixing naming styles (kebab-case, snake_case, spaces, camelCase) =="
cat "$dirs" "$list" | awk -F/ '{
  n=$NF; sub(/\.[^.]*$/, "", n); par=(NF>1) ? substr($0, 1, length($0)-length($NF)-1) : "(root)"
  st=""; if (n ~ / /) st="spaces"; else if (n ~ /_/ && n !~ /-/) st="snake"
  else if (n ~ /-/ && n !~ /_/) st="kebab"; else if (n ~ /[a-z][A-Z]/) st="camel"
  if (st!="" && !seen[par SUBSEP st]++) { s[par]=s[par] " " st; c[par]++ } }
  END { for (p in c) if (c[p]>1) print p ":" s[p] }' | sort | cap

echo "== twin folders (same parent, same purpose or same name in another case) =="
awk -F/ '{
  n=tolower($NF); par=(NF>1) ? substr($0, 1, length($0)-length($NF)-1) : "(root)"; g=n
  if (n ~ /^(docs?|documentation)$/) g="docs"
  else if (n ~ /^(assets|images?|img|media|static)$/) g="assets"
  else if (n ~ /^(utils?|helpers?|lib|common|shared)$/) g="utils"
  else if (n ~ /^(tmp|temp|scratch)$/) g="tmp"
  else if (n ~ /^(_?archives?|_?old|backups?|bak|legacy|deprecated)$/) g="archive"
  else if (n ~ /^(outputs?|exports?|out)$/) g="output"
  else if (n ~ /^(scripts|tools|bin)$/) g="scripts"
  else if (n ~ /^(tests?|__tests__|spec)$/) g="tests"
  k=par SUBSEP g; m[k]=m[k] "  " $0; cnt[k]++ }
  END { for (k in m) if (cnt[k]>1) print m[k] }' "$dirs" | sed 's/^  //' | sort | cap

echo "== dump folders (where things pile up) =="
grep -iE '(^|/)(outputs?|claude[ _-]?outputs?|new folder[^/]*|untitled[^/]*|misc|stuff|temp|tmp|downloads?|exports?|scratch|random|wip)$' "$dirs" | cap

echo "== archive-like folders outside the archive folders ($(printf '%s/, ' "${ARCHES[@]}" | sed 's/, $//')) =="
grep -iE '(^|/)(_?archives?|_?old|backups?|bak|legacy|deprecated|attic|trash)$' "$dirs" | grep -vE "^($ARCH_RE)(/|$)" | cap

for ARCHIVE in "${ARCHES[@]}"; do
echo "== archive check ($ARCHIVE) =="
if [ -d "$ARCHIVE" ]; then
  if git check-ignore -q "$ARCHIVE/"; then echo "ignored by git: yes"; else echo "tracked by git (fine: history keeps it)"; fi
  {
    for d in "$ARCHIVE"/*/; do
      [ -d "$d" ] || continue; n="${d%/}"; n="${n##*/}"
      echo "$n" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-' || echo "not dated: $n"
      [ -f "$d/MOVES.tsv" ] || echo "no MOVES.tsv: $n"
    done
    find "$ARCHIVE" -maxdepth 1 -type f ! -name '.DS_Store' ! -name 'LEDGER.tsv' | sed "s|^$ARCHIVE/|loose file: |"
  } | cap
else
  echo "no archive folder"
fi
done

echo "== top-level folders no root doc mentions (README, CLAUDE.md, AGENTS.md, GEMINI.md; tool dot-folders skipped) =="
# tool folders: the tool that owns them is the doc (other dot-folders are still checked)
TOOL_DIRS='^\.(claude|agents|codex|gemini|github|gitlab|circleci|vscode|idea|cursor|devcontainer|husky|changeset|storybook|vercel|wrangler|netlify|cache)$'
awk -F/ 'NF>1 { print $1 }' "$list.all" | grep -vE "$TOOL_DIRS" | sort -u | while IFS= read -r d; do
  # whole-name match, so a folder called "a" isn't "mentioned" by every word with an a in it
  e="$(printf '%s' "$d" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
  grep -qsE "(^|[^A-Za-z0-9_-])$e(/|[^A-Za-z0-9_-]|$)" README.md CLAUDE.md AGENTS.md GEMINI.md || echo "$d/"
done | cap
