# Forever QuestLine Navigator

A WoW Forever addon that shows the dungeon quest chains for your level, in pickup
order, with numbered map pins and a blue arrow to the next stop.

**Status:** first draft (0.2.0), focused on Horde. It is being tested on level 35 characters.

## Needs
- **Required:** [Questie](https://www.curseforge.com/wow/addons/questie) and its QuestieDB (Forever versions).
- **Optional:** DungeonJournal (ForeverDungeonJournal) gives better chain data. With OpenMap installed, the pins show on its seamless map.

## Install
Copy the `ForeverQuestLineNavigator` folder into `World of Warcraft\_forever_\Interface\AddOns\`.

## Use
- `/fqln`: show or hide the quest list.
- `/fqln help`: all commands.
- `/fqln status`: shows what the addon is using right now.
- Click a quest in the list, or a pin on the map, to point the arrow at it.
- Hover the arrow for a padlock (pin it in place), text size (A- / A+) and hide.
- The quest window has a padlock and a minimize button. Minimized, it shows only your next stop.
- The QN minimap button: left-click opens the list, right-click turns the arrow on or off.
- The arrow is hidden inside dungeons, raids, battlegrounds and arenas. The list keeps working.
- `/fqln debug` opens a window with position values to copy (Ctrl+C) when reporting a problem.

## Parked features
- **Game waypoint (Retail-style map pin and in-world marker).** Removed in 0.2.x. Forever
  accepts the waypoint (`C_Map.SetUserWaypoint`, `C_SuperTrack`) but never draws it.
  The code is in git history at commit `08ba4f1` (`UI/Arrow.lua`, `A:UpdateGameWaypoint`).
  `/fqln debug` still checks the game's waypoint API. If a Forever patch starts drawing
  user waypoints, the option can be brought back.

## Data
- Quest, NPC and map data come from QuestieDB's public API while you play.
- If DungeonJournal is installed, its quest chains are read at runtime. Nothing from it is copied into this addon.
- `Data/Overrides.lua` holds hand-checked corrections (quest IDs only), taken from Wowhead's WoW Forever database.

## Licence
MIT for this addon's own code and art. Bundled libraries keep their own licences; see `Libs/README.md`.
