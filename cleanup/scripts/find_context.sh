#!/usr/bin/env bash
# find_context.sh: what Claude loads every session in this project, and what makes it heavy or stale.
# Usage: find_context.sh [repo_root] [big_doc_kb] [archive_dirs]   (defaults: current git root, 25, _archive)
#   archive_dirs: one folder, or several separated by commas (docs/archive,app/docs/archive)
set -u

# show non-ASCII paths as they are (git quotes them by default)
git() { command git -c core.quotepath=off "$@"; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
{ [ -n "$root" ] && cd "$root"; } || { echo "ERROR: not a git repo"; exit 1; }
BIG_KB="${2:-25}"
ARCH_LIST="${3:-_archive}"
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
MAX="${CLEANUP_MAX:-40}"   # lines per section; CLEANUP_MAX=<n> shows more
case "$MAX" in ""|*[!0-9]*) MAX=40 ;; esac

cap() { awk -v max="$MAX" 'NR<=max{print} END{if(NR>max) printf "... %d more\n", NR-max; if(NR==0) print "none"}'; }
tok() { wc -c < "$1" | awk '{printf "%d", $1/4}'; }          # rough: ~4 bytes per token
short() { sed -e "s|^$PWD/||" -e "s|^$HOME|~|"; }
files() { git ls-files; git ls-files --others --exclude-standard; }

umask 077   # the temp files hold repository paths and hashes: nobody else reads them
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/context.XXXXXX")" || exit 1   # a private folder: a planted symlink in a shared /tmp can't redirect a write
tmp="$tmpdir/t"
always="$tmp.always"; demand="$tmp.demand"; scan="$tmp.scan"; hop="$tmp.hop"
trap 'rm -rf "$tmpdir"' EXIT
: > "$always"; : > "$demand"

add() { [ -f "$1" ] && ! grep -qxF "$1" "$always" && echo "$1" >> "$always"; return 0; }

# a markdown file with fenced code blocks blanked out, line numbers kept (Claude Code skips imports in code)
nocode() { awk '/^[ \t]*(```|~~~)/ { f=!f; print ""; next } { print (f ? "" : $0) }' "$1" 2>/dev/null; }

resolve() {   # dir path -> absolute path
  # shellcheck disable=SC2088  # a literal ~/ the user wrote
  case "$2" in "~/"*) echo "$HOME/${2#??}" ;; /*) echo "$2" ;; *) echo "$1/$2" ;; esac
}

# @path imports outside code: line<TAB>path as written
atpaths() {
  nocode "$1" | grep -noE '(^|[[:space:]])@[~./A-Za-z0-9_][^[:space:]`)]*' \
    | awk '{ i=index($0, ":"); l=substr($0, 1, i-1); p=substr($0, i+1); sub(/^[ \t]*@/, "", p); print l "\t" p }'
}

# existing files a context file pulls in with @path (relative to that file)
imports() {
  dir="$(dirname "$1")"
  atpaths "$1" | while IFS=$'\t' read -r _ p; do q="$(resolve "$dir" "$p")"; [ -f "$q" ] && echo "$q"; done
}

# path-like references outside code (`backticks`, ](links), @imports): line<TAB>path
refs() {
  # shellcheck disable=SC2016  # awk code, not shell
  nocode "$1" | grep -noE '`[^` ]+`|\]\([^) ]+\)|(^|[[:space:]])@[~./A-Za-z0-9_][^[:space:]`)]*' | awk '{
    i=index($0, ":"); l=substr($0, 1, i-1); p=substr($0, i+1)
    sub(/^[ \t]+/, "", p); sub(/^(`|\]\()/, "", p); sub(/(`|\))$/, "", p); sub(/^@/, "", p)
    sub(/#.*$/, "", p); sub(/:[0-9]+$/, "", p)
    if (p=="" || p ~ /:\/\// || p ~ /[*<>{}$|()= ]/ || p ~ /^\//) next
    gsub(/%20/, " ", p)   # links write spaces as %20
    if (p ~ /\//) { if (p ~ /\/$/ || p ~ /\.(md|mdx|txt|json|jsonc|ya?ml|toml|sh|py|js|mjs|cjs|ts|tsx|jsx|html|css|sql|csv|tsv|pdf|png|jpe?g|svg|webp)$/) print l "\t" p }
    else if (p ~ /\.(md|mdx|txt|csv|tsv|sh)$/) print l "\t" p }'
}

# unscoped rules load every session, rules with paths: load on demand (rules folders are searched recursively)
rules() {
  [ -d "$1" ] || return 0
  find "$1" -type f -name '*.md' | while IFS= read -r f; do
    if head -n 10 "$f" | grep -q '^paths:'; then echo "$f" >> "$demand"; else add "$f"; fi
  done
}

# every session: global file and rules, project + parent folders' CLAUDE files, project rules, then imports
add "$HOME/.claude/CLAUDE.md"
rules "$HOME/.claude/rules"
has_claude=no
d="$PWD"
while :; do
  for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md; do
    [ "$d/$f" = "$HOME/.claude/CLAUDE.md" ] && continue
    [ -f "$d/$f" ] && { add "$d/$f"; has_claude=yes; }
  done
  [ "$d" = "/" ] && break; d="$(dirname "$d")"
done
# AGENTS.md is read at start only when no CLAUDE.md file exists in the project or its parents
if [ "$has_claude" = no ]; then
  d="$PWD"
  while :; do
    for f in AGENTS.md .claude/AGENTS.md; do add "$d/$f"; done
    [ "$d" = "/" ] && break; d="$(dirname "$d")"
  done
fi
rules "$PWD/.claude/rules"
# the loop also reads lines appended while it runs, so imports of imports are followed
while IFS= read -r f; do imports "$f" | while IFS= read -r p; do add "$p"; done; done < "$always"

# on demand: CLAUDE.md / AGENTS.md in subfolders
files | grep -E '(^|/)(CLAUDE|AGENTS)\.md$' | grep -vxE '(\.claude/)?(CLAUDE|AGENTS)\.md' \
  | sed "s|^|$PWD/|" | while IFS= read -r f; do grep -qxF "$f" "$always" || echo "$f"; done >> "$demand"
# archives are often ignored by git, but a CLAUDE.md inside one still loads: look on disk
ARCH_NAMES_RE="$(for a in "${ARCHES[@]}"; do esc "${a##*/}"; echo; done | sort -u | paste -sd'|' -)"
for a in "${ARCHES[@]}"; do echo "${a##*/}"; done | sort -u | while IFS= read -r an; do
  find . \( -name node_modules -o -name .git \) -prune -o -type d -name "$an" -print 2>/dev/null
