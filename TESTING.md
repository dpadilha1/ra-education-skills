# Testing a skill

How skills in this repo get tested and improved. Learned on real runs.

## The loop
1. **Two chats.** A *testing chat* runs the skill the way any user would
   (`/<skill>` in the project folder, nothing explained). A *maintainer chat*
   owns the skill's files and reads the testing chat's output as evidence.
   They see different problems: the testing chat feels what's confusing from
   inside the run, the maintainer sees what the output says about the skill.
2. **Fix after the run, never during.** The run reads the skill's files at
   every step. Editing them mid-run mixes two versions, and the fix phase
   (commits, logs, verification) teaches its own lessons.
3. **Collect lessons from both chats**, then fix them in one commit.
4. **Cold review every change.** A fresh subagent that never saw the reasoning
   reads the diff and the touched files, tests the scripts on a synthetic
   layout with traps, and reports. Fix what it finds in the same commit.
   Fixes create bugs too: a fix for false alarms can start hiding real ones.
5. **Prove it with a re-run** on the same project. A second run on a cleaned
   project should be quiet; anything it still says is the next lesson.

## Rules of thumb
- **When Claude improvises, the skill has a gap.** Copying a script to get
  past a limit, or reading a file to test a rule, means the skill offered no
  proper way. Add the way (an override, a check) and a clear "never".
- **Proven over documented.** Prefer what a run has shown to work over what
  the docs say should work, especially where the sandbox is involved.
- **Second runs test memory.** A first run on a messy project tests whether
  the skill finds problems; a second run tests whether it remembers what's
  settled (rulings, retention) and stays quiet.
- **Verdicts must be stable.** A judgment one run makes ("not worth moving")
  is saved as a ruling, or the next run may judge it differently.
- **Paste-ready means complete.** Text handed to the user to paste into the
  testing chat has no placeholders and no "A or B" left in it.
