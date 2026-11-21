-- Quest chains: built once at login (spread over frames), then sorted into
-- sections on every redraw.
--
-- A chain is 2+ linked quests in the order you do them, from the first quest to
-- a final quest that nothing follows. A quest with alternative prerequisites
-- ("do A or B first") takes one that fits the chain's faction; finishing the
-- other one also counts. Chains made only of dungeon quests are left out (this is
-- the open-world journal); dungeon steps inside a chain are marked.
--
-- Sections:
--   active     a quest of the chain is in your log, or you did part of it and the
--              next quest can be picked up now (and isn't grey)
--   completed  every quest of the chain is done
--   trivial    every quest of the chain is grey for you
--   zone:<n>   all other chains, by the zone of their first open-world quest

local _, ns = ...

local C = { lines = {}, byQuest = {}, count = 0 }
ns.Chains = C

local D -- ns.Data, set in Build
local MAX_DEPTH = 40
local KEY_ITEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Key) or 13

---------------------------------------------------------------------------------------
-- Game state
---------------------------------------------------------------------------------------

local completedSet, logSet

local function BuildCompletedSet()
    completedSet = nil
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(ids) == "table" then
            completedSet = {}
            for _, id in ipairs(ids) do completedSet[id] = true end
        end
    end
end

local function BuildLogSet()
    logSet = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return end
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID and info.questID > 0 then
            logSet[info.questID] = true
        end
    end
end

function C:ClearStateCache()
    completedSet = nil
end

local function IsDone(id)
    if completedSet then return completedSet[id] == true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    end
    return false
end

local function InLog(id)
    if logSet and next(logSet) then return logSet[id] == true end
    return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) ~= nil or false
end

local function IsReady(id)
    return C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and true or false
end

C.IsDone, C.InLog, C.IsReady = IsDone, InLog, IsReady

function C:QuestName(id)
    local name = D and D:Quest(id, "name")
    if not name and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok then name = title end
    end
    return name or ("Quest #" .. id)
end

local levelCache = {} -- quest levels never change; -1 (scales) is stored as false
function C:QuestLevel(id)
    local cached = levelCache[id]
    if cached == false then return UnitLevel("player"), true end
    if cached then return cached end
    local level = D and D:Quest(id, "questLevel")
    if type(level) ~= "number" and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local ok, l = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
        if ok then level = l end
    end
    if level == -1 then levelCache[id] = false; return UnitLevel("player"), true end -- scales with you
    level = type(level) == "number" and level > 0 and level or nil
    if level and D and D.questie then levelCache[id] = level end
    return level
end

function C:RequiredLevel(id)
    local level = D and D:Quest(id, "requiredLevel")
    return type(level) == "number" and level or 1
end

-- Grey, by the game's own colour rule.
function C.IsTrivial(level)
    if not level then return false end
    if GetQuestDifficultyColor and QuestDifficultyColors and QuestDifficultyColors.trivial then
        return GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
    end
    local range = (GetQuestGreenRange and GetQuestGreenRange("player")) or 8
    return level < UnitLevel("player") - range
end

---------------------------------------------------------------------------------------
-- Building (Questie data)
---------------------------------------------------------------------------------------