done | while IFS= read -r d; do
      find "$d" \( -name node_modules -o -name .git \) -prune -o -type f \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name AGENTS.md -o -name GEMINI.md \) -print 2>/dev/null
    done | sed "s|^\./|$PWD/|" > "$tmp.arch"
while IFS= read -r f; do grep -qxF "$f" "$demand" "$always" || echo "$f"; done < "$tmp.arch" > "$tmp.arch2"
cat "$tmp.arch2" >> "$demand"

echo "== loaded every session by Claude Code (file, lines, ~tokens) =="
total=0
while IFS= read -r f; do
  t=$(tok "$f"); total=$((total + t))
  printf '%s\t%s lines\t~%s tokens\n' "$(echo "$f" | short)" "$(wc -l < "$f" | tr -d ' ')" "$t"
done < "$always"
slug="$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')"
mem="$HOME/.claude/projects/$slug/memory/MEMORY.md"
if [ -f "$mem" ]; then
  t=$(head -n 200 "$mem" | head -c 25600 | wc -c | awk '{printf "%d", $1/4}'); total=$((total + t))
  printf 'auto memory MEMORY.md (first 200 lines or 25KB)\t~%s tokens\n' "$t"
fi
echo "total: ~$total tokens (plus skill and agent descriptions, MCP tools)"

echo "== loaded on demand (file, ~tokens; one inside the archive still loads there: rename it) =="
while IFS= read -r f; do
  a=""; printf '/%s' "${f#"$PWD"/}" | grep -qE "/($ARCH_NAMES_RE)/" && a=$'\tIN ARCHIVE'
  printf '%s\t~%s tokens%s\n' "$(echo "$f" | short)" "$(tok "$f")" "$a"
done < "$demand" | cap
for f in AGENTS.md .claude/AGENTS.md; do
  [ -f "$f" ] && ! grep -qxF "$PWD/$f" "$always" && echo "note: Claude Code doesn't read $f (a CLAUDE.md exists) unless a CLAUDE.md imports it; Codex does"
done

echo "== other agents' instruction files Claude Code doesn't load (file, lines, ~tokens) =="
# Codex reads AGENTS.md, Gemini CLI reads GEMINI.md: checked below like the files above
files | grep -E '(^|/)(AGENTS|GEMINI)\.md$' | sed "s|^|$PWD/|" \
  | while IFS= read -r f; do grep -qxF "$f" "$always" "$demand" || echo "$f"; done > "$tmp.other"
