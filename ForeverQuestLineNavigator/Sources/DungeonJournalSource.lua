-- Optional: reads DungeonJournal's (ForeverDungeonJournal) quest data while the game runs.
--
-- DungeonJournal has no licence file, so NOTHING from it is copied into this addon.
-- Its data is internal to that addon (not an official API), so every read is checked.
-- If anything looks unexpected, this source switches itself off and the addon
-- carries on with QuestieDB data only.

local _, ns = ...

local D = {
    available = false,
    quests = {},  -- [questId] = { dungeon = name, faction = "Horde"|"Alliance"|"Both", level =, requires = }
    chains = {},  -- [questId] = { prerequisite ids in order }
    xp = {},      -- [questId] = stored Forever XP (fallback when the game client has no answer)
}

local function ReadXP(fdj)
    if type(fdj.FOREVER_QUEST_XP_FALLBACK) == "table" then
        for questId, xp in pairs(fdj.FOREVER_QUEST_XP_FALLBACK) do
            if type(questId) == "number" and type(xp) == "number" and xp > 0 then D.xp[questId] = xp end
        end
    end
end
ns.DungeonJournalSource = D

local function ReadDungeons(fdj)
    if type(fdj.DB) ~= "table" then return 0 end
    local count = 0
    for dungeonName, dungeon in pairs(fdj.DB) do
        if type(dungeonName) == "string" and type(dungeon) == "table" and type(dungeon.quests) == "table" then
            for _, q in ipairs(dungeon.quests) do
                if type(q) == "table" and type(q.id) == "number" then
                    D.quests[q.id] = {
                        name     = type(q.name) == "string" and q.name or nil,
                        dungeon  = dungeonName,
                        faction  = type(q.faction) == "string" and q.faction or "Both",
                        level    = type(q.level) == "number" and q.level or nil,
                        requires = type(q.requires) == "number" and q.requires or nil,
                    }
                    if type(q.liveXPFallback) == "number" and q.liveXPFallback > 0 and not D.xp[q.id] then
                        D.xp[q.id] = q.liveXPFallback
                    end
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function ReadChains(fdj)
    if type(fdj.QUEST_PREREQ_CHAINS) ~= "table" then return end
    for questId, steps in pairs(fdj.QUEST_PREREQ_CHAINS) do
        if type(questId) == "number" and type(steps) == "table" then
            local ids = {}
            for _, step in ipairs(steps) do
                if type(step) == "table" and type(step.id) == "number" then
                    ids[#ids + 1] = step.id
                end
            end
            if #ids > 0 then D.chains[questId] = ids end
        end
    end
end

function D:Init()
    local fdj = rawget(_G, "ForeverDungeonJournal_NS")
    if type(fdj) ~= "table" then return end -- not installed: nothing to do, no message
    local ok, count = pcall(function()
        ReadXP(fdj)
        local n = ReadDungeons(fdj)
        ReadChains(fdj)
        return n
    end)
    if ok and count and count > 0 then
        self.available = true
    else
        wipe(self.quests)
        wipe(self.chains)
        wipe(self.xp)
        ns.Print("DungeonJournal is installed, but its data was not recognised. Using QuestieDB data only.")
    end
end
