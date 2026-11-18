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
- Drag the arrow to move it. Right-click it to hide it.
- The arrow is hidden inside dungeons, raids, battlegrounds and arenas. The list keeps working.

## Data
- Quest, NPC and map data come from QuestieDB's public API while you play.
- If DungeonJournal is installed, its quest chains are read at runtime. Nothing from it is copied into this addon.
- `Data/Overrides.lua` holds hand-checked corrections (quest IDs only), taken from Wowhead's WoW Forever database.

## Licence
MIT for this addon's own code and art. Bundled libraries keep their own licences; see `Libs/README.md`.
