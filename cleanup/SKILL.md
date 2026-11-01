---
name: cleanup
description: Audit a project folder for bloat, messy structure, security leaks, heavy AI-agent context and a stale archive, then fix only what the user approves. Run it by name (/cleanup in Claude Code, $cleanup in Codex); alone it runs every check, with a mode it runs one (bloat, structure, security, context, archive). Use only when the user asks for it by name. Reports first; never deletes without an explicit OK.
license: MIT
compatibility: Agent Skills format (Claude Code, Codex, Gemini CLI and others). Needs git and bash; the scripts run on macOS and Linux.
argument-hint: "[help | bloat | structure | security | context | archive | archive all]"
disable-model-invocation: true
---

# Cleanup

Scan a project, report what's messy, fix only what the user approves.
Flow: **scan → report → approve → fix → verify → confirm.**

## How to use (show this when the user asks for `help`)
Print this block as is, then stop. Do not scan anything.

- **Run it:** ask for it by name inside the project (a git repo). Claude Code:
  `/cleanup`. Codex: `$cleanup`. Gemini CLI: "run the cleanup skill".
- **One mode** instead of all five: add the word. `security` (leaked keys,
  passwords, risky permissions), `bloat` (big and unused files), `structure`
  (messy folders), `context` (what bloats the agent's instructions),
  `archive` (old docs past their review age; `archive all` for every one).
- **First run:** it asks a few questions (where your archive lives, what to
  protect) and saves the answers in `.claude/cleanup.md` (`.agents/cleanup.md`
  on other agents). Commit that file; later runs read it and stay quiet about
  what you already decided.
- **Then:** read the numbered report and answer with numbers: "do 1, 3, 5",
  "all high", "none". Nothing changes until you do. Every move is logged and
  checked first; a fresh check verifies the result before it says done.
- It never prints a secret: file and line, plus the first 4 characters.

## 0. Any agent
This skill runs on any agent that reads Agent Skills (Claude Code, Codex,
Gemini CLI...). "The agent" below means you.
- **`<skill>`** = this skill's folder, the one holding this `SKILL.md`
  (Claude Code fills it in here: `${CLAUDE_SKILL_DIR}`; shown as a literal
  `${...}` → use the path this file was loaded from). Every `modes/`,
  `scripts/` and `templates/` path in this skill means that folder.
- **Settings file** (`cleanup.md` below): `.claude/cleanup.md` or
  `.agents/cleanup.md` in the project, whichever exists (both → the
  `.claude/` one, and say so). A first run writes it in `.claude/` on Claude
  Code and in `.agents/` on any other agent.
- **Agent-specific checks.** The context and security modes know Claude
  Code's files in detail (`CLAUDE.md`, `.claude/settings.json`, its auto
  memory). Their general checks (stale pointers, big docs, handoffs,
  secrets, paths outside the project) work on any agent. On another agent,
  run the Claude Code checks only for the Claude Code files the project
  has, and list the agent's own files (its instruction file such as
  `AGENTS.md` or `GEMINI.md`, its permissions config, its memory) under
  "not checked".
- **Instruction files** = `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`: whichever
  the project has.

## 1. Pre-flight
1. Project root = the git root of the working directory. No git → stop and ask.
   If the folder holds git repos below it but none at the top, offer these
   three, recommending C:
   - A. Run on each repo, one after the other (skips the loose files around them).
   - B. Like A, and name the loose files around the repos. The scripts read
     git, so those files are not scanned: say so in the report.
   - C. `git init` the top folder, local only, no remote; the nested repos go
     in its `.gitignore`. No commit until security and bloat have scanned, so
     no secret or big file enters history; show the first commit's file list
     before making it. A remote is a separate decision.

   Nested repos: list each one's current branch. Commits land on that branch,
   prefixed `cleanup(...)`. Never create or switch branches (a dev server or
   unfinished work may depend on the checkout) unless the user asks.
