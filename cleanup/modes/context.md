# Mode: context

Goal: the agent loads only what it needs. The always-loaded part stays small,
every pointer works, and big docs get searched, never read whole.

## How Claude Code loads context

| what | when it loads |
|------|---------------|
| `~/.claude/CLAUDE.md`, `CLAUDE.md` / `.claude/CLAUDE.md` / `CLAUDE.local.md` in the project root and its parent folders | every session |
| files pulled in with `@path` inside those (not inside code) | every session (an import is not a pointer) |
| rules in `.claude/rules/` and `~/.claude/rules/` (subfolders too) without `paths:` | every session |
| auto memory `MEMORY.md` (first 200 lines or 25KB) | every session |
| skill and agent descriptions (not skills with `disable-model-invocation: true`) | every session |
| `CLAUDE.md` in a subfolder | when Claude works in that folder |
| rules with `paths:` | when Claude touches a matching file |
| a doc named in plain text (`docs/x.md`) | only when Claude decides to read it |
| `AGENTS.md` | every session only when no `CLAUDE.md` file exists in the project or its parents; otherwise only if a `CLAUDE.md` imports it |

If Claude Code's loading rules change, trust its current docs over this table.
Other agents load their own instruction file (Codex: `AGENTS.md`; Gemini
CLI: `GEMINI.md`) by rules this table doesn't cover. The script lists those
files in their own section and checks them for repeated lines, stale
pointers and big docs on their map, like the Claude Code files. Its "loaded
every session" section (with `~/.claude/CLAUDE.md` and auto memory) is
Claude Code's view: on another agent, report the budget for that agent's
file from its line count, and put its exact loading rules, global file and
memory under "not checked".

Settings from `cleanup.md`: always-loaded budget (default: project files
under 200 lines in total), big-doc threshold (default 25KB), handoffs to keep
per folder (default 3).

## Steps

1. **Run `<skill>/scripts/find_context.sh <root> <big_doc_kb> <archive>`** (several
   archive folders → one comma-separated argument). Sections: loaded
   every session · loaded on demand · lines repeated between context files ·
   stale pointers · big text docs · handoffs piling up · project skills,
   agents and commands · MCP servers · paths outside the project.

2. **Judge each hit.**
   - **Always-loaded weight:** `CLAUDE.md` holds rules and a map, not state
     or detail. State (current status, counts, dates) goes to the project's
     state doc. Detail goes to the doc for that area, linked from the map.
     Rules for one area go to a subfolder `CLAUDE.md` or a rule with `paths:`.
   - **`@` imports:** each one loads every session. Keep only what every
     session needs; turn the rest into a plain mention on the map.
   - **Repeated rules:** a rule already in the global file doesn't need to be
     in the project file. The script catches exact repeats only. Also compare
     by meaning (the global file is already in your context: don't read it
     again), and show the work: a table with each project rule, the closest
     global rule, and a verdict (same · adds detail · different). No table →
     the check didn't run; never mark it clean without one.
     - Before calling anything repeated, ask the user: does anyone or anything
       use this project without the global file (teammates, cloud sessions,
       scheduled agents)? Yes → user decides per rule.
     - "Adds detail" → trim, don't delete: keep every clause the global file
       doesn't say. Show the trimmed text before applying it.
     - Same check between a parent folder's `CLAUDE.md` and a nested repo's:
       the nested repo is often opened on its own (a clone, a cloud session,
       a PR review) where the parent file doesn't exist. Rules that repo
       needs stay in its own file; the parent can point to it instead.
   - **The map:** every row points to a doc that exists, and every doc people
     work from is on the map. Docs nobody works from (research, client notes)
     can stay off it: an agent finds them by searching.
   - **Stale pointer:** find where the file went (`git log --follow`,
     `git log --diff-filter=D -- <path>`, the archive's `MOVES.tsv`), then
     propose the new path or removing the line.
   - **Big docs:** a big doc on the map with no "search it, never read it
     whole" line → add that line. Logs that only grow (journals, changelogs)
     → split by period: the current period stays live, older periods move to
     `<doc>/YYYY-MM.md` or the archive, with a one-line index. A file holding
     several months is named `YYYY-MM-to-YYYY-MM.md`, never two dates joined
     (`2026-08-09.md` reads as 9 August). Never summarize content away without
     the user's OK: a summary loses detail.
   - **Handoffs:** keep the newest N per folder (the `cleanup.md` setting);
     older ones are history → archive. A handoff whose open questions no later
     one closed → user decides. Handoffs already in an archive are history:
     the script counts them apart, never against N, never a finding.
   - **`AGENTS.md` next to a `CLAUDE.md`:** Claude Code skips it. Import it
     from `CLAUDE.md`, or leave it if it's meant for other tools.
   - **Descriptions** of project skills and agents over ~100 tokens → shorten.
   - **MCP servers** the project never uses → remove them from `.mcp.json`.
   - **Paths outside the project** (`.mcp.json` or `.claude/settings*.json`
     naming a folder under the home folder but outside this project, such
     as a server's output folder) → **user decides**: it can be on purpose
     (a shared folder) or left over from a move. Say which project the path
     belongs to and what writes or reads there. The answer is a ruling.
   - **Huge files an agent never needs** (lockfiles, data dumps, minified
     bundles) → on Claude Code, suggest a deny rule in `.claude/settings.json`
     (`Read(./path)`), so its file tools skip them. A Read deny also
     blocks Edit and Write on that path, so only for files nobody changes
     through an agent. A data file people do edit (seed data, a catalogue) gets
     a "search it, never read it whole" line on the map instead.
   - **A `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, `AGENTS.md` or
     `GEMINI.md` inside the archive** (tagged `IN ARCHIVE`) still loads when an agent works
     in that folder, with rules that may be overturned → rename it
     `*.archived.md` and log the rename in that folder's `MOVES.tsv`.

3. **Every finding states its saving:** `~N tokens every session` or
   `~N tokens each time it's read`.

## Priority

| level  | when |
|--------|------|
| high   | always-loaded project files over budget · `@` import of a big file · stale pointer in an always-loaded file · big doc on the map without a "search it" line |
| medium | repeated rules · working docs off the map · handoffs piling up · growing logs over the threshold · `CLAUDE.md` in the archive |
| low    | long descriptions · unused MCP servers · `AGENTS.md` skipped · deny-rule suggestions |

## Fixes to propose

| finding | fix |
|---------|-----|
| heavy `CLAUDE.md` | move state to the state doc, detail to area docs, area rules to a subfolder `CLAUDE.md` or a `paths:` rule; leave a map row |
| big `@` import | replace it with a plain mention on the map |
| repeated rule | same → delete it from the project file · adds detail → trim it to the part the global file doesn't say |
| stale pointer | point it to the new path, or remove the line |
| working doc off the map | add a map row |
| big doc without a search line | add "search it, never read it whole" next to its map row |
| growing log | split by period, older periods to `<doc>/` or the archive, add an index line |
| old handoffs | archive all but the newest N per folder |
| long description | shorten it to one line saying when to use it |
| unused MCP server | remove it from `.mcp.json` |
| huge file an agent never needs | add a `Read(./path)` deny rule (Claude Code; never on a file people edit through an agent) |
| big data file people edit | add "search it, never read it whole" next to its map row |
| `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` in the archive | rename it `*.archived.md`, log it in `MOVES.tsv` |

## Report
Add findings to the shared report (mode = context), biggest per-session saving first.
