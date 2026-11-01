#!/usr/bin/env bash
# review_archive.sh: facts for the archive usefulness review. Prints findings only, changes nothing.
# Usage: review_archive.sh [repo_root] [archive_dirs] [min_age_days]   (defaults: git root, _archive, 90; 0 = all)
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
MIN_AGE="${3:-90}"
MAX="${CLEANUP_MAX:-40}"   # lines per section; CLEANUP_MAX=<n> shows more
case "$MAX" in ""|*[!0-9]*) MAX=40 ;; esac
found=(); for a in "${ARCHES[@]}"; do if [ -d "$a" ]; then found+=("$a"); else echo "no archive folder: $a"; fi; done
[ ${#found[@]} -gt 0 ] || exit 0
ARCHES=("${found[@]}")
multi=0; [ ${#ARCHES[@]} -gt 1 ] && multi=1
# with one archive, paths are shown relative to it; with several, from the root
rel() { if [ "$multi" = 0 ]; then sed "s|^${ARCHES[0]}/||"; else cat; fi; }

cap() { awk -v max="$MAX" 'NR<=max{print} END{if(NR>max) printf "... %d more\n", NR-max; if(NR==0) print "none"}'; }
hk() { awk -v s="$1" 'BEGIN { u="KB"; if (s>=1024) {s/=1024; u="MB"} if (s>=1024) {s/=1024; u="GB"} printf "%.1f%s", s, u }'; }
sizesum() { tr '\n' '\0' | xargs -0 -r du -k 2>/dev/null | awk '{s+=$1} END {print s+0}'; }   # paths on stdin -> KB
epoch() { date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

TEXT='\.(md|txt|csv|tsv|json|jsonc|ya?ml|toml|js|mjs|cjs|ts|tsx|jsx|py|sh|html|css|sql)$'
MEDIA='\.(mp4|mov|m4v|avi|mkv|webm|wav|mp3|m4a|aiff?|flac|png|jpe?g|webp|gif|heic|tiff?|psd|ai|pdf|zip)$'
AV='\.(mp4|mov|m4v|avi|mkv|webm|wav|mp3|m4a|aiff?|flac)$'
REBUILD='(^|/)(node_modules|\.next|dist|build|\.wrangler|__pycache__|\.venv|venv)(/|$)'
COMMON='^(README|CLAUDE|AGENTS|GEMINI|index|MOVES|LEDGER|package|package-lock|LICENSE)(\.[a-z]+)?$'

umask 077   # the temp files hold repository paths and hashes: nobody else reads them
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/archive.XXXXXX")" || exit 1   # a private folder: a planted symlink in a shared /tmp can't redirect a write
tmp="$tmpdir/t"
trap 'rm -rf "$tmpdir"' EXIT
# hash the list in $1 as raw bytes (no git filters); prints hash<TAB>path, and fails unless every path got a hash
hash_list() {
  git hash-object --no-filters --stdin-paths < "$1" > "$tmp.h" 2>/dev/null || return 1
  [ "$(wc -l < "$tmp.h" | tr -d ' ')" = "$(wc -l < "$1" | tr -d ' ')" ] || return 1
  paste "$tmp.h" "$1"
}
# live files (tracked + untracked not ignored), never the archive itself: hash of what is on disk now<TAB>path
git ls-files --cached --others --exclude-standard | grep -vE "^($ARCH_RE)/" \
  | while IFS= read -r f; do [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"; done > "$tmp.livefiles"
: > "$tmp.live"
live_ok=1
if [ -s "$tmp.livefiles" ]; then hash_list "$tmp.livefiles" > "$tmp.live" || { live_ok=0; : > "$tmp.live"; }; fi
: > "$tmp.review"; T_ALL=0; T_TXT=0; T_MED=0; T_REB=0; young=0; young_kb=0
now=$(date +%s)

echo "== archive folders (only files git tracks can be restored after a delete) =="
for a in "${ARCHES[@]}"; do
  on_disk=$(find "$a" -type f ! -name .DS_Store | wc -l | tr -d ' ')
  in_git=$(git ls-files -- "$a" | while IFS= read -r f; do [ -f "$f" ] && echo x; done | wc -l | tr -d ' ')   # tracked and still on disk
  if git check-ignore -q "$a/"; then
    echo "$a/	ignored by git: yes (deleting any file is permanent)"
  else
    changed=$(git diff --name-only HEAD -- "$a" 2>/dev/null | wc -l | tr -d ' ')
    note=""; [ "$changed" -gt 0 ] && note=" ($changed changed since the last commit: a delete loses those edits)"
    echo "$a/	tracked: $in_git files in git$note, $((on_disk - in_git)) not in git (deleting those is permanent)"
  fi
done

echo "== folders up for review (age >= ${MIN_AGE}d): folder, age, size, text, media, other, rebuildable, files, MOVES.tsv =="
for a in "${ARCHES[@]}"; do for d in "$a"/*/; do
  [ -d "$d" ] || continue; d="${d%/}"; n="${d##*/}"; lab="$n"; [ "$multi" = 1 ] && lab="$d"
  dt="$(echo "$n" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')"
  if [ -n "$dt" ]; then t="$(epoch "$dt")"; src=""; else t="$(mtime "$d")"; src=" (undated: by mtime)"; fi
  age=$(( (now - ${t:-$now}) / 86400 ))
  find "$d" -type f ! -name .DS_Store > "$tmp.f"
  all=$(sizesum < "$tmp.f")
  if [ "$age" -lt "$MIN_AGE" ]; then young=$((young + 1)); young_kb=$((young_kb + all)); continue; fi
  echo "$d" >> "$tmp.review"
  # text and media leave out rebuildable folders, so nothing is counted twice
  txt=$(grep -iE "$TEXT" "$tmp.f" | grep -vE "$REBUILD" | sizesum)
  med=$(grep -iE "$MEDIA" "$tmp.f" | grep -vE "$REBUILD" | sizesum)
  reb=$(grep -E "$REBUILD" "$tmp.f" | sizesum)
  oth=$((all - txt - med - reb)); [ "$oth" -lt 0 ] && oth=0
  mv=no; [ -f "$d/MOVES.tsv" ] && mv=yes
  T_ALL=$((T_ALL + all)); T_TXT=$((T_TXT + txt)); T_MED=$((T_MED + med)); T_REB=$((T_REB + reb))
  printf '%s\t%sd%s\t%s\ttext %s\tmedia %s\tother %s\trebuildable %s\t%s files\tMOVES.tsv %s\n' \
    "$lab" "$age" "$src" "$(hk "$all")" "$(hk "$txt")" "$(hk "$med")" "$(hk "$oth")" "$(hk "$reb")" \
    "$(wc -l < "$tmp.f" | tr -d ' ')" "$mv"
done; done
for a in "${ARCHES[@]}"; do
  loose="$(find "$a" -maxdepth 1 -type f ! -name .DS_Store ! -name LEDGER.tsv)"
  if [ -n "$loose" ]; then
    echo "loose files at the archive root ($a): $(echo "$loose" | wc -l | tr -d ' '), $(hk "$(echo "$loose" | sizesum)")"
  fi
done
echo "younger than ${MIN_AGE}d, skipped: $young folders, $(hk "$young_kb")"

while IFS= read -r d; do find "$d" -type f ! -name .DS_Store ! -name MOVES.tsv; done < "$tmp.review" \
  | grep -vE "$REBUILD" > "$tmp.files"

echo "== still mentioned in live files (archived file -> first live file naming it) =="
# one search for all archived names at once, outside the archive itself
# (code files also by name without extension, since imports often drop it)
CODE='\.(js|jsx|ts|tsx|mjs|cjs|py|vue|svelte|html|htm)$'
awk -F/ -v code="$CODE" '{ b=$NF; print b; if (b ~ code) { s=b; sub(/\.[^.]*$/, "", s); if (length(s)>=4) print s } }' "$tmp.files" \
  | grep -vE "$COMMON" | sort -u > "$tmp.names"
: > "$tmp.hits"
ex=(); for a in "${ARCHES[@]}"; do ex+=(":(exclude)$a"); done
[ -s "$tmp.names" ] && git grep -oIF --untracked -f "$tmp.names" -- . "${ex[@]}" > "$tmp.hits" 2>/dev/null
awk -v code="$CODE" 'FILENAME==ARGV[1] { i=index($0, ":"); m=substr($0, i+1); if (!(m in first)) first[m]=substr($0, 1, i-1); next }
  { b=$0; sub(/.*\//, "", b); s=""; if (b ~ code) { s=b; sub(/\.[^.]*$/, "", s) }
    if (b in first) print $0 "\t-> " first[b]; else if (s!="" && (s in first)) print $0 "\t-> " first[s] }' "$tmp.hits" "$tmp.files" \
  | rel | cap

echo "== exact copy exists live (archived file = live path; files under 64 bytes skipped) =="
while IFS= read -r d; do find "$d" -type f -size +63c ! -name .DS_Store ! -name MOVES.tsv; done < "$tmp.review" \
  | grep -vE "$REBUILD" > "$tmp.sized"
if [ "$live_ok" = 0 ]; then
  echo "not checked: git could not hash every live file"
elif [ -s "$tmp.sized" ]; then
  if hash_list "$tmp.sized" > "$tmp.sh"; then
    awk -F'\t' 'FNR==NR { if (!($1 in live)) live[$1]=$2; next } ($1 in live) { print $2 "\t= " live[$1] }' "$tmp.live" "$tmp.sh" \
      | rel | cap
  else
    echo "not checked: git could not hash every archived file"
  fi
else
  echo "none"
fi

echo "== MOVES.tsv checks (original path in use again, or logged file missing) =="
while IFS= read -r d; do
  [ -f "$d/MOVES.tsv" ] || continue
  # empty columns become "-" so a missing "to" isn't read as the note
  tail -n +2 "$d/MOVES.tsv" | awk -F'\t' 'BEGIN { OFS="\t" } $1=="from" && $2=="to" { next } { for (i=1; i<=3; i++) if ($i=="") $i="-"; print $1, $2, $3 }' \
    | while IFS=$'\t' read -r from to _note; do
        [ "$from" != "-" ] && [ -e "$from" ] && printf '%s\toriginal path exists again: %s\n' "$(echo "$d" | rel)" "$from"
        [ "$to" != "-" ] && [ ! -e "$to" ] && printf '%s\tlogged but missing: %s\n' "$(echo "$d" | rel)" "$to"
      done
done < "$tmp.review" | cap

echo "== biggest media per folder (top 5; length if ffprobe is installed) =="
ff=no; command -v ffprobe >/dev/null && ff=yes
while IFS= read -r d; do
  find "$d" -type f | grep -iE "$MEDIA" | grep -vE "$REBUILD" | tr '\n' '\0' | xargs -0 -r du -k 2>/dev/null | sort -rn | head -n 5 \
    | while IFS=$'\t' read -r k f; do
        len=""
        if [ "$ff" = yes ] && echo "$f" | grep -qiE "$AV"; then
          len="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null \
                 | awk '{ printf "%dm%02ds", $1/60, $1%60 }')"
        fi
        printf '%s\t%s\t%s\n' "$(hk "$k")" "$(echo "$f" | rel)" "$len"
      done
done < "$tmp.review" | cap

echo "== totals for reviewed folders =="
echo "size $(hk "$T_ALL") · text $(hk "$T_TXT") · media $(hk "$T_MED") · rebuildable $(hk "$T_REB")"
echo "if media goes to cold storage and rebuildables are deleted, the archive drops to ~$(hk $((T_ALL - T_MED - T_REB)))"
