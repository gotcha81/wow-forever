# Forever QuestLine Navigator

A WoW Forever addon that shows the dungeon quest chains for your level, in pickup
order, with numbered map pins (grey quests show on the maps only once they are in your quest log) and a blue arrow to the next stop.

**Status:** draft (0.9.0), focused on Horde. It is being tested on level 35 characters.

## Needs
- **Required:** [Questie](https://www.curseforge.com/wow/addons/questie) and its QuestieDB (Forever versions).
- **Optional:** DungeonJournal (ForeverDungeonJournal) gives better chain data. With OpenMap installed, the pins,
  the route line and the quest markers show on its seamless map.

## Install
Copy the `ForeverQuestLineNavigator` folder into `World of Warcraft\_forever_\Interface\AddOns\`.

## Use
- `/fqln`: show or hide the quest list.
- `/fqln help`: all commands.
- `/fqln status`: shows what the addon is using right now.
- Click a quest in the list, or a pin on the map, to point the arrow at it.
- **Route line** (0.9.0): on the world map (and OpenMap) a line runs from you to stop 1 (gold), then on
  to 2, 3 ... (blue), under the numbered pins. A leg that changes continent is left out.
  Settings > Map, or `/fqln line on|off`.
- **Quest on the map** (0.9.0): clicking a quest in any tab also shows it on the world map, OpenMap and
  the minimap with this addon's own markers (not Questie's): **S** = quest giver, **E** = turn-in,
  small blue dots = objectives (mobs, objects, item drops, places to explore; finished objectives drop
  out). One quest at a time: clicking another quest takes over; clicking the same quest again, Esc, or
  turning it in removes them. An Esc that closes the world map leaves them; the next Esc removes them.
  The row says "shown on the map".
- **Quest log** (0.9.0): when the clicked quest is in your quest log, the game's quest log opens on it,
  like Questie's tracker does, so the log shows whichever addon you clicked last. Not in combat, and not
  in controller mode (it would taint the gamepad bindings). Both on/off in Settings > Map.
- **Zone tab** (0.9.0, `/fqln z`, or `/fqln z <name>`): pick a zone to see every quest picked up there
  (where the quest giver stands), with its state for you. **(MZ)** at the end of a name means the quest
  itself spans more than one zone (giver, objectives and turn-in are not all in the same zone); hover it
  for the zones. A dungeon counts as the zone its entrance is in. Grey quests are folded under a `+` row.
  The tab follows you when you enter a new zone.
- Hover the arrow for a padlock (pin it in place) and a cogwheel (settings). Right-click it to hide it.
- **Dungeon tab** (`/fqln d`, or `/fqln d <name>`): pick a dungeon to see all its quests: done, on it,
  or what you are missing in the chain and where that starts. Grey quests are hidden unless what follows
  gives at least 35% of a level.
- **Search** (the box under the tabs): searches every quest you can do by quest name, questline, dungeon,
  zone and the NPC that starts it. Grey quests are folded under a `+` row. Clears when the window closes.
- **Route by XP per hour** (0.8.0): the route is planned about an hour ahead, picking each step for
  the most XP per second of travel plus time spent (objectives from kill counts, `/fqln killtime`;
  one dungeon run for all quests you hold for it, `/fqln dungeontime`). Picking up a quest adds its
  objectives and turn-in later in the route (shown as **[Later]**), and a turn-in unlocks the next
  quest of its questline. Dungeon runs wait while pickups for that dungeon are still close by.
  The Route header shows the planned minutes and XP per hour.
  - Optional **Shortest Path Forever** (GPL-3.0): real travel times with flight paths, boats,
    zeppelins, portals and hearthstone, through its public API. Without it: straight-line distance.
  - Optional **ForeverDB** (forever-db, GPL-3.0): quest XP at your level when the game has not told
    us yet, and NPC spots recorded on Forever for the NPCs tab. Read at runtime only.
- **Whole questline**: the **+** on a Route or Dungeon row opens every quest of its questline under it
  (step, level, done / on quest, where it starts and ends, XP); **-** closes it. Click a step to point
  the arrow there.
- **NPCs tab**: search friendly NPCs by name, title (flight master, innkeeper, weapon trainer) or zone.
  Click one to mark every place it stands on the world map and minimap (green pins), with the arrow
  pointing at the nearest. Esc, the x, right-click or marking another NPC removes the marker, and it
  goes by itself when you talk to that NPC. "Keep pinned" keeps it through Esc and /reload.
  Shift-click puts the NPC's Wowhead (Forever) address in the chat box to copy (`/fqln npc [name]`,
  `/fqln unmark`). Positions, best first:
  - **learned by playing** (all your characters): where you stand when you talk to an NPC (exact),
    or target / mouse over a friendly or neutral NPC close by (rough, paler pin, only when nothing
    better is known). NPCs Questie does not know become searchable this way too;
  - **the game's own flight data** for flight masters and flight points;
  - **QuestieDB** spawns, plus small dots along the walking path of NPCs that move around;
  - **your own coordinates**: `/fqln pin [zone] x y [name]`, e.g. `/fqln pin Orgrimmar 32.2 37.8 Thrall`
    (Wowhead's "[32.2, 37.8]" style works too).
  Wowhead is never read by the addon.
- **Nearby quest targets**: a small window lists the quest mobs and NPCs close to you (to kill, drop a
  quest item, turn in to, or give the arrow's quest), with a click to target them. It finds them by
  nameplates (V key), target, mouseover and combat. Settings: on/off and "also inside dungeons".
- **Shift-click** a quest to put its Wowhead (Forever) address in the chat box, selected (Ctrl+C copies it).
  Addons cannot open a browser. On/off in Settings > Links.
- Right-click a quest to **ignore** its questline (saved per character). Ignored ones are listed at the
  bottom of the Route tab; right-click there to bring them back.
- Optional (Settings, off by default): when you enter a dungeon, chat lists the quests for it you could have
  picked up but don't have.
- `/fqln errors`: the addon's error log in a copy window (`/fqln errors clear` empties it). It catches every Lua error from this addon's files, not just the wrapped ones.
- The quest window has a padlock, a cogwheel and a minimize button. Minimized, it shows only your next stop.
- Settings (cogwheel) has the text sizes for the arrow and the quest window, plus the on/off switches.
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