local function BuildFromQuestie()
    local classMask = D:PlayerClassMask()
    local band = bit.band
    local dungeons = D:Dungeons()

    -- 1. Reward items, and which quests give a key.
    local rewards, keyQuests = {}, {}
    local itemIds = D:AllItemIds()
    for i = 1, #itemIds do
        local itemId = itemIds[i]
        local quests = D:Item(itemId, "questRewards")
        if type(quests) == "table" and #quests > 0 then
            local isKey = D:Item(itemId, "class") == KEY_ITEM_CLASS
            for _, q in ipairs(quests) do
                local list = rewards[q]
                if not list then list = {}; rewards[q] = list end
                list[#list + 1] = itemId
                if isKey then keyQuests[q] = true end
            end
        end
        if i % 600 == 0 then coroutine.yield() end
    end

    -- 2. Quests, their faction, zone and prerequisites.
    local info, followers = {}, {}
    local ids = D:AllQuestIds()
    for i = 1, #ids do
        local id = ids[i]
        local classes = D:Quest(id, "requiredClasses")
        local classQuest = type(classes) == "number" and classes ~= 0
        if not classQuest or band(classes, classMask) ~= 0 then
            local zone = D:Quest(id, "zoneOrSort")
            if type(zone) ~= "number" then zone = 0 end
            local single = D:Quest(id, "preQuestSingle")
            local group = D:Quest(id, "preQuestGroup")
            info[id] = {
                side = D.SideOfRaces(D:Quest(id, "requiredRaces")),
                zone = zone,
                dungeon = zone > 0 and dungeons[zone] and dungeons[zone].name or nil,
                class = classQuest,
                single = type(single) == "table" and #single > 0 and single or nil,
                group = type(group) == "table" and #group > 0 and group or nil,
            }
        end
        if i % 500 == 0 then coroutine.yield() end
    end
    for id, q in pairs(info) do
        for _, list in ipairs({ q.single or {}, q.group or {} }) do
            for _, pre in ipairs(list) do
                if info[pre] then
                    local f = followers[pre]
                    if not f then f = {}; followers[pre] = f end
                    f[#f + 1] = id
                end
            end
        end
    end

    local function SideFits(side, lineSide)
        return side == "Both" or lineSide == "Both" or side == lineSide
    end

    -- Steps from the first quest to finalId, prerequisites first.
    local function Steps(finalId)
        local lineSide = info[finalId].side
        local steps, alternatives, seen = {}, {}, {}
        local function Visit(id, depth)
            if seen[id] or depth > MAX_DEPTH or not info[id] then return end
            seen[id] = true
            local q = info[id]
            if lineSide == "Both" and q.side ~= "Both" then lineSide = q.side end
            for _, pre in ipairs(q.group or {}) do Visit(pre, depth + 1) end
            if q.single then
                local pick
                for _, pre in ipairs(q.single) do
                    if info[pre] and SideFits(info[pre].side, lineSide) then pick = pre; break end
                end
                if pick then
                    if #q.single > 1 then alternatives[pick] = q.single end
                    Visit(pick, depth + 1)
                end
            end
            steps[#steps + 1] = id
        end
        Visit(finalId, 0)
        return steps, alternatives
    end

    -- 3. One chain per final quest (a linked quest nothing follows).
    local lines, n = {}, 0
    for id, q in pairs(info) do
        if not followers[id] and (q.single or q.group) then
            local steps, alternatives = Steps(id)
            if #steps >= 2 then
                local line = { id = id, steps = steps, alternatives = alternatives, side = "Both",
                               dungeonOf = {}, keyOf = {}, rewards = rewards }
                local openWorld = false
                for _, s in ipairs(steps) do
                    local si = info[s]
                    if line.side == "Both" and si.side ~= "Both" then line.side = si.side end
                    if si.dungeon then line.dungeonOf[s] = si.dungeon else openWorld = true end
                    if si.class then line.class = true end
                    if keyQuests[s] then line.hasKey = true; line.keyOf[s] = true end
                    if not line.zone and not si.dungeon and si.zone > 0 then line.zone = si.zone end
                end
                if openWorld then
                    if line.class then
                        line.group = "Class quests"
                    else
                        line.group = line.zone and D:AreaName(line.zone) or "Other"
                    end
                    lines[#lines + 1] = line
                end
            end
        end
        n = n + 1
        if n % 300 == 0 then coroutine.yield() end
    end
    return lines
end

---------------------------------------------------------------------------------------
-- Building (game client only, no Questie): the game's own questlines for quests
-- in your log, where the client has them.
---------------------------------------------------------------------------------------

local function BuildFromGame()
    local lines, seen = {}, {}
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) then return lines end
    BuildLogSet()
    for questId in pairs(logSet) do
        local ok, li = pcall(C_QuestLine.GetQuestLineInfo, questId)
        local lineId = ok and type(li) == "table" and li.questLineID
        if lineId and not seen[lineId] then
            seen[lineId] = true
            local ok2, quests = pcall(C_QuestLine.GetQuestLineQuests, lineId)
            if ok2 and type(quests) == "table" and #quests >= 2 then
                local steps = {}
                for i, id in ipairs(quests) do steps[i] = id end
                lines[#lines + 1] = { id = steps[#steps], steps = steps, alternatives = {}, side = "Both",
                                      dungeonOf = {}, keyOf = {}, rewards = {},
                                      name = li.questLineName, group = "Your quest log" }
            end
        end
    end
    return lines
end

function C:Build(onDone)
    D = ns.Data
    local co = coroutine.create(function()
        local lines = D.questie and BuildFromQuestie() or BuildFromGame()
        local byQuest = {}
        for _, line in ipairs(lines) do
            line.name = line.name or self:QuestName(line.id)
            for _, id in ipairs(line.steps) do
                local list = byQuest[id]
                if not list then list = {}; byQuest[id] = list end
                list[#list + 1] = line
            end
        end
        table.sort(lines, function(a, b) return a.name < b.name end)
        self.lines, self.byQuest, self.count = lines, byQuest, #lines
    end)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(f)
        local ok, err = coroutine.resume(co)
        if not ok then
            f:SetScript("OnUpdate", nil)
            ns.Print("|cffff5555could not build the quest chains:|r " .. tostring(err))
            ns.LogError("build", err, debugstack and debugstack(co) or "")
            onDone()
            return
        end
        if coroutine.status(co) == "dead" then
            f:SetScript("OnUpdate", nil)
            onDone()
        end
    end)
end

---------------------------------------------------------------------------------------
-- State and sections (every redraw)
---------------------------------------------------------------------------------------

function C:StepDone(line, id)
    if IsDone(id) then return true end
    local alts = line.alternatives[id]
    if alts then
        for _, alt in ipairs(alts) do
            if IsDone(alt) then return true end
        end
    end
    return false
end

-- Fills line.state = { done = {[i]=bool}, current = index, status = ..., started = bool }
function C:Evaluate(line, level)
    local st = line.state or {}
    line.state = st
    st.done = st.done or {}
    local current, started, anyInLog, allDone, allTrivial = nil, false, false, true, true
    local minL, maxL
    for i, id in ipairs(line.steps) do
        local done = self:StepDone(line, id)
        st.done[i] = done
        if done then started = true else allDone = false end
        if InLog(id) then anyInLog = true; started = true end
        if not done and not current then current = i end
        local l = self:QuestLevel(id)
        if l then
            minL = (not minL or l < minL) and l or minL
            maxL = (not maxL or l > maxL) and l or maxL
        end
        if not self.IsTrivial(l) then allTrivial = false end
    end
    st.current = current or #line.steps
    st.started = started
    st.minLevel, st.maxLevel = minL, maxL
    if allDone then
        st.status = "completed"
    elseif anyInLog then
        st.status = "active"
    elseif started and self:RequiredLevel(line.steps[st.current]) <= level
        and not self.IsTrivial(self:QuestLevel(line.steps[st.current])) then
        st.status = "active"
    elseif allTrivial then
        st.status = "trivial"
    else
        st.status = "open"
    end
    return st
end

local function FactionAllows(side)
    local f = ns.db.faction
    if f == "Both" or side == "Both" then return true end
    if f == "mine" then f = UnitFactionGroup("player") end
    return side == f
end
C.FactionAllows = FactionAllows

-- { active = {lines}, completed = {...}, trivial = {...}, zones = { [name] = {lines} } }
function C:Sections()
    BuildCompletedSet()
    BuildLogSet()
    local level = UnitLevel("player")
    local out = { active = {}, completed = {}, trivial = {}, zones = {} }
    for _, line in ipairs(self.lines) do
        local st = self:Evaluate(line, level)
        -- your own chains always show; the faction filter is for browsing
        if st.status == "active" or st.status == "completed" or FactionAllows(line.side) then
            if st.status == "open" then
                local list = out.zones[line.group]
                if not list then list = {}; out.zones[line.group] = list end
                list[#list + 1] = line
            else
                table.insert(out[st.status], line)
            end
        end
    end
    return out
end

-- XP of one step and the chain: total, left (not done), estimate flag.
function C:ChainXP(line)
    local total, left, estimate = 0, 0, false
    for i, id in ipairs(line.steps) do
        local xp, est = ns.XP:Get(id)
        total = total + xp
        if not (line.state and line.state.done[i]) then left = left + xp end
        if est then estimate = true end
    end
    return total, left, estimate
end

-- Reward item IDs of a quest (Questie data).
function C:RewardItems(line, id)
    return line.rewards and line.rewards[id] or nil
end
