# wow-forever
Multiple wow-forever addons under one repository for anyone who wish to use it.

## Dev tools

- `python tools/check_addons.py`: checks every addon against the installed WoW Forever
  client (TOC interface number, Lua syntax, saved errors, game API used).
  Add `--apply` to write the game's interface number into every TOC.
- `python tools/read_errors.py <Addon>`: an addon's caught Lua errors.
- `tools/deploy.ps1 -Addon <Addon>`: copy an addon into the game (path in the git-ignored
  `tools/deploy.local.json`).
- Claude Code skill `/update-addons` (`.claude/skills/update-addons`): runs the whole
  update for all addons after a game patch.
