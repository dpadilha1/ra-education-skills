# Mode: security

Goal: find secrets that leaked or could leak, and settings that give the agent or
the repo more access than needed.

## Steps

1. **Run `<skill>/scripts/find_secrets.sh`.** It prints 6 sections, values masked:
   secrets in current files · secrets in git history · secret-type files tracked
   now · secret-type files ever committed · secret-type files not ignored ·
   .gitignore gaps.

2. **Judge each hit: real or fine.**
   - Fine: placeholders (`xxx`, `your-key-here`, `<TOKEN>`, `changeme`, test
     fixtures with fake values), env references (`process.env.X`), keys meant for the browser
     (Supabase anon/publishable key, Stripe `pk_`, Mercado Pago public key,
     Turnstile site key).
   - Real: anything else that looks like a working credential.
   - A JWT: the variable name is a hint, the token's own `role` claim decides.
     Read it without printing the token (this prints only the role):
     `sed -n '<line>p' <file> | grep -oE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' | head -1 | cut -d. -f2 | tr '_-' '/+' | awk '{ while (length($0)%4) $0=$0 "="; print }' | { base64 -d 2>/dev/null || base64 -D 2>/dev/null; } | grep -oE '"role" *: *"[a-z_]+"'`.
     `anon` → fine. `service_role`, `authenticated`, anything else, or
     nothing readable → real or **user decides**, even if the name says `anon`.
   - To see a hit in context, never print the raw line. Print it with
     everything after the first `=` or `:` cut to 4 characters, and every
     word of 6+ characters masked:
     `sed -n '<line>p' <file> | sed -E 's/([=:][[:space:]]*["'\'']?[^[:space:]"'\'']{0,4}).*/\1…/; s/([A-Za-z0-9_/+.-]{4})[A-Za-z0-9_/+=.-]{2,}/\1…/g'`
   - A history hit whose file still exists: the current-files section shows
     whether the secret is still in it.
   - A password for a real account is a secret, even inside a test.
   - Before asking the user, look for the answer yourself, and cite it:
     - what the lines around the hit point at. The mask above hides that,
       so print only hosts and environment words, never values:
       `awk -v l=<line> 'NR>=l-10 && NR<=l+10' <file> | sed -E 's#(https?://)[^/@[:space:]]*@#\1#g' | grep -oiE 'https?://[A-Za-z0-9.-]+|prod(uction)?|staging|sandbox|test|dev|localhost|127\.0\.0\.1' | sort -u`.
       A production host or project id there answers "is it real".
     - the project's own rules (its instruction files and the docs they point to for
       secrets): a rule like "a leaked key gets rotated" decides the fix.
       Propose that fix; don't ask whether to apply the rule.
   - Unsure → **user decides**, with what you found and what is still open.

3. **Repo visibility**, per repo, first answer wins:
   - `git remote` (names only: `-v` would print URLs, which can hold a token)
     empty → **local only**: nothing in it is public.
   - `gh repo view --json visibility -q .visibility` (a GitHub remote).
   - `gh` missing, offline or blocked by the sandbox → the `visibility` line
     in `cleanup.md`, said as "per cleanup.md".
   - none of these → "unknown", listed under "not checked".
   Public raises every real secret to high.