2. Read `cleanup.md` (this project's settings, section 0). Missing → fill
   `templates/project.md` with what you can see without a scan (archive folder,
   `.gitignore`, deploy config), ask the user the rest, run the memory check
   below, then show the filled file and write it on their OK. For the archive,
   list every archive folder the project already has
   (`find . \( -name node_modules -o -name .git \) -prune -o -type d -iname '*archive*' -print`):
   one per area (`docs/archive/`, `app/docs/archive/`) means the setting
   lists them all.
   Present → compare it with `templates/project.md`: every `- name:` line
   whose name is plain text (not a `<...>` placeholder, not under
   `## Rulings`) that the file lacks is a setting added since the file was
   written. Ask the user for each one now (blank = the default, or "unknown"
   where there is none), and add the answers on their OK. They are committed
   with the run's rulings (section 4.7), even if no fix is approved.
   No dated line under `## Rulings` (section missing, empty, or only `<...>`
   placeholders), or no file: an earlier run may have saved its answers in
   the agent's memory instead. Check before showing or writing the file,
   so imported rulings get the same OK.
   - Another agent: look where it keeps memory if you know; else list
     "memory: not checked". Never read Claude Code's memory folder from
     another agent.
   - Claude Code: if a `MEMORY.md` index is in your context, start there.
     Then search the project's memory folder (`<root>`
     with no trailing slash):
     `grep -rilE 'cleanup|ruling' "$HOME/.claude/projects/$(printf '%s' "<root>" | sed 's/[^A-Za-z0-9]/-/g')/memory/"`.
     Folder not there → `ls ~/.claude/projects/ | grep -iF '<last folder name of root, spaces as ->'`;
     nothing → say "no memory found" and go on. With nested repos, also
     check the parent folder's memory: an earlier run may have started there.
     Show what you find; the lines the user confirms go under `## Rulings`,
     dated today and citing the source: `<today>: <ruling> (from memory,
     <its date, or the file's modified date (`date -r <file> +%F`) marked
     "approx.">)`. Don't edit the memory files (Stay inside the project): list
     each one's path in section 6 (Confirm), so the user can trim it (it keeps
     loading every session).
3. **Reminders.** Rulings marked `(re-check)`, or saying to re-check next run,
   that no newer ruling cites ("per <its date>") go in the report's
   Reminders section: only the newest line on a topic counts. Ask about each
   once; the answer is a new ruling, dated today. Still open ("not yet") →
   the new line keeps `(re-check)`.
   A ruling that settles a finding (keep it, skip it, do it
   later) means that finding goes under Clean, citing the ruling's date (an
   imported line: the date it was written into `cleanup.md`):
   never judge it again, unless the ruling is marked `(re-check)`.
4. **Trail rules.** Check the project's instruction files for what every session
   must leave behind (a journal entry, a decisions-log row). Those entries
   are part of the fix: the report lists them as `T1`, `T2`... with their
   exact wording, so the user approves them like numbers. They are new rows
   (logs stay append-only). A count inside one (files archived, handoffs left)
   is a proposal: when a fix lands differently, write the real count and list
   the entry under "changed from plan" with the wording as written. A trail file outside the project root is
   reported, not written, unless the user approves that path. On a run where
   the user approves nothing, write only the trail entries they approved.
5. Run `git status --short`. Uncommitted work is fine for scanning. Fixes wait
   for the checkpoint in section 4.
6. **Another session?** List files changed in the last 15 minutes
   (`find "<root>" -type f -mmin -15 -not -path '*/.git/*'`). Any hit this run didn't
   write → warn the user another session may be working here; ask them to
   pause it, or go on and leave its files alone. Check again before the
   checkpoint commit.

## 2. Route
The argument is the mode word the user gave with the skill's name
(`/cleanup security`, `$cleanup security`, "run cleanup, security mode").
No mode word → (none).

