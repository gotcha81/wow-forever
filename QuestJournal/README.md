# QuestJournal

A journal for **open-world quest chains** in WoW Forever, in the style of a dungeon
journal: follow any chain from its first quest to its last.

- **In progress**: chains you are on (a quest in your log, or the next quest ready to pick up).
- **By zone**: every other chain, in the zone where it starts. Your zone is listed first.
- **Trivial**: chains where every quest is grey for you.
- **Completed**: chains you have finished.

Each chain shows the step you are on. **[+] earlier quests** opens the quests before
it, and **[+] next quests** opens the ones after it. Every quest shows its XP, and
the chain shows the XP for the whole chain (and how much is left). Hover a quest to
see its objectives, the quest giver, where to hand it in, and its rewards.

- **Key icon**: the chain rewards a key (shown on the chain and all of its quests).
- **Map button**: marks where the quest starts (S) and where you hand it in (E) on
  the world map and minimap. Click it again, right-click a pin, or type `/qj clear` to remove them.
- **Faction button**: shows chains for your faction, Horde, Alliance, or both.

Open it with the minimap button, the game's addon menu, or `/qj`.

## Data

- **Questie + QuestieDB** (optional, recommended): every chain, quest givers,
  turn-ins, objectives, reward items and map positions.
- Without Questie the journal only knows what the game client itself tells it.
- XP comes from the game client (exact). Until the game sends it, Questie's
  estimate is shown with a `~`.

## Commands

| Command | What it does |
|---|---|
| `/qj` | open or close the journal |
| `/qj clear` | remove the map pins |
| `/qj minimap on\|off` | show or hide the minimap button |
| `/qj status` | what data was found |
| `/qj errors` | caught errors (`/qj errors clear` empties the list) |

## Licence

MIT (see the repository). Bundled libraries keep their own licences, see `Libs/README.md`.
