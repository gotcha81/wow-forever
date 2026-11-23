# DisenchantInfo

For enchanters in WoW Forever: hover over an item and its tooltip shows what it
disenchants into.

```
Disenchant: chance (with Salvager) - vendor - AH
Strange Dust x1-2 - 80% (85%) - 3c - 1s 20c
Lesser Magic Essence x1-2 - 20% (15%) - 16c - 4s
Average worth - 7c (8c) - 1s 76c
your log - logged 34 / 21 with Salvager (20 needed)
```

Each line is: **material - chance (chance with the Arcane Salvager) - vendor price - AH price**.

- The **AH price** comes from TradeSkillMaster (DBMarket). Without TSM there is no
  AH column: the lines end after the vendor price.
- **Average worth** is what one disenchant of this item gives on average
  (chance x amount x price), at vendor and on the AH. The value with the Salvager is in brackets.
- Prices are for one of the material.

## Learning from your disenchants

Every disenchant you do is logged: the item, what came out, and whether the Arcane
Salvager was active. Items are grouped like the game does (armor or weapon, quality,
item level band). Once a group has enough disenchants (20 by default, see the settings),
the tooltip shows **your own numbers** instead of the standard table.

- Until then the chance comes from the standard Classic disenchant table. Those
  chances are not confirmed for WoW Forever, since the game client doesn't contain them.
- **Arcane Salvager**: nobody has published how much it helps. The chance with it
  shows `(?)` until enough disenchants with the Salvager are logged for that group.
- `/dei stats` compares everything logged without and with the Salvager (dust,
  essence, shard and crystal: how often and how many). This is where its effect shows first.

### Is the Salvager active?

The setting has three choices: **Auto** (default), **On**, **Off**.
Auto looks for a buff with "Salvager" in its name. If the Salvager gives no buff
of its own, set it **On** by hand while you disenchant at one, and back to Auto or Off
afterwards. Use `/dei salvager` or right-click DisenchantInfo in the game's addon menu
to switch. Every tooltip reminds you while it's On by hand.

## Commands

| Command | |
|---|---|
| `/dei` | settings (also: Options > AddOns > DisenchantInfo, or click it in the addon menu) |
| `/dei salvager` | Salvager auto > on > off (or `/dei salvager on`) |
| `/dei stats` | what's logged, without vs with the Salvager |
| `/dei buffs` | your buffs right now (to find the Salvager's buff) |
| `/dei errors` | caught errors |

## Settings

Who sees the lines (enchanters only, or every character), amount on/off, the average
worth line on/off, a chat line per logged disenchant, how many disenchants are needed
before your own numbers are used, the Salvager mode, and a button that forgets everything logged.
