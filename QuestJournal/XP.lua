-- Quest XP at your current level.
--   1. The game client (exact Forever numbers). Quests you don't have are loaded
--      first with C_QuestLog.RequestLoadQuestByID; the answer arrives with the
--      QUEST_DATA_LOAD_RESULT event and the journal redraws.
--   2. Questie's estimate (Classic numbers, lower than Forever's), marked "~".

local _, ns = ...

local X = { cache = {}, requested = {} }
ns.XP = X

local MAX_REQUESTS_PER_DRAW = 40
local RETRY_AFTER = 120
local requestsThisDraw = 0

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

function X:NewDraw() requestsThisDraw = 0 end
function X:Clear() wipe(self.cache) end

local function Request(questId)
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    if requestsThisDraw >= MAX_REQUESTS_PER_DRAW then return end
    local last = X.requested[questId]
    if last and GetTime() - last < RETRY_AFTER then return end
    X.requested[questId] = GetTime()
    requestsThisDraw = requestsThisDraw + 1
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

-- xp (0 if unknown), isEstimate
function X:Get(questId)
    local cached = self.cache[questId]
    if cached then return cached, false end
    if GetQuestLogRewardXP then
        local ok, xp = pcall(GetQuestLogRewardXP, questId)
        if ok and type(xp) == "number" and not IsSecret(xp) and xp > 0 then
            self.cache[questId] = xp
            return xp, false
        end
    end
    Request(questId)
    return QuestieEstimate(questId) or 0, true
end

function X:OnQuestDataLoaded(questId, success)
    if success and questId then
        self.cache[questId] = nil
        ns.RequestRefresh(1.5) -- many answers arrive together: one redraw for all
    end
end

function X.Format(value)
    value = math.floor((value or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    return tostring(value)
end
