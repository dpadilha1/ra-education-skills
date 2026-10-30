# Cleanup settings: <project>
<!-- Read by the cleanup skill. Lives in this project only.
     First run: fill what you can see without a scan (archive folder,
     .gitignore, deploy config), ask the user only the rest, show the file
     before writing it. Blank = default.
     Paths may be globs (clients/*/raw/); the skill turns them into regexes
     for the scripts.
     Archive folder: one, or several separated by commas when each area keeps
     its own (docs/archive/, app/docs/archive/). It may be ignored by git or
     tracked; the skill checks which.
     Setting names stay as written (the skill compares them with this file):
     "CLAUDE.md" in a name means the project's instruction file, whichever
     the agent uses (CLAUDE.md, AGENTS.md, GEMINI.md). -->

## Archive
- folder: _archive/
- review age (days): 90
- cold storage: <where and how, e.g. "R2 bucket <name> via wrangler r2 object put --remote", an external drive path, or "none">

## Protect
- never touch (report only): <paths or globs>
- live paths (deployed: moving them changes the site): <paths or globs>

## Limits
- big file (KB): 1024
- big doc (KB): 25
- max folder depth: 5
- handoffs to keep per folder: 3
- always-loaded budget (lines across project CLAUDE.md files): 200

## Context
- state doc (where current status lives, not in CLAUDE.md): <path, e.g. docs/status.md, or "none">

## Git and media
- visibility (per repo, used when gh can't answer): <e.g. "root: local only; app/: private on GitHub">
- types kept out of git: <e.g. *.mp4 *.mov *.psd>
- exceptions that stay in git: <paths or globs>

## Retention
- <rule, e.g. "invoices: keep 5 years", "buyer data: delete after 90 days">

## Naming
- style: <kebab-case | snake_case | none>

## Personal data patterns (security mode, optional)
- email exceptions: <regex for addresses that are not personal data, e.g. @mycompany\.com$; generic inboxes like info@ are skipped already>
- <regex per line, e.g. a national ID number or phone format>
<!-- A phone pattern must match every way people write the number: grouped
     3-3-3, 3-2-2-2, no spaces, dots or dashes, with or without the country
     code. Test it on each form before saving. -->

## Rulings
<!-- Written by the skill after a run: the user's answers, one dated line each.
     Read at pre-flight so the next run doesn't ask again. Each line is dated
     the day it's written, never the date of a ruling it cites. -->
- <YYYY-MM-DD: ruling, e.g. "prospect phone lists stay out of git (ignored)">
- <YYYY-MM-DD: something to check again next run, ending in (re-check), e.g. "the old API key is not rotated yet (re-check)">