| argument     | read                |
|--------------|---------------------|
| security     | `modes/security.md` |
| bloat        | `modes/bloat.md`    |
| structure    | `modes/structure.md`|
| context      | `modes/context.md`  |
| archive      | `modes/archive.md` (folders past the review age) |
| archive all  | `modes/archive.md` (every archive folder) |
| help         | the "How to use" block above, then stop |
| (none)       | all five, in this order: security, bloat, structure, context, archive |

- Read one mode at a time: finish its scan, keep its findings, then open the next.
- Never open a mode the run doesn't need.
- `<skill>` (section 0) in a command: replace it with the real path, in
  quotes in case it has spaces (a bare `scripts/` would hit the project's
  own folder).
- Run the scripts, don't read them. They print only findings.
- **Nested repos** (pre-flight found any): run each mode's scripts once per
  repo, with that repo as `<root>`: the top folder's repo if there is one
  (option C), then every nested repo. A parent's git ignores them, so a scan
  of the parent never sees their files or history. Prefix each nested repo's
  findings with its path.
- A section ending in `... N more` was cut short: re-run that script with
  `CLEANUP_MAX=<a bigger number>` in front and filter with `grep`. Never copy
  or edit a script to get around a limit.
- Pass them the settings from `cleanup.md`. Globs there become extended
  regexes for the scripts (`clients/*/raw/` → `clients/[^/]+/raw/`).
- **Several archive folders** (one per area, listed in `cleanup.md`): pass
  them all as one argument, comma-separated (`docs/archive,app/docs/archive`).
  Never run a script once per archive: each run would count the other
  archives as live files. With nested repos, each repo's run gets only the
  archives inside it, written relative to that repo's root; the parent's
  run leaves them out.

## 3. Report
- Fill `templates/report.md`: one findings table, numbered across all modes
  (1, 2, 3...) so the user can answer "do 1, 3, 5". A finding that needs an
  answer goes in the template's "User decides" table instead, never in both;
  its number continues the same sequence.
- Every finding states its evidence and its proposed fix.
- Numbers (counts, sizes, lines) come from the scan output: quote them, don't
  recount by hand. If a later step finds a different number, say which is
  right and why.
- A hit you'd advise skipping is not a finding: it goes under Clean, one line
  with the reason. "I'd skip" in the recommendation is for findings with a
  real trade-off.
- A Clean line that took weighing ("6 files, 12 references, little gain"),
  not a plain "nothing found", is a verdict the next run could flip. Mark it
  `(ruling?)`; the Recommendation offers to save those as rulings.
- Before showing it, check the Clean list against the findings: nothing can be
  both clean and a finding.
- The report ends with its Recommendation. Add nothing after it: no second
  summary, no repeated question. Then stop and wait. No changes in this step.

## 4. Fix (only the numbers the user approved)
An answer that still holds a `<placeholder>`, offers two options, or doesn't
answer the question asked is no answer. Ask again for that number only,
quoting the question; never pick for the user. Go on with the clear ones.
Declined means the user said no to that number ("skip 6", "not 4"). A
number they didn't mention is not declined: it stays open, nothing is saved.

1. **Checkpoint first.** If there is uncommitted work, ask before committing it.
   Apply approved `.gitignore` fixes before the checkpoint. Stage only tracked
   changes minus the settings file and every path a finding in this run
   flagged (`git add -u -- . ':!<settings file>' ':!<flagged path>' ...`),
   or a list the user approves.
   Check `git diff --cached --name-only` before committing.
   Message: `cleanup: checkpoint before <date> run`.
