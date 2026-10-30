# Mode: structure

Goal: a layout where every file has one obvious home, so people and agents
find things fast and never read the wrong copy.

Settings from `cleanup.md`: archive folder(s), max depth (default 5), protected
paths, naming style if the project has one.

## Steps

1. **Run `<skill>/scripts/map_tree.sh <root> <archive> <max_depth>`** (several archive
   folders → one comma-separated argument; their contents stay out of the
   smell sections). Sections:
   top-level map · loose root files · deep paths · single-item and crowded
   folders · odd names · mixed naming styles · twin folders · dump folders ·
   archive-like folders · archive check · top-level folders no doc describes.

2. **Judge each hit.**
   - **Framework rules win.** `app/`, `src/`, `public/`, `pages/`, `migrations/`
     and similar are where the tools expect them. Never propose moving those.
   - **Twin folders** (`docs/` and `documentation/`, `old/` next to
     `_archive/`): the same kind of thing in two homes. Propose one home.
   - **Loose root files:** where does each belong? No clear home → user decides.
   - **Dump folders** (`outputs/`, `misc/`, `tmp/`): sort the contents into
     real homes or the archive. Don't just rename the folder.
   - **Deep paths and single-item folders:** flatten only if nothing depends
     on the path (imports, URLs, deploy config).
   - **Naming:** a mixed style in one folder is low priority. Spaces and
     accents matter more: they break shell commands and URLs.
   - **Archive check:** undated folders, missing `MOVES.tsv`, loose files at
     the archive root. Tracked or ignored by git is a choice, not a finding:
     a tracked archive keeps history (deletes can be undone), an ignored one
     keeps big files and secrets out of git. A tracked archive is a finding
     only if it holds a secret-type file or media `cleanup.md` keeps out of
     git. Check with
     `git ls-files -- "<archive>" | grep -iE '(^|/)\.env|\.(pem|key|p8|p12|pfx)$|<types kept out of git, as a regex>'`.
   - **Folders no doc describes:** tool folders (`.claude/`, `.agents/`, `.github/`,
     `.vscode/`...) need no line; the script skips the usual ones.

3. **Price every move before proposing it.** For each path, grep how many
   files point to it (imports, links, docs, deploy config). Put that count in
   the finding. Many references + small gain → don't propose it.

## Priority

| level  | when |
|--------|------|
| high   | same kind of thing in two homes · archive-like folders outside the archive · secret-type file or kept-out media tracked in the archive |
| medium | loose root files · dump folders · paths deeper than max · archive folders undated or without `MOVES.tsv` · top-level folder no doc describes |
| low    | single-item folders · mixed naming styles · spaces and accents in names |

## Fixes to propose

| finding | fix |
|---------|-----|
| twin folders | merge into one with `git mv`, update every reference |
| archive-like folder outside the archive | move its contents into `<archive>/YYYY-MM-DD-<topic>/` |
| loose root file | `git mv` to its home, or archive it |
| dump folder | sort each file into a home or the archive, then remove the empty folder |
| too deep / single-item folder | move up one level, update references |
| bad name | `git mv` to the project's style, update references |
| undated archive folder | rename to `YYYY-MM-DD-<topic>`, add a `MOVES.tsv` saying what's inside |
| top-level folder no doc describes | add one line on its purpose to the root README or the instruction file's map |

**Live paths:** renaming or moving anything the site serves changes its URL.
Old links break at the next deploy. Say so in the finding, and propose a
redirect if the host supports it.

## Report
Add findings to the shared report (mode = structure), with the reference
count for every proposed move.
