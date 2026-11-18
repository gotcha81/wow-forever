-- Dungeon view: every quest of one dungeon, whether you have it, and if not,
-- what you are missing and where that starts. Also the optional check when you
-- enter a dungeon (Settings: "Check quests when entering a dungeon", off by default).

local _, ns = ...

local D = { stepsCache = {} }
ns.DungeonView = D

local TRIVIAL_LEADS_SHARE = 0.35 -- a grey quest shows only if what follows gives >= 35% of a level

-- Sort order of the states in the list.
local ORDER = { turnin = 1, progress = 2, pickup = 3, chain = 4, missing = 5, locked = 6, unavailable = 7, done = 8 }

---------------------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------------------

-- { { name =, min =, max =, quests = { ids } }, ... } sorted by level. Built once.
function D:Dungeons()
    if self.list then return self.list end
    local P, byName, list = ns.Planner, {}, {}
    for id, t in pairs(P.targets) do
        if t.kind == "dungeon" and t.dungeon then
            local d = byName[t.dungeon]
            if not d then
                d = { name = t.dungeon, quests = {} }
                byName[t.dungeon] = d
                list[#list + 1] = d
            end
            d.quests[#d.quests + 1] = id
            local level = P:QuestLevel(id)
            if level and level > 0 then
                d.min = math.min(d.min or level, level)
                d.max = math.max(d.max or level, level)
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.min or 999) ~= (b.min or 999) then return (a.min or 999) < (b.min or 999) end
        return a.name < b.name
    end)
    self.list, self.byName = list, byName
    return list
end

function D:Find(name)
    if not name then return nil end
    self:Dungeons()
    if self.byName[name] then return self.byName[name] end
    local lower = name:lower()
    for _, d in ipairs(self.list) do
        if d.name:lower() == lower then return d end
    end
    for _, d in ipairs(self.list) do
        if d.name:lower():find(lower, 1, true) then return d end
    end
end

-- The dungeon you are in right now (nil outside dungeons).
function D:Current()
    local inInstance, kind = IsInInstance()
    if not inInstance or kind ~= "party" then return nil end
    local name = GetInstanceInfo and GetInstanceInfo()
    local d = type(name) == "string" and self:Find(name)
    if d and d.name:lower() == name:lower() then return d end
    -- by map: the map you are on -> Questie's area id -> its dungeon
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    local area = ok and map and ns.QuestieSource:AreaForUiMap(map)
    local dungeon = area and ns.QuestieSource:Dungeons()[area]
    return dungeon and self:Find(dungeon.name) or d or nil
end

---------------------------------------------------------------------------------------
-- One quest
---------------------------------------------------------------------------------------

-- Steps up to and including this quest, in the order you do them.
local function ChainTo(questId)
    local cached = D.stepsCache[questId]
    if cached then return cached end
    local steps, alternatives = ns.Planner:BuildSteps(questId)
    cached = { steps = steps, alternatives = alternatives }
    D.stepsCache[questId] = cached
    return cached
end

-- The longest questline this quest is part of (for "step 3 of 12" and chain XP).
local function LongestLine(questId)
    local best
    for _, line in ipairs(ns.Planner.linesByQuest[questId] or {}) do
        if not best or #line.steps > #best.steps then best = line end
    end
    return best
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do if v == value then return i end end
end

-- Who or what starts a quest: "Name (NPC)", "an object", "an item"
local function StarterName(questId)
    local Q = ns.QuestieSource
    local starters = Q:Quest(questId, "startedBy")
    if type(starters) ~= "table" then return nil end
    local npc = starters[1] and starters[1][1]
    if npc then return Q:Npc(npc, "name") end
    local obj = starters[2] and starters[2][1]
    if obj then return Q:Object(obj, "name") end
    local item = starters[3] and starters[3][1]
    if item then return "item: " .. (Q:Item(item, "name") or ("#" .. item)) end
end

-- A stop the arrow can point at, placed at the nearest known point.
local function MakeStop(questId, state)
    local P = ns.Planner
    local xp, isEstimate = ns.XP:Get(questId)
    local stop = { questId = questId, state = state, name = P:QuestName(questId), level = P:QuestLevel(questId),
                   xp = xp, xpEstimate = isEstimate, lines = {}, external = true }
    P:Locate(stop)
    local px, py, instance = ns.Pos.Player()
    local best, bestDistance
    for _, point in ipairs(stop.points) do
        local d = px and (not instance or not point.instance or point.instance == instance)
            and ns.Pos.Distance(px, py, point.wx, point.wy)
        if d and (not bestDistance or d < bestDistance) then best, bestDistance = point, d end
    end
    stop.point = best or stop.points[1]
    return stop
end

