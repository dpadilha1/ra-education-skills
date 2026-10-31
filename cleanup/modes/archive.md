# Mode: archive

Goal: decide, folder by folder, what in the archive is still worth keeping on
disk. Nothing leaves without the user's OK, and every delete is approved item
by item.

**When:** only when the user runs the skill alone or with `archive`. By default
it reviews folders past the review age; `archive all` reviews every folder. A
full run (no mode) mentions folders past the age and offers this mode.

Settings from `cleanup.md`: archive folder(s), review age (default 90 days), cold
storage (where and how to upload), protected paths, retention rules (e.g.
"invoices: keep 5 years", "buyer data: delete after 90 days").

## Steps

1. **Run `<skill>/scripts/review_archive.sh <root> <archive> <age>`** (age 0 for
   `archive all`; several archive folders → all of them in one
   comma-separated argument). Sections: archive folders (ignored by git or
   tracked) · folders up for review (age, size, text, media,
   rebuildable) · still mentioned live · exact copies live · `MOVES.tsv`
   checks · biggest media · totals.

2. **Read each reviewed folder's `MOVES.tsv`.** It's small and says why things
   were archived. Over 50 lines → read the first 50 (`head -n 50`).

3. **Give each folder a verdict.** Split a folder when its parts differ
   (text Keep, media Cold). Check the rows top to bottom; the first that
   matches wins.

   | # | signal | verdict |
   |---|--------|---------|
   | 1 | a retention rule in `cleanup.md` covers it | the rule wins |
   | 2 | still used by a live file (code, a site page, a doc people work from) | **Restore** |
   | 3 | client material, footage, deliverables, brand assets, raw recordings | **Cold** |
   | 4 | exact copy exists live, outside the archive (the script's hash match) | **Delete** |
   | 5 | rebuildable: name the command that regenerates it (`npm install`, the build command). A render counts only if its source file is shown to exist | **Delete** |
   | 6 | replaced: `MOVES.tsv` names a replacement and it exists | **Delete** (small text → Keep) |
   | 7 | text: notes, docs, code | **Keep** |
   | 8 | name, size, length and note don't settle it | **user decides** |

   - Mentioned only in history notes (decision log, journal) is not a reason
     to restore.
   - A folder name like `build/` or `dist/` alone doesn't prove rebuildable.
   - Torn between Delete and Cold → Cold. It's cheap and can be undone.
   - Media is judged by name, size, length and the `MOVES.tsv` note. Never
     open or play it. For text, read only the first lines (`head`), and only
     when the name and note aren't enough.

4. **Evidence per verdict**, e.g. `og-v2.jpg: replaced by og-v5.jpg (exists),
   0 live mentions → Delete`.

## Carrying out approved verdicts

- **Restore:** if the original path is free, move the files back to it, run
  the reference check from `SKILL.md`, log it in `LEDGER.tsv`. If something
  already sits at that path → user decides.
- **Keep:** nothing to do.
- **Cold:**
  1. State size, cost and time, then wait for the user's OK on that
     (uploading is an outward action).
  2. Zip the folder's media into the system temp folder and record its sha256.
     Upload it the way `cleanup.md` says, to the real remote (with Wrangler,
     `r2 object put` needs `--remote`, or it writes to local storage).
  3. Verify: download the object again and compare its sha256 with the local
     zip. A size match alone isn't enough.
  4. Only then remove the local media. Log where it went and the sha256 in
     `LEDGER.tsv`. Delete the temp zip.
  Never remove a local copy before its upload is verified.
- **Delete:**
  1. Show the exact paths and sizes. The user approves each item, or each
     folder with its full file list shown.
  2. Remove only those paths.
  3. Log each one in `LEDGER.tsv` (date, path, size, reason).
  Only a file whose current contents are committed can be restored (the
  script's first section counts tracked files and the ones with uncommitted
  changes, per archive). Check one:
  `git cat-file -e HEAD:<path> && git diff --quiet HEAD -- <path>`
  (exit 0 = restorable; an untracked or newly staged file fails the first
  part, an edited one the second; a committed file already gone from disk
  fails the second but `git checkout HEAD -- <path>` still brings it back). Before the delete is committed, restore
  with `git checkout HEAD -- <path>`; after,
  `git checkout "$(git rev-list -n1 HEAD -- <path>)^" -- <path>`. Any other
  file is gone for good, even inside a tracked archive; for an edited tracked
  file say that its edits are lost, and offer to commit them first. Mark each
  file in the list. Same OK per item either way.
- **Always:** `MOVES.tsv` and `LEDGER.tsv` are never deleted. When a whole
  folder goes, its `MOVES.tsv` stays as the record. `LEDGER.tsv` lives at the
  root of the archive it logs (format: `templates/LEDGER.tsv`).

## Priority
Sort by disk space freed, biggest first. Retention-rule hits ("must delete
after N days") go first, whatever their size.

## Report
Add findings to the shared report (mode = archive): one row per folder or
part, with verdict, space freed and evidence. End with totals: space freed on
disk · text kept · sent to cold storage (and its cost).