4. **Agent permissions (Claude Code).** Read `.claude/settings.json` and
   `.claude/settings.local.json`. Another agent's permission config
   (Codex `config.toml`, Gemini CLI `settings.json`) is not covered yet:
   list it under "not checked". Flag:
   - `defaultMode: bypassPermissions`
   - allow rules that cover destructive or outward actions: `Bash(*)`,
     `Bash(rm:*)`, `Bash(git push:*)`, `Bash(curl:*)`, deploy commands
   - allow rules with a literal key or token inside the command
   - allow rules for MCP tools that aren't read-only. Read-only tool names
     (the part after the last `__`) start with `get`, `list`, `show`,
     `search`, `read`, `describe`, `query`, `fetch`, `find`, `view` or
     `status`, or only report (`balance`); not sure from the name → read the
     tool's description; still unsure → user decides. Anything else (generate, upscale, create, edit, upload, import, send,
     publish, deploy, delete, exec, invoke) can spend credits or act outward
     with no prompt. A server-wide allow (`mcp__<server>` or
     `mcp__<server>__*`) counts as all its tools. Fix: move them to `ask`.
     Before calling an MCP allow stale, apply "Unknown is not stale"
     (`SKILL.md` Rules).
   - no deny rules for secret files, or rules that miss subfolders (only in
     a project that uses Claude Code: has a `.claude/` folder or a
     `CLAUDE.md`). Suggest
     one rule per real env file name the project has: `Read(.env)`,
     `Read(.env.local)`, `Read(.env.production)`, `Read(.dev.vars)`... Find
     the names (paths only, never contents) with
     `find . \( -name node_modules -o -name .git \) -prune -o -type f \( -name '.env*' -o -name '.dev.vars*' \) -print | grep -vE '\.(example|sample|template)$'`.
     Put the rules in the root `.claude/settings.json` deny list and in each
     nested repo's own: a session opened inside a nested repo doesn't load
     the parent's settings. A bare name (no `/`) matches at any depth under
     the folder Claude Code starts in; `Read(./.env)` covers that folder only.
     Never a glob like `.env*` or `apps/*/.env*`: it also blocks
     `.env.example`, and with the sandbox on, `git status` then fails on it.
     A deny rule blocks the file tools and the file commands Claude Code
     recognizes in Bash (`cat`, `head`, `tail`, `sed`, `tee`); with the
     sandbox on, also `grep -r` and scripts.
   - `settings.local.json` tracked by git

5. **Browser-exposed config.** Variables with public prefixes (`NEXT_PUBLIC_`,
   `VITE_`, `EXPO_PUBLIC_`, `PUBLIC_`) ship to every visitor. Flag any whose
   name says `SECRET`, `SERVICE_ROLE`, `PRIVATE` or `TOKEN`. Also flag secrets
   in plain deploy config (`wrangler.jsonc` `vars`, `vercel.json`,
   `netlify.toml`) instead of the platform's secret store.

6. **Personal data.** The script's last section lists e-mail addresses per
   file (count and domains, never the addresses), skipping generic inboxes
   (`info@`, `contact@`, `noreply@`...), test files, reserved domains
   (`example.com`, `.test`) and any address matching the `email exceptions`
   regex from `cleanup.md` (passed as the script's second argument). A person's work address (`name@company`) is personal data; a
   company inbox is not. Judge by the domains: the project's own people, a
   client list, a prospect list, a test fixture. Then grep the other patterns
   `cleanup.md` lists (ID numbers, phones...) and report a count per file,
   never the values.

## Severity

| level  | when |
|--------|------|
| high   | real secret in a tracked file or in history · secret-type file tracked · public repo with any real secret |
| medium | real secret in an unignored file · broad permissions · secret in plain deploy config · public-prefixed secret |
| low    | .gitignore gap with no file there yet · missing deny rule |
| medium | personal data of third parties (clients, prospects, staff) in a tracked file; low if the file is the project's own contact page or a test fixture |

## Fixes to propose

| finding | fix |
|---------|-----|
| real secret in a current file | 1. user rotates it at the provider · 2. value moves to env var / secret store · 3. file keeps only a reference |
| real secret in history only | user rotates it. History rewrite (`git filter-repo` + force push) is never the default: propose only for public repos, only after rotation |
| secret-type file tracked | `git rm --cached <file>`, add it to `.gitignore`, rotate what was in it |
| file not ignored / .gitignore gap | add the pattern to `.gitignore` |
| broad permission | narrow it to the exact command, or move it to `ask` |
| key inside a permission rule | delete the rule, rotate the key |
| public-prefixed secret | drop the prefix, use it server-side only, rotate |
| personal data in git | move the list out of git (ignore the file, or keep it where that data belongs: CRM, accounting). Already in history: say so; a rewrite follows the same rule as secrets. Own-company addresses: add them to `email exceptions` in `cleanup.md` |

**Rotate first, always.** Once a key has been in git or chat, assume it's
copied. Deleting it doesn't un-leak it; only a new key does.

## Report
Add findings to the shared report (mode = security), highest severity first.