-- Status of one dungeon quest. Returns a table, see the fields below.
function D:Entry(questId, level, levelXP)
    local P = ns.Planner
    local e = { questId = questId, name = P:QuestName(questId), level = P:QuestLevel(questId) }
    e.xp, e.xpEstimate = ns.XP:Get(questId)
    e.ignored = ns.Ignore:Hidden(questId)

    local chain = ChainTo(questId)
    local fakeLine = { alternatives = chain.alternatives }
    e.line = LongestLine(questId)

    -- the questline it belongs to: step number and XP still to get
    local line = e.line
    if line and #line.steps > 1 then
        e.lineIndex = IndexOf(line.steps, questId)
        local remaining, total, started = 0, 0, false
        for _, id in ipairs(line.steps) do
            local xp = ns.XP:Get(id)
            total = total + xp
            if P:StepDone(line, id) or P.InLog(id) then started = true end
            if not P:StepDone(line, id) then remaining = remaining + xp end
        end
        e.lineRemaining, e.lineTotal, e.lineStarted = remaining, total, started
    end

    if P:StepDone(fakeLine, questId) then
        e.state = "done"
        return e
    end
    if P.InLog(questId) then
        e.state = P.IsReadyToTurnIn(questId) and "turnin" or "progress"
        e.stop = MakeStop(questId, e.state)
        return e
    end

    -- first step of the chain to this quest you have not done
    local first, firstIndex
    for i, id in ipairs(chain.steps) do
        if not P:StepDone(fakeLine, id) then first, firstIndex = id, i; break end
    end
    first, firstIndex = first or questId, firstIndex or #chain.steps
    e.missingId, e.missingIndex, e.chainLength = first, firstIndex, #chain.steps
    e.missingName = P:QuestName(first)
    e.required = P:RequiredLevel(first)

    if first ~= questId and P.InLog(first) then
        e.state = "chain" -- you are on an earlier step
        e.stop = MakeStop(first, P.IsReadyToTurnIn(first) and "turnin" or "progress")
    elseif P.BlockedByExclusive(first) then
        e.state = "unavailable"
    elseif e.required > level then
        e.state = "locked"
    else
        e.state = (first == questId) and "pickup" or "missing"
        e.stop = MakeStop(first, "pickup")
        e.starter = StarterName(first)
    end

    -- Grey quests only show when what follows is worth it (>= 35% of a level,
    -- with at least one quest further on that is not grey).
    if P.IsTrivial(e.level, level) then
        local leadsOn, xpAfter = false, 0
        if line then
            local from = IndexOf(line.steps, first) or 1
            for i = from, #line.steps do
                local id = line.steps[i]
                if not P:StepDone(line, id) then
                    xpAfter = xpAfter + ns.XP:Get(id)
                    if not P.IsTrivial(P:QuestLevel(id), level) then leadsOn = true end
                end
            end
        end
        e.trivialHidden = not (leadsOn and levelXP > 0 and xpAfter / levelXP >= TRIVIAL_LEADS_SHARE)
    end
    return e
end

-- All quests of a dungeon: open (shown), done, ignored, and how many grey ones are hidden.
function D:Entries(name)
    local d = self:Find(name)
    local result = { open = {}, done = {}, ignored = {}, greyHidden = 0, dungeon = d }
    if not d then return result end
    local level = UnitLevel("player")
    local levelXP = UnitXPMax("player") or 0
    for _, id in ipairs(d.quests) do
        local e = self:Entry(id, level, levelXP)
        if e.state == "done" then
            result.done[#result.done + 1] = e
        elseif e.ignored then
            result.ignored[#result.ignored + 1] = e
        elseif e.trivialHidden then
            result.greyHidden = result.greyHidden + 1
        else
            result.open[#result.open + 1] = e
        end
    end
    local function Sort(a, b)
        if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.name < b.name
    end
    table.sort(result.open, Sort)
    table.sort(result.done, Sort)
    table.sort(result.ignored, Sort)
    return result
end

-- Open quests in a dungeon you can do something about right now: count for the picker.
function D:OpenCount(d)
    local level, count = UnitLevel("player"), 0
    local P = ns.Planner
    for _, id in ipairs(d.quests) do
        if not P.IsDone(id) and not ns.Ignore:Hidden(id) then
            if P.InLog(id) or (P:RequiredLevel(id) <= level and not P.IsTrivial(P:QuestLevel(id), level)) then
                count = count + 1
            end
        end
    end
    return count
end

-- Whether a stop picked in the dungeon view is still worth pointing at.
function D:StillValid(stop)
    local P = ns.Planner
    if P.IsDone(stop.questId) then return false end
    if stop.state == "pickup" then return not P.InLog(stop.questId) end
    if stop.state == "progress" then return P.InLog(stop.questId) and not P.IsReadyToTurnIn(stop.questId) end
    return P.InLog(stop.questId)
end

---------------------------------------------------------------------------------------
-- Entering a dungeon
---------------------------------------------------------------------------------------

local lastDungeon

function D:CheckEntered()
    if not ns.ready then return end
    local d = self:Current()
    if not d then lastDungeon = nil; return end
    if d.name == lastDungeon then return end -- once per visit
    lastDungeon = d.name
    ns.db.list.dungeon = d.name -- the dungeon view shows where you are
    ns.List:Update()
    if not ns.db.dungeonCheck then return end

    local missing = {}
    for _, e in ipairs(self:Entries(d.name).open) do
        if e.state == "pickup" or e.state == "missing" then missing[#missing + 1] = e end
    end
    if #missing == 0 then return end
    ns.Print(("|cffffd100%s:|r you don't have %d %s that end here:"):format(d.name, #missing,
        #missing == 1 and "quest" or "quests"))
    for _, e in ipairs(missing) do
        local text = "  - " .. e.name
        if e.state == "missing" then
            text = text .. (" (start with %s, step %d of %d)"):format(e.missingName, e.missingIndex, e.chainLength)
        end
        if e.starter then text = text .. " - starts at " .. e.starter end
        local zone = e.stop and e.stop.point and ns.Pos.MapName(e.stop.point.zone or e.stop.point.uiMapId)
        if zone then text = text .. ", " .. zone end
        print(text)
    end
    print("  Type /fqln d to see them.")
end
