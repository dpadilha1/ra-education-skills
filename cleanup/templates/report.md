# Cleanup report: <project> · <YYYY-MM-DD> · modes: <list>

Nothing has been changed yet. Reply with the numbers to fix ("do 1, 3, 5"),
"all high", or "none", plus the `R` and `T` labels below you approve.

| # | mode | priority | finding | evidence | proposed fix | saves |
|---|------|----------|---------|----------|--------------|-------|
| 1 | security | high | ... | ... | ... | — |

Rows in run order (security, bloat, structure, context, archive), highest
priority first inside each mode. A fix that changes a live site starts with ⚠ live.

## User decides
Numbers continue the table above. An item lives in one table only: a
finding needing an answer goes here, not in both.

| # | finding | question to answer |
|---|---------|--------------------|

## Reminders
Rulings in `cleanup.md` that say to re-check this run (a key to rotate, a
date to pass), unless a newer ruling cites them ("per <date>"). Not findings: no number, no fix. Ask once; the answer becomes
a new ruling.
- <ruling date: what to re-check> → <still open? / question>

## Clean
One line per check that found nothing, or found only hits not worth fixing
(say why), so it's clear it ran.
- security: no secrets in files or history ✓

## Totals
- findings: N (high X · medium Y · low Z) · reminders: R
- disk freed if all approved: ~X
- tokens saved per session if all approved: ~X
- not checked: <what and why, e.g. "repo visibility: gh offline">

## Recommendation
I'd do <numbers>: <one-line why>. I'd skip <numbers> (findings with a real
trade-off only): <one-line why>.
For <user-decides numbers> I need your answers.
Save as rulings, so the next run doesn't weigh them again (the `(ruling?)`
lines from Clean, exact wording):
- R1: <today's date (date +%F)>: <verdict>
Trail the project's rules ask for (exact wording), or "none required":
- T1: <file: entry>
