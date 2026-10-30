# RA Education Skills

Skills for AI coding agents, in the open [Agent Skills](https://agentskills.io) format.
One folder per skill; each works in Claude Code, OpenAI Codex, Gemini CLI and other agents that read `SKILL.md`.

| skill | what it does |
|---|---|
| [`cleanup`](cleanup/) | Audits a project folder and fixes only what you approve |

## cleanup

Projects get messy as you work on them with an agent: stale docs, leaked keys, giant
instruction files the agent reads every session, old files nobody dares to delete.
`cleanup` scans for that, writes one numbered report, and changes nothing until you
say which numbers to fix.

**Five checks (modes):**

| mode | looks for |
|---|---|
| security | keys and passwords in files or git history, `.gitignore` gaps, agent permissions that are too wide |
| bloat | big files, unused files, duplicates, old versions, junk |
| structure | files without an obvious home, dump folders, deep or crowded folders |
| context | heavy instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`), broken pointers, big docs with no "search it" note |
| archive | what in the archive is still worth keeping, sending to cold storage, or deleting |

**Safety rules it never breaks:**
- Report first. Nothing moves, changes or gets deleted without your OK on that number.
- Deletes, history rewrites and uploads always need their own OK.
- Every move is logged (`MOVES.tsv`) and checked for references first, so nothing breaks.
- It never prints a secret: file and line only, plus the first 4 characters.
- A fresh check verifies the result before it reports done.

### Install

Requirements: `git` and `bash` (macOS or Linux). Optional: `jq`, `gh`, `ffprobe`.

```bash
git clone https://github.com/dpadilha1/ra-education-skills.git ~/agent-skills

# Claude Code
mkdir -p ~/.claude/skills && ln -s ~/agent-skills/cleanup ~/.claude/skills/cleanup

# Codex and Gemini CLI (both read this shared folder)
mkdir -p ~/.agents/skills && ln -s ~/agent-skills/cleanup ~/.agents/skills/cleanup
```

Restart the agent after installing. Update later with `git -C ~/agent-skills pull`.

### Run it

Open the agent inside the project (a git repo) and ask for it by name:

| agent | full run | one mode |
|---|---|---|
| Claude Code | `/cleanup` | `/cleanup security` |
| Codex | `$cleanup` | `$cleanup security` |
| Gemini CLI | "run the cleanup skill" (it asks to activate it) | "run cleanup, security mode" |

It is meant to run only when you ask: Claude Code and Codex enforce that; Gemini CLI asks you before it activates any skill.

**First run:** it asks a few questions (where your archive lives, what to protect)
and saves the answers in `.claude/cleanup.md` (Claude Code) or `.agents/cleanup.md`
(other agents). Commit that file: later runs read it, remember your rulings and stay quiet
about what you already decided.

**Then:** read the report, answer with numbers ("do 1, 3, 5", "all high", "none").

### Agent support

| | Claude Code | Codex / Gemini CLI |
|---|---|---|
| security, bloat, structure, archive | full | full |
| context: general checks (pointers, big docs, handoffs) | full | full |
| context: exact loading rules, permission files, agent memory | full | reported as "not checked" (coming) |

`SKILL.md` carries two Claude Code-only frontmatter fields (`argument-hint`,
`disable-model-invocation`); other agents ignore them. Codex reads
`cleanup/agents/openai.yaml` for the same "only when asked" rule.

## How these skills are tested

See [TESTING.md](TESTING.md): real runs on real projects, a cold review of every change,
and a re-run that should come back quiet.

## License

TBD
