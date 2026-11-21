# ClearTargetFrame

Clean, simple frames for **you, your target, your target's target and your focus**
in WoW Forever. Each frame shows only:

- a small **name bar**: the name on the left, **Elite** or **Boss** on the right
- the **health bar**
- the **power bar** (mana, rage, energy, ... in its own colour)

The **border** shows the target's level colour, like the game does: grey, green,
yellow, orange or red. Your own frame uses your class colour. Each frame can use a
custom colour instead.

Left-click a frame to target the unit, right-click it for the unit's menu (also in
combat). The game's own player, target, target-of-target and focus frames are hidden.

## Settings

Open them with `/ctf`, the game's addon menu, or Options > AddOns > ClearTargetFrame.

- **Health / power text**: none, value (`1234 / 2000`), percent (`62%`) or both
- **Health colour**: green, or the class colour for players
- **Size**: width, name bar, health bar and power bar heights, border size
- **Per frame**: show or hide, scale, border (level colour or a custom colour)
- **Unlock** to drag the frames, **Reset positions** to put them back

Sizes and positions can't change in combat (a game rule); they apply when combat ends.

## Commands

| Command | What it does |
|---|---|
| `/ctf` | open the settings |
| `/ctf unlock` / `/ctf lock` | drag the frames / fix them in place |
| `/ctf reset` | default positions |
| `/ctf errors` | caught errors (`/ctf errors clear` empties the list) |

`/cleartargetframe` works the same as `/ctf`.

## Licence

MIT (see the repository).
