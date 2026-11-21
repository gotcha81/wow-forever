# CleanFrame

Clean, simple frames for **you, your target, your target's target, your focus and your pet**
in WoW Forever. Each frame shows only:

- a small **name bar**: the name on the left, **Elite** or **Boss** on the right
- the **health bar**
- the **power bar** (mana, rage, energy, ... in its own colour)
- **debuffs** in rows outside the frame, under it (on by default for target and target
  of target). Hover one for its tooltip.

The **border** shows the target's level colour, like the game does: grey, green,
yellow, orange or red. Your own frame uses your class colour. Each frame can use a
custom colour instead.

Left-click a frame to target the unit, right-click it for the unit's menu (also in
combat). The game's own player, target, target-of-target, focus and pet frames are hidden.

**Mind control**: the game has no separate frame for it; the unit you control becomes
your pet. The Pet frame shows it and marks it **Mind controlled**.

## Settings

Open them with the **minimap button**, `/cfr`, the game's addon menu, or
Options > AddOns > CleanFrame. Right-click the minimap button to unlock or lock the frames.

**Test mode** (General tab, `/cfr test`, or Shift-click the minimap button) shows every
frame with sample data: a different level colour, Elite/Boss/Mind controlled tag and power
type on each, moving health and sample debuffs. Change settings while it runs to see them
at once. It ends when combat starts.

**Import / export** (General tab, `/cfr export`, `/cfr import`): all settings as one line
of text, to keep or share. Importing only takes known settings; nothing in the text is run as code.

(Up to 0.6.0 this addon was called ClearTargetFrame, with `/ctf`.)

The settings have tabs: **General** (unlock, hide the game's frames, minimap button,
reset positions) and one tab per frame: Player, Target, Target of target, Focus, Pet.
Every frame tab has the same settings, so each frame is set up on its own:

- **Show** the frame or not
- **Health / power text**: a text on the left and one on the right of each bar, each
  none, remaining (`1234`), value (`1234 / 2000`), percent (`62%`) or both. Default: percent left, value right.
- **Health colour**: green, or the class colour for players
- **Size**: width, name bar, health bar and power bar heights, border size and scale
- **Position**: X and Y offset from the screen centre, with a slider or by typing the
  number (dragging the unlocked frame updates them too)
- **Border**: level colour (your class colour on the Player frame) or a custom colour
- **Debuffs** under the frame: on or off, how many (16 by default), icon size, icons per row.
  On by default for Target and Target of target.

Sizes and positions can't change in combat (a game rule); they apply when combat ends.

## Commands

| Command | What it does |
|---|---|
| `/cfr` | open the settings |
| `/cfr unlock` / `/cfr lock` | drag the frames / fix them in place |
| `/cfr test` | test mode on / off |
| `/cfr reset` | default positions |
| `/cfr export` / `/cfr import` | copy all settings as text / paste settings |
| `/cfr minimap on\|off` | show or hide the minimap button |
| `/cfr errors` | caught errors (`/cfr errors clear` empties the list) |

`/cleanframe` works the same as `/cfr`.

## Licence

MIT (see the repository).
