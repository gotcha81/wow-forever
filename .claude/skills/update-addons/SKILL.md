---
name: update-addons
description: Check and update ALL addons in this repo after a WoW Forever game update - TOC interface numbers, Lua syntax, saved error logs, game API changes and vendored libraries - then deploy, commit and report. Use when the user says all addons should be updated/checked (e.g. "update all addons", "check everything", "new patch") or types /update-addons.
---

# Update all addons

The user wants one command that checks every addon and updates what's needed. Never ask them to update addons one by one. Work through these steps in order and keep the ground rules: don't assume, stay ToS-safe, and never print the game path or account names.

## 1. Run the check

The syntax check needs the Python package `luaparser`. If no Python with it is available, make a venv in the session scratchpad (never in the repo or the user's Python) and install it there:

```
python -m venv <scratchpad>/venv && <scratchpad>/venv/Scripts/python -m pip install luaparser
```

Then run, from the repo root:

```
<python with luaparser> tools/check_addons.py
```

It finds every addon folder (`<Folder>/<Folder>.toc`) and reports, per addon:
- **Interface**: the TOC number vs. the game's, worked out from the installed Forever client (`.build.info`, product `wowf`). For example, version 1.60.1 gives 16001.
- **Syntax**: syntax errors in the addon's own Lua files (`Libs/` is skipped).
- **Saved errors**: how many errors are in the addon's own error log.
- **API**: the game API the addon calls.

## 2. TOC interface numbers

If any TOC is behind, run `tools/check_addons.py --apply`. It writes the game's number into every TOC. All addons are Forever-only, with a single number.

## 3. Errors from play

For every addon that has saved errors, run `python tools/read_errors.py <Folder>`, then fix the cause in the code. Say which errors you fixed. Forever hides unit values as *secret values*, so read the memory note on that before you touch unit data.

## 4. Game API changes

Find out what changed in the game API between the old and new version. Allowed sources only:
- warcraft.wiki.gg (e.g. "Patch x.y.z/API changes")
- Blizzard's own patch notes or forums
- Wowhead
- well-established addon repos, including Blizzard's UI source mirror (Gethe/wow-ui-source)

Compare the changes with the API list from step 1, focusing on functions that were **removed, renamed or made secret**. Fix every addon that uses them, and keep the fallbacks for older clients where that costs little. If nothing affects our addons, say so.

## 5. Vendored libraries

The addons carry their own copies of libraries in `<Folder>/Libs/` (LibStub, CallbackHandler-1.0, HereBeDragons, ...). For each one, check the library's official repo or CurseForge page for a newer release that matters for this client version. If one exists, update every addon's copy; addons share no files. Keep `Libs/README.md` up to date.

## 6. Versions, check again, deploy, commit

- Bump the `## Version:` of every addon that changed: patch for TOC-only or small fixes, minor for real changes. Update an addon's README if its behaviour changed.
- Run `tools/check_addons.py` again: every addon should be up to date with no syntax errors.
- Deploy every changed addon with `powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1 -Addon <Folder>`. A brand-new addon needs a game restart, not just /reload.
- Commit everything in one commit, "Update all addons for WoW Forever <version>", with the attribution line, then push.
- Add a dated line to the project-status memory.

## 7. Report

Give a short report per addon: what changed (interface, fixes, API, libs), or "nothing needed". Say what has not been tested in game, and ask the user to /reload and tell you about any errors.