2. Every move is logged in a `MOVES.tsv` (format: `templates/MOVES.tsv`).
   Archive moves: files go to `<archive>/YYYY-MM-DD-<topic>/`, logged there.
   With several archive folders, a file goes to the one for its area: the
   archive whose path shares the most leading folders with the file
   (`app/x.zip` → `app/docs/archive/`, not `docs/archive/`); a tie → the
   first one listed. A file git ignores stays out of git: before moving it
   into a tracked archive, run `git check-ignore` on the destination path;
   not ignored there → ask the user where it goes. Exception: when a
   Retention or Protect rule in `cleanup.md` keeps a file in its own folder
   (e.g. client files stay in the client's folder), it goes to
   `<that folder>/<archive name>/YYYY-MM-DD-<topic>/`, where `<archive name>`
   is the last folder name of the archive its area would use.
   Reorg moves: files go to their new live place, logged in
   `<archive>/YYYY-MM-DD-reorg/MOVES.tsv` (several archives: the first one
   listed).
   An inventory of a folder with no log lists its files, never the
   `MOVES.tsv` or `LEDGER.tsv` being written.
   An instruction file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) moving into
   an archive is renamed `<NAME>.archived.md` in the same move: under its
   own name it keeps loading whenever an agent works in that folder. Its
   reference check greps the full path only (the bare name hits every
   project); hits in logs (`MOVES.tsv`, `LEDGER.tsv`, journals, decision
   logs) are history and stay as they are. A rename in a folder with no
   `MOVES.tsv` creates one.
3. **Reference check before every move.** Grep the full path, the file name
   and the name without extension. Judge each hit (relative imports like
   `../img/logo.png` count). If anything live points to the file, update that
   reference in the same step, or drop the move and say why. A comment in
   the code or a current doc that keeps the file on purpose ("parked",
   "disabled for now", "lives in X so it can come back") is a live
   reference: drop the move and list it under skipped in section 6
   (Confirm), citing that `file:line`.
4. **Back up config before editing it**, keeping its path:
   `<archive>/YYYY-MM-DD-config/<original path>`, logged in that folder's
   `MOVES.tsv`. A file that git or an agent acts on by its name (e.g.
   `.gitignore`, `.gitattributes`, `CLAUDE.md`, `CLAUDE.local.md`,
   `AGENTS.md`, `GEMINI.md`, `.mcp.json`, anything under `.claude/`,
   `.agents/`, `.codex/` or `.gemini/`) gets `.backup` added
   to its name (`.gitignore.backup`): under its own name a `.gitignore`
   starts ignoring files inside the archive, and an instruction file
   starts loading. (A backup is a copy; a context file *moved* into the archive is
   renamed `*.archived.md` instead, step 2.) A file that
   holds secrets is backed up only if the archive is ignored by git; otherwise ask the user where to keep the backup, or skip
   that edit. Then run `git check-ignore` on the backup: an ignore rule (the
   project's or the user's global one) can keep it out of git. Say in section 6 (Confirm)
   whether each backup is in git or on disk only.
5. **Do each fix as approved.** A detail that must change (a date, a path, a
   name), small and clearly better → do it and list it under "Changed from
   plan" in section 6 (Confirm). Anything bigger → ask first.
6. **Save the rulings.** The user's answers to "user decides" items, the
   `R1`, `R2`... verdicts they approved, every finding they declined
   (`<today>: <finding, by path> stays as it is, declined by the user
   (<their reason, if they gave one>)`; a security finding adds
   `(re-check)`), and any change they asked for go
   into `cleanup.md` under `## Rulings`, one dated line each, so the
   next run doesn't ask again. Every new line is dated the day it's written,
   even when it renews or answers an older ruling: cite the old date inside
   it (`<today>: key still not rotated, per <old date> (re-check)`).
   Approved `T` entries go in their trail files. A line that restates
   the user's answer is written without asking and shown in section 6 (Confirm). A line
   that adds anything they didn't say (wider scope, a new rule, a guess about
   why) is shown first and waits for their OK.
7. One commit per mode: `cleanup(<mode>): <what changed>`. Rulings get their
   own, with any settings added at pre-flight and the trail entries the
   project's rules ask for: `cleanup: rulings <date>`.
   It is made even when the user approved no fix. Before every commit, check
   `git diff --cached --name-only`: only that mode's files. A `git rm` or
   `git mv` stages at once, so an earlier fix can ride along unseen.

