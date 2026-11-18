-- Quest XP at your current level.
--
-- Order of sources:
--   1. The game client (exact, Forever numbers). Quests you don't have yet are
--      loaded with C_QuestLog.RequestLoadQuestByID first; the answer arrives
--      with the QUEST_DATA_LOAD_RESULT event.
--   2. DungeonJournal's stored Forever values (only if it is installed).
--   3. forever-db's reward XP at your level (only if ForeverDB is installed).
--   4. Questie's estimate (Classic numbers, marked as an estimate).

local _, ns = ...

local X = {
    cache = {},       -- [questId] = xp from the client, for the current level
    requested = {},   -- [questId] = time of the last load request
    estimates = {},   -- [questId] = true when the last value was not from the client
}
ns.XP = X

local MAX_REQUESTS_PER_PASS = 30
local RETRY_AFTER = 120 -- seconds before asking the server again for the same quest
local requestsThisPass = 0

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

function X:NewPass()
    requestsThisPass = 0
end

function X:Clear()
    wipe(self.cache)
    wipe(self.estimates)
end

local function Request(questId)
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    if requestsThisPass >= MAX_REQUESTS_PER_PASS then return end
    local last = X.requested[questId]
    if last and GetTime() - last < RETRY_AFTER then return end
    X.requested[questId] = GetTime()
    requestsThisPass = requestsThisPass + 1
    pcall(C_QuestLog.RequestLoadQuestByID, questId)
end

local questXPModule
local function QuestieEstimate(questId)
    if questXPModule == nil then
        questXPModule = false
        if QuestieLoader and QuestieLoader.ImportModule then
            local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestXP")
            if ok and type(module) == "table" and type(module.GetQuestLogRewardXP) == "function" then
                questXPModule = module
            end
        end
    end
    if not questXPModule then return nil end
    local ok, xp = pcall(questXPModule.GetQuestLogRewardXP, questXPModule, questId)
    if ok and type(xp) == "number" then return xp end
    return nil
end

-- Returns xp (number, 0 if unknown) and isEstimate (boolean).
function X:Get(questId)
    local cached = self.cache[questId]
    if cached then return cached, false end

    if GetQuestLogRewardXP then
        local ok, xp = pcall(GetQuestLogRewardXP, questId)
        if ok and type(xp) == "number" and not IsSecret(xp) and xp > 0 then
            self.cache[questId] = xp
            self.estimates[questId] = nil
            return xp, false
        end
    end
    Request(questId)

    local dj = ns.DungeonJournalSource.xp[questId]
    if dj then
        self.estimates[questId] = true
        return dj, true
    end
    local fdb = ns.ForeverDBSource:QuestXP(questId, UnitLevel("player"))
    if fdb then
        self.estimates[questId] = true
        return fdb, true
    end
    local estimate = QuestieEstimate(questId)
    self.estimates[questId] = true
    return estimate or 0, true
end

-- The server answered a load request: forget the old value so the next Get reads it.
function X:OnQuestDataLoaded(questId, success)
    if success and questId then
        self.cache[questId] = nil
        ns.RequestRefresh(2) -- many answers arrive together: one refresh for all
    end
end

function X.Format(value)
    value = math.floor((value or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    return tostring(value)
end