while IFS= read -r f; do
  printf '%s\t%s lines\t~%s tokens\n' "$(echo "$f" | short)" "$(wc -l < "$f" | tr -d ' ')" "$(tok "$f")"
done < "$tmp.other" | cap

echo "== lines repeated between context files (normalized, 40+ chars) =="
norm() { tr '[:upper:]' '[:lower:]' < "$1" | sed -E 's/[^a-z0-9 ]+/ /g; s/ +/ /g; s/^ //; s/ $//' | awk 'length>=40' | sort -u; }
cat "$always" "$demand" "$tmp.other" > "$tmp"
while IFS= read -r a; do
  while IFS= read -r b; do
    [ "$a" \< "$b" ] || continue
    n=$(comm -12 <(norm "$a") <(norm "$b") | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && printf '%s <> %s\t%s lines\n' "$(echo "$a" | short)" "$(echo "$b" | short)" "$n"
  done < "$tmp"
done < "$tmp" | cap

echo "== stale pointers (file:line -> path that doesn't exist from the root, the file's folder or a nested repo) =="
# nested repos: a doc at the root often names paths inside them (src/app.js meaning app/src/app.js)
nested="$(find . -mindepth 2 -maxdepth 4 -name node_modules -prune -o -name .git -print 2>/dev/null \
  | sed -e 's|^\./||' -e 's|/\.git$||' | grep -vE "(^|/)($ARCH_RE)/")"
# files in this repo (archive left out) and in the nested repos, so a short path with a folder
# (lib/x.js for src/lib/x.js or app/src/lib/x.js) counts as found. Bare names (HANDOFF.md) never
# match this way: a same-named file elsewhere must not hide a stale pointer.
allf="$tmp.all"
{ files | grep -vE "(^|/)($ARCH_RE)/"
  while IFS= read -r r; do [ -n "$r" ] && git -C "$r" ls-files 2>/dev/null | sed "s|^|$r/|"; done <<< "$nested"; } \
  | awk '{ print "/" $0; n=split($0, a, "/"); p=""; for (i=1; i<n; i++) { p=p "/" a[i]; print p "/" } }' | sort -u > "$allf"
# project context files, plus the docs they point to (one hop)
grep "^$PWD/" "$tmp" > "$scan" || true
while IFS= read -r f; do
  refs "$f" | while IFS=$'\t' read -r _ p; do
    # shellcheck disable=SC2088  # a literal ~/ the user wrote
    case "$p" in ../*|*/../*|/*|"~/"*) continue ;; esac   # stay inside this repo
    q="$PWD/${p#./}"; [ -f "$q" ] && [[ "$q" == *.md ]] && echo "$q"
  done
done < "$scan" > "$hop"
cat "$scan" "$hop" | sort -u | grep -vE "/($ARCH_RE)/" | while IFS= read -r f; do
  dir="$(dirname "$f")"
  refs "$f" | while IFS=$'\t' read -r line p; do
    case "$p" in *YYYY*|*'<'*|*...*|*'*'*) continue ;; esac   # a template or a pattern, not a path
    # shellcheck disable=SC2088  # a literal ~/ the user wrote
    case "$p" in "~/"*) [ -e "$(resolve "$dir" "$p")" ] && continue ;;
      *) { [ -e "$PWD/${p#./}" ] || [ -e "$dir/$p" ]; } && continue
         hit=""; while IFS= read -r r; do [ -n "$r" ] && [ -e "$PWD/$r/${p#./}" ] && { hit=1; break; }; done <<< "$nested"
         [ -n "$hit" ] && continue
         s="/${p#./}"; [[ "${p#./}" == */?* ]] && grep -qE "$(printf '%s' "$s" | sed 's/[][\.*^$+?(){}|/]/\\&/g')/?\$" "$allf" && continue ;; esac
    printf '%s:%s\t-> %s\n' "$(echo "$f" | short)" "$line" "$p"
  done
done | sort -u | cap

echo "== big text docs (>= ${BIG_KB}KB; ~tokens if read whole; on a context file's map?) =="
files | grep -E '\.(md|txt|csv|tsv|json|ya?ml|log)$' | grep -vE '(^|/)[^/]*lock[^/]*$' | tr '\n' '\0' \
  | xargs -0 -r du -k 2>/dev/null | awk -F'\t' -v m="$BIG_KB" '$1>=m' | sort -rn \
  | while IFS=$'\t' read -r kb f; do
      b="${f##*/}"
      if tr '\n' '\0' < "$tmp" | xargs -0 grep -qsF "$b"; then r="on map"; else r="not on map"; fi
      printf '%s\t%sKB\t~%s tokens\t%s\n' "$f" "$kb" "$(tok "$f")" "$r"
    done | cap

