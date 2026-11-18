-- Hand-maintained data that sits on top of QuestieDB (and DungeonJournal, if installed).
--
-- Facts only (quest IDs, area IDs, levels), looked up one page at a time on
-- Wowhead's WoW Forever database (https://www.wowhead.com/forever) or official
-- Blizzard sources. No text or data is copied from other addons.

local _, ns = ...

ns.Overrides = {
    -- Instances in QuestieDB's dungeon list that are NOT 5-player dungeons
    -- (raids, battlegrounds, travel). Their quests are not listed as dungeon quests.
    notDungeons = {
        [1977] = true, -- Zul'Gurub (raid)
        [2159] = true, -- Onyxia's Lair (raid)
        [2257] = true, -- Deeprun Tram (travel)
        [2597] = true, -- Alterac Valley (battleground)
        [2677] = true, -- Blackwing Lair (raid)
        [2717] = true, -- Molten Core (raid)
        [2917] = true, -- Hall of Legends (PvP hall)
        [2918] = true, -- Champions' Hall (PvP hall)
        [3277] = true, -- Warsong Gulch (battleground)
        [3358] = true, -- Arathi Basin (battleground)
        [3428] = true, -- Temple of Ahn'Qiraj (raid)
        [3429] = true, -- Ruins of Ahn'Qiraj (raid)
        [3456] = true, -- Naxxramas (raid)
    },

    -- Extra dungeon quests QuestieDB does not file under a dungeon.
    -- [questId] = dungeonAreaId   (example: [12345] = 718, -- Wailing Caverns)
    extraDungeonQuests = {
    },

    -- Quests to never show (removed from Forever, broken, or not really dungeon quests).
    -- [questId] = true,
    hiddenQuests = {
    },

    -- Hand-checked prerequisite chains, in the order you do them, used when
    -- neither QuestieDB nor DungeonJournal gets the chain right.
    -- [finalQuestId] = { firstStepId, secondStepId, ... },
    chains = {
    },
}
