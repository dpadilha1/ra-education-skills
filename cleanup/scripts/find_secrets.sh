#!/usr/bin/env bash
# find_secrets.sh: scan a git repo for leaked secrets. Prints findings only, values masked.
# Usage: find_secrets.sh [repo_root] [email_skip_regex]
#   repo_root: default current git root
#   email_skip_regex: extended regex; addresses matching it (lower-cased) are not reported
#                     in the e-mail section, e.g. '@mycompany\.com$' for the project's own inboxes
set -u

# show non-ASCII paths as they are (git quotes them by default)
git() { command git -c core.quotepath=off "$@"; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
email_skip="${2:-}"
{ [ -n "$root" ] && cd "$root"; } || { echo "ERROR: not a git repo"; exit 1; }

MAX="${CLEANUP_MAX:-50}"   # lines per section; CLEANUP_MAX=<n> shows more
case "$MAX" in ""|*[!0-9]*) MAX=50 ;; esac
tmp="$(mktemp "${TMPDIR:-/tmp}/secrets.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# name<TAB>extended regex (more specific patterns first: a value is reported once, under the first match)
# (a function, not $(cat <<EOF): bash 3.2 misreads the quote in the generic pattern inside $(...))
patterns() { cat <<'EOF'
private-key	-----BEGIN [A-Z ]*PRIVATE KEY-----
aws-key	AKIA[0-9A-Z]{16}
github-token	(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,})
anthropic-key	sk-ant-[A-Za-z0-9_-]{20,}
openai-key	sk-(proj-)?[A-Za-z0-9_-]{32,}
stripe-live-key	(sk|rk)_live_[A-Za-z0-9]{20,}
slack-token	xox[abprs]-[A-Za-z0-9-]{10,}
google-api-key	AIza[0-9A-Za-z_-]{35}
resend-key	(^|[^A-Za-z0-9_])re_[A-Za-z0-9_]{20,}
elevenlabs-key	sk_[a-f0-9]{48}
mercadopago-token	(APP_USR|TEST)-[0-9]{6,}-[0-9]{6}-[a-f0-9]{32}-[0-9]{6,}
telegram-bot-token	[0-9]{8,10}:AA[A-Za-z0-9_-]{33}
jwt	eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
supabase-secret-key	sb_secret_[A-Za-z0-9_-]{20,}
bearer-token	Bearer [A-Za-z0-9._~+/-]{20,}=*
generic-assignment	((api[_-]?key|secret|token|passw(or)?d|auth[_-]?token)[A-Za-z0-9_]*["']?[ 	]*[:=][ 	]*["']?[A-Za-z0-9_/+=.-]{16,}|passw(or)?d[A-Za-z0-9_]*["']?[ 	]*[:=][ 	]*["'][^"' 	]{8,}["'])
EOF
}

SECRET_FILES='(^|/)(\.env(\.[^/]*)?|\.dev\.vars[^/]*|[^/]*\.(pem|key|p12|pfx)|id_(rsa|ed25519)[^/]*|credentials\.json|service[-_]?account[^/]*\.json|\.npmrc|settings\.local\.json)$'
SAFE_FILES='\.(example|sample|template)$'

# keep a section short: first $MAX lines, then a count
cap() { awk -v max="$MAX" 'NR<=max{print} END{if(NR>max) printf "... %d more\n", NR-max; if(NR==0) print "none"}'; }