echo "== handoffs and session notes outside the archive (folder, count, first, last) =="
HANDOFF='(^|/)[^/]*(handoff|session[-_ ]?notes?|wrap[-_ ]?up)[^/]*\.md$'
files | grep -iE "$HANDOFF" | grep -vE "(^|/)($ARCH_RE)/" | sort \
  | awk -F/ '{ d=(NF>1) ? substr($0, 1, length($0)-length($NF)-1) : "(root)"
      n[d]++; if (!(d in first)) first[d]=$NF; last[d]=$NF }
      END { for (d in n) printf "%s\t%d files\t%s\t%s\n", d, n[d], first[d], last[d] }' | sort | cap
# archived handoffs are history already: counted apart, never against the keep-N limit
n_arch="$(files | grep -iE "$HANDOFF" | grep -cE "(^|/)($ARCH_RE)/")"
[ "$n_arch" -gt 0 ] && echo "in the archive (history, not counted): $n_arch"

echo "== project skills, agents, commands (descriptions load every session) =="
# frontmatter description, including folded (>) and multi-line forms, quotes stripped
desc() {
  awk -v q="'" '
    /^---[ \t]*$/ { n++; if (n==2) exit; next }
    n==1 && /^description:/ { v=$0; sub(/^description:[ \t]*/, "", v); fold=(v ~ /^[>|][-+]?$/ || v==""); d=(fold ? "" : v); grab=1; next }
    n==1 && grab && fold && /^[ \t]+/ { s=$0; sub(/^[ \t]+/, "", s); d=d " " s; next }
    n==1 && grab { grab=0 }
    END { sub(/^ /, "", d); gsub("^[\"" q "]|[\"" q "]$", "", d); print d }' "$1"
}
for f in .claude/skills/*/SKILL.md .agents/skills/*/SKILL.md .gemini/skills/*/SKILL.md .claude/agents/*.md .claude/commands/*.md; do
  [ -f "$f" ] || continue
  if grep -q '^disable-model-invocation:[[:space:]]*true' "$f"; then printf '%s\tnot loaded (disable-model-invocation)\n' "$f"; continue; fi
  d="$(desc "$f")"
  printf '%s\t~%d tokens\n' "$f" $(( ${#d} / 4 ))
done | cap

echo "== MCP servers in .mcp.json =="
if [ ! -f .mcp.json ]; then echo "none"
elif ! command -v jq >/dev/null; then echo ".mcp.json present (no jq: read it to list servers)"
elif out="$(jq -r '(.mcpServers // {}) | keys[]' .mcp.json 2>/dev/null)"; then printf '%s\n' "$out" | sed '/^$/d' | cap
else echo "could not parse .mcp.json"; fi

echo "== paths outside the project (.mcp.json, .claude/settings*.json: file:line -> path under home, not in this project) =="
# a server or setting that writes to or reads from another project: on purpose, or left over from a move?
# home dot-folders (~/.claude, ~/.local...) are tool paths, not projects: skipped
for f in .mcp.json .claude/settings.json .claude/settings.local.json; do
  [ -f "$f" ] || continue
  # the home path, or ~/, $HOME/, ${HOME}/ as written (Claude Code expands ${VAR} in .mcp.json; a shell
  # command expands the rest), only at the start of a path: never the ~ inside a URL
  grep -noE "(^|[\"'[:space:]:=(])(~|\\\$\{?HOME\}?|$(esc "$HOME"))/[^\"'\`]*" "$f" 2>/dev/null | while IFS= read -r hit; do
    l="${hit%%:*}"; m="${hit#*:}"; m="${m#[\"\'[:space:]:=(]}"
    # a PATH-style list (a:b) holds several paths: check each
    printf '%s\n' "$m" | sed -E 's#:(~|\$\{?HOME\}?|/)#\n\1#g' | while IFS= read -r p; do
      p="${p%%[[:space:]]&&*}"; p="${p%%[[:space:]];*}"
      full="$p"
      # shellcheck disable=SC2088,SC2016  # a literal ~/ or $HOME the user wrote
      case "$p" in "~/"*) full="$HOME/${p#??}" ;; '${HOME}/'*) full="$HOME/${p#????????}" ;; '$HOME/'*) full="$HOME/${p#??????}" ;; esac
      case "$full" in "$HOME"/*) ;; *) continue ;; esac
      case "$full" in "$PWD"|"$PWD"/*) continue ;; "$HOME"/.*) continue ;; esac
      printf '%s:%s\t-> %s\n' "$f" "$l" "$p"
    done
  done
done | cap
