# Mode: bloat

Goal: find weight the project doesn't need: big files, files nothing uses,
duplicates, old versions, junk. (Shortening docs an agent reads is the context
mode's job.)

Settings from `cleanup.md`: big-file threshold (default 1MB), protected paths,
which file types stay out of git (and the exceptions), cold storage.

## Steps

1. **Run `<skill>/scripts/find_big.sh <root> <min_kb>`.** Sections: big files now ·
   biggest files ever committed · git history size · ignored folders on disk ·
   generated files tracked.

2. **Run `<skill>/scripts/find_unused.sh <root> "<protected paths regex>" <archive>`**
   (several archive folders → one comma-separated argument). Archived files
   are unused on purpose and a mention inside the archive is history, so the
   script leaves the archive out of every section but junk. Sections:
   files nothing mentions · exact duplicates · versioned siblings · junk ·
   empty files and folders.

3. **Judge each hit.** The scripts search names only, so check before flagging:
   - **Rolled-up folder** (`<folder>/  N unused of M files, rolled up`, the
     dates of their last commits): judge the folder as a whole first. A
     Retention rule in `cleanup.md` that covers it decides: if every date is
     under its age, it's Clean, one line. Otherwise list the folder's unused
     files with their dates and check the ones past the age:
     `CLEANUP_ROLL=999999 CLEANUP_MAX=999999 "<skill>/scripts/find_unused.sh" <root> "<skip>" | grep -F '<folder>/'`
     (for `(root)/`, keep the lines whose path has no `/`). No rule → judge a
     sample of 5, then the rest by the same reasoning, and say so.
   - **Unused:** is it loaded by a pattern, not its name (glob in a build
     config, dynamic import, a route that maps a URL to a file, a host serving
     it directly like `/favicon.ico`)? An entry point the script missed
     (`package.json` main/scripts, deploy config `main`)? A doc people read
     directly (handoffs, logs)? Any yes → fine.
     A comment in the code or a current doc (README, state doc) that keeps
     it on purpose ("parked", "disabled for now", "lives in X so it can come
     back"), including the file's own header (`head -n 20`: the script
     ignores self-mentions)? → Clean, quoting `file:line`, marked
     `(ruling?)`. An old journal or decision-log entry alone doesn't count.
   - **Duplicates:** keep the copy something references. Both referenced →
     user decides.
   - **Versioned siblings:** the live one is the one referenced. The rest →
     archive. None referenced → user decides. A keep-comment (see Unused) on
     a sibling or duplicate → Clean, `(ruling?)`.
   - **Big tracked media:** should it be in git at all? Check the media rule
     in `cleanup.md`.
   - **Generated files tracked:** does a build command make them? If the host
     deploys straight from git, it may need them → user decides.
   - **History-only big files, ignored folders:** info only. History weight
     needs a rewrite to remove (never the default); ignored folders cost disk,
     not tokens.

4. **Evidence per finding**, e.g. `0 mentions of "logo-v2.png" · last commit
   2026-03-04 · no glob in build config`.

## Priority

| level  | when |
|--------|------|
| high   | file over 10MB tracked in git · big file not ignored (next `git add` commits it) |
| medium | unused files · duplicates · old versions · generated files tracked |
| low    | junk · empty files and folders |

## Fixes to propose

| finding | fix |
|---------|-----|
| unused file | move to archive, log in `MOVES.tsv` |
| duplicate | keep the referenced copy, archive the rest |
| old version | archive every version that isn't live |
| big media tracked | `git rm --cached`, add the pattern to `.gitignore`; file stays on disk |
| big file not ignored | add it to `.gitignore` before it gets committed |
| junk tracked | `git rm --cached`, add the pattern to `.gitignore` |
| junk not ignored | add the pattern to `.gitignore` |
| empty file | archive (user decides if it's a placeholder) |
| empty folder | remove it (nothing inside to lose); log it in `MOVES.tsv` |
| generated file tracked | `git rm --cached` + ignore, only if the deploy doesn't need it |
| history weight · ignored folders | info only; say which rebuild command frees the space |

**Live files:** archiving anything the site serves takes it off the site at the
next deploy. Say so in the finding.

## Report
Add findings to the shared report (mode = bloat), biggest saving first, with sizes.