# where:line:match  ->  name<TAB>where:line<TAB>first 4 chars...(length)<TAB>key name (generic only)
# drops env references and obvious placeholders
mask() {
  awk -v n="$1" -v q="'" 'BEGIN { OFS="\t" } {
    i=index($0, ":"); f=substr($0, 1, i-1); r=substr($0, i+1)
    j=index(r, ":"); l=substr(r, 1, j-1); m=substr(r, j+1); k=""
    if (n=="resend-key") sub(/^[^r]/, "", m)
    if (n=="bearer-token") sub(/^Bearer /, "", m)
    if (n=="generic-assignment" && match(m, "[:=][ \t\"" q "]*")) {
      k=substr(m, 1, RSTART-1); m=substr(m, RSTART+RLENGTH)
      sub("[ \t\"" q "]+$", "", k)
      # names that hold a word about secrets, not a secret (tokenizer, passwordField, tokenCount...)
      if (tolower(k) ~ /^token(s|i[sz]e|i[sz]er|count|length|type)|(field|label|placeholder|input|hint|prompt|count|length|type|name)$/) next
      sub("[\"" q "]+$", "", m)   # closing quote of a quoted value
      k="key " k
    }
    v=tolower(m)
    if (v ~ /^(process\.env|import\.meta\.env|os\.environ|getenv)/) next
    if (v ~ /your[_-]|example|placeholder|changeme|xxxx|replace[_-]?me|[_-]here$/) next
    if (n=="generic-assignment" && (v ~ /^\$\{?[a-z_][a-z0-9_]*\}?$/ || v ~ /^\$\{[^}]*\}$/ || v ~ /^(\$\(|\{\{|%[({]|<[^>]*>$|\*+$)/ || v ~ /^(passw|secret|string|required|undefined|null|true|false|none|empty|hidden)[a-z_]*$/)) next   # a reference, a type or a label, not a value
    print n, f ":" l, substr(m, 1, 4) "...(" length(m) " chars)", k, m   # 5th field: the full value, only so two keys with one prefix stay two findings; cut -f1-4 drops it before printing
  }'
}

echo "== secrets in current files (tracked + untracked not ignored + settings.local.json) =="
patterns | while IFS=$'\t' read -r name re; do
  flags="-nIoE"; [ "$name" = generic-assignment ] && flags="-nIoiE"
  {
    git grep $flags --untracked -e "$re" -- . ':!*.lock' ':!package-lock.json' ':!pnpm-lock.yaml' 2>/dev/null
    [ -f .claude/settings.local.json ] && grep -H $flags -e "$re" .claude/settings.local.json
  } | mask "$name"
done | awk -F'\t' '!seen[$2 FS $3 FS $4 FS $5]++' | cut -f1-4 | cap

echo "== secrets in git history (pattern, commit:file, masked value, key, file now) =="
# one line per added line in any commit: commit:file:content
# normal commits first, then merges (-m diffs each parent, which the default log skips)
{ git log --all -p --no-color --no-ext-diff --format='@@COMMIT %h' 2>/dev/null
  git log --all --merges -p -m --no-color --no-ext-diff --format='@@COMMIT %h' 2>/dev/null; } \
  | awk '/^@@COMMIT / { c=$2; next }
         /^\+\+\+ / { f=$0; sub(/^\+\+\+ "?b\//, "", f); sub(/\t$/, "", f); sub(/"$/, "", f); next }
         /^\+/ { print c ":" f ":" substr($0, 2) }' > "$tmp"
patterns | while IFS=$'\t' read -r name re; do
  flags="-E"; [ "$name" = generic-assignment ] && flags="-iE"
  grep $flags -e "$re" "$tmp" | while IFS= read -r line; do
    c="${line%%:*}"; rest="${line#*:}"; f="${rest%%:*}"; body="${rest#*:}"
    printf '%s\n' "$body" | grep -o $flags -e "$re" | while IFS= read -r m; do printf '%s:%s:%s\n' "$c" "$f" "$m"; done
  done | mask "$name"
done | awk -F'\t' '{ f=$2; sub(/^[^:]*:/, "", f); key=$1 FS f FS $3 FS $4 FS $5; if (!seen[key]++) print }' | cut -f1-4 \
  | while IFS=$'\t' read -r n cf v k; do
  f="${cf#*:}"; if [ -e "$f" ]; then s="file exists (current-files section says if the secret is still in it)"; else s="file deleted"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$cf" "$v" "$k" "$s"
done | sort | cap

echo "== secret-type files tracked now =="
git ls-files | grep -E "$SECRET_FILES" | grep -vE "$SAFE_FILES" | cap

echo "== secret-type files ever committed (still in history even if deleted) =="
git log --all --diff-filter=A --name-only --format= | grep -E "$SECRET_FILES" | grep -vE "$SAFE_FILES" | sort -u | cap

echo "== secret-type files not ignored (the next git add would commit them) =="
git ls-files --others --exclude-standard | grep -E "$SECRET_FILES" | grep -vE "$SAFE_FILES" | cap

echo "== .gitignore gaps (these names would NOT be ignored) =="
for p in .env .env.local .env.production .dev.vars .claude/settings.local.json secrets.json key.pem id_rsa; do
  git check-ignore -q --no-index "$p" || echo "$p"
done | cap

echo "== personal data: e-mail addresses per file (count, domains only; generic inboxes, test files and reserved domains skipped) =="
# a person's work address (name@company) is personal data; info@, contact@... are not
EMAIL='[A-Za-z0-9._%+:/-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'   # ':' and '/' let a URL credential (user:pass@host) be seen and dropped
GENERIC_INBOX='^(info|contact|contacto|hello|hola|hi|admin|administrator|support|soporte|suporte|help|ayuda|sales|ventas|vendas|noreply|no-reply|no_reply|donotreply|do-not-reply|team|office|billing|facturacion|invoices|accounts|finance|press|prensa|jobs|careers|hr|rrhh|newsletter|marketing|webmaster|postmaster|hostmaster|abuse|security|privacy|legal|dev|developers?|test|testing|example|mail|email|notifications?|alerts?|bot|git|root|user|me|you|name|someone|user[0-9]*)@'
RESERVED_DOMAIN='(@(example\.(com|org|net)|localhost|company\.com|yourcompany\.com|acme\.com|foo\.com|bar\.com)|\.(test|example|invalid|localhost|local|internal)|sentry\.io)$'
TEST_FILES='(^|/)(tests?|__tests__|__mocks__|fixtures|spec)/|\.(test|spec|stories)\.[a-z]+$|(^|/)[^/]*\.example$'
git grep -nIoE --untracked -e "$EMAIL" -- . ':!*.lock' ':!package-lock.json' ':!pnpm-lock.yaml' 2>/dev/null \
  | awk -v g="$GENERIC_INBOX" -v x="$RESERVED_DOMAIN" -v t="$TEST_FILES" -v s="$email_skip" 'BEGIN { OFS="\t" } {
      f=$0; sub(/:[0-9]+:.*$/, "", f); if (f ~ t) next
      m=$0; sub(/^[^:]*:[0-9]+:/, "", m); m=tolower(m); sub(/^mailto:/, "", m)
      if (m ~ /^[^@]*[:\/]/) next                       # user:pass@host or scheme://x@host: a URL, not an address
      if (m ~ g || m ~ x || (s != "" && m ~ s)) next
      d=m; sub(/^[^@]*@/, "", d); print f, d }' \
  | sort | uniq -c \
  | awk '{ f=$2; d=$3; n[f]+=$1; k[f]++
           if (k[f] <= 5) doms[f]=(doms[f]=="" ? d : doms[f] ", " d) }
         END { for (f in n) printf "%s\t%d address(es)\t%s%s\n", f, n[f], doms[f], (k[f] > 5 ? ", ..." : "") }' \
  | sort -t$'\t' -k2,2nr | cap
