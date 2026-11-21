# ClearTargetFrame

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

Open them with the **minimap button**, `/ctf`, the game's addon menu, or
Options > AddOns > ClearTargetFrame. Right-click the minimap button to unlock or lock the frames.

The settings have tabs: **General** (unlock, hide the game's frames, minimap button,
reset positions) and one tab per frame: Player, Target, Target of target, Focus, Pet.
Every frame tab has the same settings, so each frame is set up on its own:

- **Show** the frame or not
- **Health / power text**: a text on the left and one on the right of each bar, each
  none, remaining (`1234`), value (`1234 / 2000`), percent (`62%`) or both. Default: percent left, value right.
- **Health colour**: green, or the class colour for players
- **Size**: width, name bar, health bar and power bar heights, border size and scale
- **Border**: level colour (your class colour on the Player frame) or a custom colour
- **Debuffs** under the frame: on or off, how many (16 by default), icon size, icons per row.
  On by default for Target and Target of target.

Sizes and positions can't change in combat (a game rule); they apply when combat ends.

## Commands

| Command | What it does |
|---|---|
| `/ctf` | open the settings |
| `/ctf unlock` / `/ctf lock` | drag the frames / fix them in place |
| `/ctf reset` | default positions |
| `/ctf minimap on\|off` | show or hide the minimap button |
| `/ctf errors` | caught errors (`/ctf errors clear` empties the list) |

`/cleartargetframe` works the same as `/ctf`.

## Licence

MIT (see the repository).