## 5. Verify
A fresh subagent checks the result against the approved list. It changes
nothing except the output of tests and builds it runs. (No subagents on this
agent, or the user declines one → offer the user this list to check in a
fresh session, and say "not verified" until then.) If the project's
instruction files require asking before a subagent, ask before launching it
and wait for the OK: the check is part of the run, not an extra. It checks:
- every move landed and is logged in `MOVES.tsv`
- no live reference broke
- nothing outside the approved list changed
- tests or build still pass, if the project has them
Its findings are reported to the user. Fixing them needs the user's OK.

## 6. Confirm
First re-run `git status --short` and `git log --oneline -10`: report the repo
as it is now, not as it was at scan time (another session may have committed).
Tell the user: what changed (by number), commit hashes, `MOVES.tsv` paths,
changed from plan, what was verified and what wasn't, anything skipped and
why, memory files rulings were imported from (outside the project; the user
trims them). Offer a short handoff note in the chat (what changed, what's still open,
where to pick up next time). The rulings already live in `cleanup.md`: don't
save the run to the agent's memory unless the user asks.

## Rules (every mode)
- **Report first.** Nothing is moved, edited or deleted before the user approves
  that finding's number.
- **Some actions always need their own OK**, even inside "do all" or "all high":
  deletes, history rewrites, force pushes, uploads (cold storage, secret stores).
- **Never delete** outside `archive` mode. There, Delete is a verdict that needs
  the user's OK per item. A file whose current contents are committed
  can be restored from history (before the delete is committed,
  `git --literal-pathspecs checkout HEAD -- "<path>"`; after,
  `git --literal-pathspecs checkout "$(git --literal-pathspecs rev-list -n1 HEAD -- "<path>")^" -- "<path>"`). Any other
  file is gone for good: untracked, newly staged, or edited since the last
  commit (those edits are lost; commit them first if they matter), even
  inside a tracked archive. Say which, per file; the check is in
  `modes/archive.md`. Ask the same way either way.
  Only exception: removing an empty folder (nothing inside to lose), logged in
  `MOVES.tsv`.
- **Evidence or no finding.** Every finding names its proof: `0 references (grep)`,
  `same hash as assets/logo.png`, `superseded by v2 (exists)`,
  `rebuilt by the build command`. No proof → mark it **user decides**.
- **Unknown is not stale.** Never call a tool, connector or path old, unused
  or gone without proof. In Claude Code, `mcp__claude_ai_<Name>__*` tools come from the
  user's claude.ai account and `mcp__plugin_*` tools from plugins: neither
  appears in `.mcp.json`. In this session's tools → live. Not there → "status
  unknown", **user decides**: a connector can be off for one session or one
  app, so missing here is not proof it's gone.
- **Protected paths** listed in `cleanup.md` are reported, never touched.
- **Logs are history, the state doc is current.** `MOVES.tsv`, `LEDGER.tsv`,
  journals and decision logs get new rows, never edits to old ones: a rename
  or a correction is a new row. Only a row this run wrote can be fixed. The
  state doc named in `cleanup.md` (handoff, status) is not a log: it says what
  is true now, so a line it holds that this run made stale gets replaced.
- **Stay inside the project.** Edit only files under the project root.
  Anything outside it (agent memory, global settings, repos elsewhere) is
  reported, not edited, unless the user approves that path.
- **Never print a secret.** Show `file:line` and the first 4 characters only.
- **Never open a protected or secret file to test something.** Not one byte,
  not even to prove a deny rule works. Check the rule in the settings, check
  ignores with `git check-ignore`, and use a template (`.env.example`) when a
  real file is needed. A read the user or a permission check blocked is not
  retried another way.
- **Live things get a warning.** Anything deployed (site files, server config)
  gets a note saying what the next deploy will change.
- **No way, no workaround.** If the skill gives no way to do something (a
  limit, a block, a missing setting), list it under "not checked"; ask only
  when it blocks an approved fix. Never invent a step around it.
- **Stay cheap.** Scripts do the scanning; the agent reads only what a finding needs.
  Never read a file over 50KB whole: use `head`, `grep` or the script output.
  Don't re-read files already in context (the global instruction file is).
