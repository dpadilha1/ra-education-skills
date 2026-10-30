# Backlog

Open items per skill: things a test run surfaced but we haven't fixed yet,
and ideas. Fixed items leave this file; their why lives in the commit message.

## cleanup
- Full support for other agents, after a real run on Codex or Gemini CLI
  shows what breaks: their permission config (Codex `config.toml`, Gemini
  `settings.json`), memory, and exact instruction-file loading rules. Today
  these are reported as "not checked".

## Ideas
- cleanup: default the archive to "text tracked, media ignored" instead of
  fully ignored, so `MOVES.tsv` gets history and text deletes can be undone.
- More skills, one per job, same router pattern (SKILL.md + modes/ + scripts/).

## Before going public
- License.
- CodeRabbit review on the PR that makes the repo public.
