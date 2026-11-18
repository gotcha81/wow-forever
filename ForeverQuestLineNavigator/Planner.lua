-- Planner
--
-- 1. Catalog (once at login): every quest your race/class can do is scanned in
--    QuestieDB. Dungeon quests and class quests are "seeds".
-- 2. Questlines: from each seed we walk FORWARD (which quests does it unlock) to the
--    end of the line, then BACKWARD from that end through all prerequisites. A line
--    can cross several dungeons; it is split into parts, one per dungeon.
-- 3. Update (on every quest/level/zone event): for each line, what is done, what can
--    be done now, how much XP is left, and whether it is trivial (grey).
-- 4. Route: stops are picked by value = XP (plus what the step unlocks further down
--    the line) per second of estimated travel, starting from where you stand.

local _, ns = ...

local band = bit.band

local P = {
    targets = {},      -- [questId] = { kind = "dungeon"|"class", dungeon = name|nil }
    followers = {},    -- [questId] = { quests that need it }
    worldByZone = {},  -- [areaId] = { questId, ... } open-world quests (dungeon focus off)
    lines = {},        -- questlines, see BuildLine
    route = {},        -- ordered stops (numbered on the map, #1 gets the arrow)
    unlocated = {},    -- stops we cannot place on the map
    upcoming = {},     -- steps that unlock within a few levels
    notWorth = {},     -- stops that are too far away for what they give
    trivial = {},      -- lines that are grey and lead nowhere good
    catalogCount = 0,
}
ns.Planner = P

local Q -- ns.QuestieSource

-- Tuning (kept here so they are easy to find and change)
local LEAD_IN_XP_SHARE  = 0.35 -- a grey lead-in must give >= 35% of your current level in total
local DOWNSTREAM_WEIGHT = 0.5  -- how much XP further down a line counts when choosing the next stop
local STOP_OVERHEAD     = 30   -- seconds spent at a stop (talking, looting) in the travel estimate
local NOT_WORTH_SHARE   = 0.15 -- a new pickup worth < 15% of the best stop's value is "not worth it"
local LEAD_IN_WORTH     = 0.35 -- a grey lead-in pickup must reach 35% of the best stop's value
local OTHER_CONTINENT   = 600  -- seconds, rough estimate when "Travel time" is off
local CROSSING_TIME     = 120  -- seconds on board a boat / zeppelin
local RUN_SPEED         = 7    -- yards per second on foot
-- Priority multipliers on a stop's value (higher = earlier on the route)
local PRIORITY_RECOMMENDED = 3   -- questline step for a dungeon you are recommended now
local PRIORITY_QUESTLINE   = 2   -- other dungeon / class questline steps
local PRIORITY_IN_LOG      = 1.5 -- other quests already in your log (finish them)
local PRIORITY_WORLD       = 1   -- other quests you can pick up here

---------------------------------------------------------------------------------------
-- Game state helpers
---------------------------------------------------------------------------------------

local function IsDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(id) or false
end

local function InLog(id)
    return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) ~= nil or false
end

local function IsReadyToTurnIn(id)
    return C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and true or false
end

-- Grey, using the game's own colour rule for quest difficulty.
local function IsTrivial(questLevel, playerLevel)
    if not questLevel or questLevel <= 0 then return false end
    if GetQuestDifficultyColor and QuestDifficultyColors and QuestDifficultyColors.trivial then
        return GetQuestDifficultyColor(questLevel) == QuestDifficultyColors.trivial
    end
    local range = (GetQuestGreenRange and GetQuestGreenRange("player")) or 8
    return questLevel < playerLevel - range
end
P.IsTrivial = IsTrivial

function P:QuestName(id)
    local name = Q:Quest(id, "name")
    if not name and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        name = C_QuestLog.GetTitleForQuestID(id)
    end
    if not name then
        local dj = ns.DungeonJournalSource.quests[id]
        name = dj and dj.name
    end
    return name or ("Quest #" .. id)
end

function P:QuestLevel(id)
    local level = Q:Quest(id, "questLevel")
    if type(level) ~= "number" then
        local dj = ns.DungeonJournalSource.quests[id]
        level = dj and dj.level
    end
    if level == -1 then level = UnitLevel("player") end
    return type(level) == "number" and level or nil
end

function P:RequiredLevel(id)
    local level = Q:Quest(id, "requiredLevel")
    if type(level) ~= "number" then
        local dj = ns.DungeonJournalSource.quests[id]
        level = dj and dj.requires
    end
    return type(level) == "number" and level or 1
end

local function PrereqsDone(id)
    local group = Q:Quest(id, "preQuestGroup")
    if type(group) == "table" then
        for _, pre in ipairs(group) do
            if not IsDone(pre) then return false end
        end
    end
    local single = Q:Quest(id, "preQuestSingle")
    if type(single) == "table" and #single > 0 then
        for _, pre in ipairs(single) do
            if IsDone(pre) then return true end
        end
        return false
    end
    return true
end

local function BlockedByExclusive(id)
    local exclusive = Q:Quest(id, "exclusiveTo")
    if type(exclusive) == "table" then
        for _, other in ipairs(exclusive) do
            if IsDone(other) or InLog(other) then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------------------
-- Catalog and questlines (once at login, spread over frames)
---------------------------------------------------------------------------------------

local MAX_ENDS_PER_SEED = 8
local MAX_FORWARD_NODES = 200

function P:ForwardEnds(seed)
    local followers, hidden = self.followers, ns.Overrides.hiddenQuests
    local ends, seen, count = {}, {}, 0
    local function Walk(id, depth)
        if seen[id] or count >= MAX_FORWARD_NODES or #ends >= MAX_ENDS_PER_SEED then return end
        seen[id] = true
        count = count + 1
        local any = false
        if depth < 30 then
            for _, nextId in ipairs(followers[id] or {}) do
                if not hidden[nextId] then
                    any = true
                    Walk(nextId, depth + 1)
                end
            end
        end
        if not any then ends[#ends + 1] = id end
    end
    Walk(seed, 0)
    return ends, seen
end

-- Steps from the first quest to `finalId`, in the order you do them.
-- `prefer` = quests to choose when a step has alternative prerequisites.
function P:BuildSteps(finalId, prefer)
    local fixed = ns.Overrides.chains[finalId] or ns.DungeonJournalSource.chains[finalId]
    local steps, alternatives = {}, {}
    if fixed then
        for i, id in ipairs(fixed) do steps[i] = id end
        steps[#steps + 1] = finalId
        return steps, alternatives
    end
    local seen = {}
    local function Visit(id, depth)
        if seen[id] or depth > 30 then return end
        seen[id] = true
        local group = Q:Quest(id, "preQuestGroup")
        if type(group) == "table" then
            for _, pre in ipairs(group) do Visit(pre, depth + 1) end
        end
        local single = Q:Quest(id, "preQuestSingle")
        if type(single) == "table" and #single > 0 then
            local pick
            for _, pre in ipairs(single) do
                if prefer and prefer[pre] then pick = pre; break end
            end
            if not pick then
                for _, pre in ipairs(single) do
                    if self.RaceOk(pre) then pick = pre; break end
                end
            end
            if pick then
                if #single > 1 then alternatives[pick] = single end
                Visit(pick, depth + 1)
            end
        end
        steps[#steps + 1] = id
    end
    Visit(finalId, 0)
    return steps, alternatives
end

function P:BuildLine(finalId, prefer)
    local steps, alternatives = self:BuildSteps(finalId, prefer)
    local line = { id = finalId, steps = steps, alternatives = alternatives, dungeonOf = {}, partOf = {}, parts = {} }
    local hasDungeon = false
    for _, id in ipairs(steps) do
        local t = self.targets[id]
        if t and t.kind == "dungeon" then
            line.dungeonOf[id] = t.dungeon
            hasDungeon = true
        end
    end
    line.kind = hasDungeon and "dungeon" or "class"

    -- Parts: every step belongs to the next dungeon on the line (steps after the
    -- last dungeon belong to the last one). One part per dungeon in a row.
    local partDungeon, nextDungeon = {}, nil
    for i = #steps, 1, -1 do
        nextDungeon = line.dungeonOf[steps[i]] or nextDungeon
        partDungeon[i] = nextDungeon
    end
    local lastDungeon
    for i = 1, #steps do
        if not partDungeon[i] then partDungeon[i] = lastDungeon end
        lastDungeon = partDungeon[i] or lastDungeon
        local current = line.parts[#line.parts]
        if not current or current.dungeon ~= partDungeon[i] then
            current = { dungeon = partDungeon[i], first = i, last = i }
            line.parts[#line.parts + 1] = current
        else
            current.last = i
        end
        line.partOf[steps[i]] = #line.parts
    end
    return line
end

function P:BuildCatalog(onDone)
    Q = ns.QuestieSource
    local O = ns.Overrides
    local raceMask, classMask = Q:PlayerMasks()
    local dungeons = Q:Dungeons()
    local ids = Q:AllQuestIds()
    local targets, world, followers = {}, {}, {}
    local faction = UnitFactionGroup("player")

    local function RaceOk(id)
        local races = Q:Quest(id, "requiredRaces")
        return type(races) ~= "number" or races == 0 or band(races, raceMask) ~= 0
    end
    local function ClassOk(id)
        local classes = Q:Quest(id, "requiredClasses")
        return type(classes) ~= "number" or classes == 0 or band(classes, classMask) ~= 0
    end
    self.RaceOk = RaceOk

    local function AddFollower(pre, id)
        local list = followers[pre]
        if not list then list = {}; followers[pre] = list end
        list[#list + 1] = id
    end

    local function Scan()
        for index = 1, #ids do
            local id = ids[index]
            if not O.hiddenQuests[id] and RaceOk(id) and ClassOk(id) then
                local classes = Q:Quest(id, "requiredClasses")
                if type(classes) ~= "number" then classes = nil end
                local zone = Q:Quest(id, "zoneOrSort")
                if type(zone) ~= "number" then zone = nil end
                local dungeon = zone and zone > 0 and dungeons[zone] or nil
                local extra = O.extraDungeonQuests[id]
                if extra then dungeon = dungeons[extra] or { name = "Dungeon", areaId = extra } end
                if dungeon and not O.notDungeons[dungeon.areaId] then
                    targets[id] = { kind = "dungeon", dungeon = dungeon.name }
                elseif classes and classes ~= 0 then
                    targets[id] = { kind = "class" }
                elseif zone and zone > 0 then
                    local list = world[zone]
                    if not list then list = {}; world[zone] = list end
                    list[#list + 1] = id
                end
                for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
                    local pres = Q:Quest(id, key)
                    if type(pres) == "table" then
                        for _, pre in ipairs(pres) do AddFollower(pre, id) end
                    end
                end
            end
            if index % 400 == 0 then coroutine.yield() end
        end

        -- DungeonJournal: hand-checked Forever dungeon quests (only while it is installed).
        for id, info in pairs(ns.DungeonJournalSource.quests) do
            local sideOk = info.faction == "Both" or info.faction == faction
            local known = not Q.lib.Quest.Exists or Q.lib.Quest.Exists(id)
            if sideOk and not O.hiddenQuests[id] and (not known or (RaceOk(id) and ClassOk(id))) then
                local t = targets[id]
                if not t or t.kind ~= "dungeon" then
                    targets[id] = { kind = "dungeon", dungeon = info.dungeon }
                end
            end
        end
        -- DungeonJournal chains also say who follows whom.
        for finalId, chain in pairs(ns.DungeonJournalSource.chains) do
            local previous
            for _, id in ipairs(chain) do
                if previous then AddFollower(previous, id) end
                previous = id
            end
            if previous then AddFollower(previous, finalId) end
        end

        self.targets, self.worldByZone, self.followers = targets, world, followers

        -- Questlines, one per end quest.
        local lines, byFinal, processed = {}, {}, 0
        for seed in pairs(targets) do
            local ends, prefer = self:ForwardEnds(seed)
            for _, finalId in ipairs(ends) do
                if not byFinal[finalId] then
                    local line = self:BuildLine(finalId, prefer)
                    byFinal[finalId] = line
                    lines[#lines + 1] = line
                end
            end
            processed = processed + 1
            if processed % 40 == 0 then coroutine.yield() end
        end
        -- Drop lines that are just the start of a longer line.
        local inner = {}
        for _, line in ipairs(lines) do
            for i = 1, #line.steps - 1 do inner[line.steps[i]] = true end
        end
        local kept = {}
        for _, line in ipairs(lines) do
            if not inner[line.id] then kept[#kept + 1] = line end
        end
        self.lines = kept
    end

    local co = coroutine.create(Scan)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(f)
        local ok, err = coroutine.resume(co)
        if not ok then
            f:SetScript("OnUpdate", nil)
            ns.Print("|cffff5555could not read QuestieDB:|r " .. tostring(err))
            ns.LogError("catalog", err, debugstack and debugstack(co) or "")
            return
        end
        if coroutine.status(co) == "dead" then
            f:SetScript("OnUpdate", nil)
            self.catalogCount = #self.lines
            onDone()
        end
    end)
end

---------------------------------------------------------------------------------------
-- Where to go for a stop
---------------------------------------------------------------------------------------

local MAX_DROP_SOURCES = 6

local function AddPoints(out, kind, id, note)
    for _, p in ipairs(Q:Points(kind, id)) do
        -- same coordinate frame as the player's position (UnitPosition)
        local wx, wy, instance = ns.Pos.World(p[1], p[2], p[3])
        if wx then
            out[#out + 1] = { uiMapId = p[1], x = p[2], y = p[3], areaId = p[4], inside = p.inside,
                              zone = ns.Pos.Zone(p[1]), wx = wx, wy = wy, instance = instance, note = note }
        end
    end
end

local function FinishedObjectives(questId)
    local finished = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local objectives = C_QuestLog.GetQuestObjectives(questId)
        if type(objectives) == "table" then
            for i, o in ipairs(objectives) do
                if o.finished then finished[i] = true end
            end
        end
    end
    return finished
end

local function AddItemSources(points, itemId, note)
    local drops = Q:Item(itemId, "npcDrops") or {}
    for i = 1, math.min(#drops, MAX_DROP_SOURCES) do AddPoints(points, "npc", drops[i], note) end
    local objectDrops = Q:Item(itemId, "objectDrops") or {}
    for i = 1, math.min(#objectDrops, MAX_DROP_SOURCES) do AddPoints(points, "object", objectDrops[i], note) end
end

function P:Locate(stop)
    local points = {}
    local id = stop.questId
    if stop.state == "pickup" then
        local starters = Q:Quest(id, "startedBy")
        if type(starters) == "table" then
            for _, npc in ipairs(starters[1] or {}) do AddPoints(points, "npc", npc) end
            for _, obj in ipairs(starters[2] or {}) do AddPoints(points, "object", obj) end
            for _, item in ipairs(starters[3] or {}) do
                AddItemSources(points, item, "drops the item that starts this quest")
                stop.startItem = stop.startItem or Q:Item(item, "name") or ("item #" .. item)
            end
        end
    elseif stop.state == "turnin" then
        local finishers = Q:Quest(id, "finishedBy")
        if type(finishers) == "table" then
            for _, npc in ipairs(finishers[1] or {}) do AddPoints(points, "npc", npc) end
            for _, obj in ipairs(finishers[2] or {}) do AddPoints(points, "object", obj) end
        end
    else -- "progress": where the quest mobs, objects and item drops are
        local objectives = Q:Quest(id, "objectives")
        if type(objectives) == "table" then
            local finished, index = FinishedObjectives(id), 0
            for _, o in ipairs(objectives[1] or {}) do
                index = index + 1
                if not finished[index] then AddPoints(points, "npc", o[1], "quest mob") end
            end
            for _, o in ipairs(objectives[2] or {}) do
                index = index + 1
                if not finished[index] then AddPoints(points, "object", o[1], "quest object") end
            end
            for _, o in ipairs(objectives[3] or {}) do
                index = index + 1
                if not finished[index] then AddItemSources(points, o[1], "drops a quest item") end
            end
        end
    end
    stop.points = points
end

---------------------------------------------------------------------------------------
-- Riding and travel time
---------------------------------------------------------------------------------------

local function Known(spellId)
    return (IsPlayerSpell and IsPlayerSpell(spellId)) or (IsSpellKnown and IsSpellKnown(spellId)) or false
end

local ridingCache = { time = -100 }

-- Riding speed bonus in percent (0, 60 or 100) and how it was found.
function P:Riding()
    local mode = ns.db.riding
    if mode == "none" then return 0, "set to none" end
    if mode == "60" then return 60, "set to 60%" end
    if mode == "100" then return 100, "set to 100%" end
    if GetTime() - ridingCache.time < 30 then return ridingCache.speed, ridingCache.how end
    local speed, how = self:DetectRiding()
    ridingCache.time, ridingCache.speed, ridingCache.how = GetTime(), speed, how
    return speed, how
end

function P:DetectRiding()
    if Known(33391) or Known(34090) or Known(34091) or Known(90265) then return 100, "detected" end
    if Known(33388) then return 60, "detected" end
    if C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID then
        local ok, mountIds = pcall(C_MountJournal.GetMountIDs)
        if ok and type(mountIds) == "table" then
            for _, mountId in ipairs(mountIds) do
                local _, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountId)
                if isCollected and isUsable then return 60, "detected (usable mount)" end
            end
        end
    end
    return 0, "detected (no riding)"
end

-- Estimated seconds to get from (x, y, instance) to a point.
function P:TravelSeconds(fromX, fromY, fromInstance, point, speed)
    if not fromX then return STOP_OVERHEAD end
    if fromInstance and point.instance and point.instance ~= fromInstance then
        local crossing = ns.db.travelTime and (ns.db.boatWait + CROSSING_TIME) or OTHER_CONTINENT
        return crossing + STOP_OVERHEAD
    end
    local dx, dy = point.wx - fromX, point.wy - fromY
    return math.sqrt(dx * dx + dy * dy) / speed + STOP_OVERHEAD
end

---------------------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------------------

function P:StepDone(line, id)
    if IsDone(id) then return true end
    local alts = line.alternatives[id]
    if alts then
        for _, alt in ipairs(alts) do
            if IsDone(alt) then return true end
        end
    end
    return false
end

-- Cheap pre-check: false for finished lines and lines whose next step is
-- still far above your level (they are not evaluated or asked about).
function P:InReach(line, level)
    for _, id in ipairs(line.steps) do
        if not self:StepDone(line, id) then
            return InLog(id) or self:RequiredLevel(id) <= level + ns.db.levelAhead
        end
    end
    return false
end

-- Evaluates one line for the current character. Fills line.eval.
function P:EvaluateLine(line, level, levelXP)
    local db = ns.db
    local eval = { remaining = 0, done = 0, xpRemaining = 0, xpTotal = 0, xpReach = 0,
                   actionable = {}, locked = {}, started = false, estimate = false }
    line.eval = eval
    local nonTrivialLeft = false
    for index, id in ipairs(line.steps) do
        local xp, isEstimate = ns.XP:Get(id)
        eval.xpTotal = eval.xpTotal + xp
        if isEstimate then eval.estimate = true end
        if self:StepDone(line, id) then
            eval.done = eval.done + 1
            eval.started = true
        else
            eval.remaining = eval.remaining + 1
            eval.xpRemaining = eval.xpRemaining + xp
            local required = self:RequiredLevel(id)
            if required <= level + db.levelAhead then eval.xpReach = eval.xpReach + xp end
            if not IsTrivial(self:QuestLevel(id), level) then nonTrivialLeft = true end
            if InLog(id) then
                eval.started = true
                eval.actionable[#eval.actionable + 1] = { id = id, index = index,
                    state = IsReadyToTurnIn(id) and "turnin" or "progress" }
            elseif PrereqsDone(id) and not BlockedByExclusive(id) then
                if required <= level then
                    eval.actionable[#eval.actionable + 1] = { id = id, index = index, state = "pickup" }
                else
                    eval.locked[#eval.locked + 1] = { id = id, index = index, required = required }
                end
            end
        end
    end
    eval.xpShare = levelXP > 0 and eval.xpRemaining / levelXP or 0

    if eval.remaining == 0 then
        eval.status = "complete"
    elseif not nonTrivialLeft then
        eval.status = "trivial"
        eval.reason = "grey and does not lead to a non-grey quest"
    else
        local allTrivialNow = #eval.actionable > 0
        for _, a in ipairs(eval.actionable) do
            if not IsTrivial(self:QuestLevel(a.id), level) or a.state ~= "pickup" then allTrivialNow = false end
        end
        if allTrivialNow then
            if eval.xpShare >= LEAD_IN_XP_SHARE then
                eval.status = "leadin"
            else
                eval.status = "trivial"
                eval.reason = ("grey start, the whole line gives only %d%% of a level"):format(eval.xpShare * 100)
            end
        else
            eval.status = "active"
        end
    end
    return eval
end

function P:Update()
    local db = ns.db
    local level = UnitLevel("player")
    local levelXP = UnitXPMax("player") or 0
    ns.XP:NewPass()

    local stops, byKey, upcoming, upcomingSeen, trivial = {}, {}, {}, {}, {}

    local function AddStop(id, state, line, index)
        local key = id .. ":" .. state
        local stop = byKey[key]
        if not stop then
            local xp, isEstimate = ns.XP:Get(id)
            stop = { questId = id, state = state, lines = {}, name = self:QuestName(id),
                     level = self:QuestLevel(id), xp = xp, xpEstimate = isEstimate }
            stop.trivial = IsTrivial(stop.level, level)
            byKey[key] = stop
            stops[#stops + 1] = stop
        end
        if line then stop.lines[#stop.lines + 1] = { line = line, index = index } end
        return stop
    end

    for _, line in ipairs(self.lines) do
        line.eval = nil -- no stale results from an earlier update
        if (line.kind == "dungeon" or db.classQuests) and self:InReach(line, level) then
            local eval = self:EvaluateLine(line, level, levelXP)
            if eval.status == "trivial" then
                if eval.remaining > 0 and #eval.actionable > 0 then trivial[#trivial + 1] = line end
            elseif eval.status ~= "complete" then
                for _, a in ipairs(eval.actionable) do AddStop(a.id, a.state, line, a.index) end
                if #eval.actionable == 0 then
                    for _, l in ipairs(eval.locked) do
                        if l.required <= level + db.levelAhead and not upcomingSeen[l.id] then
                            upcomingSeen[l.id] = true
                            upcoming[#upcoming + 1] = { questId = l.id, required = l.required, line = line,
                                index = l.index, name = self:QuestName(l.id) }
                        end
                    end
                end
            end
        end
    end

    for _, stop in ipairs(stops) do self:Locate(stop) end

    -- Where you are.
    local px, py, pInstance = ns.Pos.Player()
    if px then
        self.lastPos = { px, py, pInstance }
    elseif self.lastPos then
        px, py, pInstance = self.lastPos[1], self.lastPos[2], self.lastPos[3]
    end
    local hereZone = ns.Pos.PlayerZone() or self.lastZone
    self.lastZone = hereZone

    -- Finish here: every quest in your log (not only questlines), and new
    -- non-grey quests you can pick up in the zone you are in.
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            local id = info and not info.isHeader and info.questID
            if id and id > 0 then
                local state = IsReadyToTurnIn(id) and "turnin" or "progress"
                if not byKey[id .. ":" .. state] then
                    local stop = AddStop(id, state, nil, nil)
                    stop.world = true
                    self:Locate(stop)
                end
            end
        end
    end
    local zonesToFill = {}
    local hereArea = hereZone and Q:AreaForUiMap(hereZone)
    if hereArea then zonesToFill[hereArea] = true end
    if not db.dungeonFocus then
        for _, stop in ipairs(stops) do
            for _, p in ipairs(stop.points) do zonesToFill[p.areaId] = true end
        end
    end
    for zone in pairs(zonesToFill) do
        for _, id in ipairs(self.worldByZone[zone] or {}) do
            if not IsDone(id) and not InLog(id) and not byKey[id .. ":pickup"]
                and not IsTrivial(self:QuestLevel(id), level) and self:RequiredLevel(id) <= level then
                local flags = Q:Quest(id, "specialFlags")
                if type(flags) ~= "number" then flags = 0 end
                if band(flags, 1) == 0 and PrereqsDone(id) and not BlockedByExclusive(id)
                    and not Q:Quest(id, "requiredSkill") then
                    local stop = AddStop(id, "pickup", nil, nil)
                    stop.world = true
                    self:Locate(stop)
                end
            end
        end
    end

    -- Dungeons you are recommended now: a non-grey dungeon quest within reach.
    local recommended = {}
    for _, line in ipairs(self.lines) do
        local eval = line.eval
        if eval and (eval.status == "active" or eval.status == "leadin") then
            for _, id in ipairs(line.steps) do
                local dungeon = line.dungeonOf[id]
                if dungeon and not self:StepDone(line, id) then
                    if not IsTrivial(self:QuestLevel(id), level) and self:RequiredLevel(id) <= level + db.levelAhead then
                        recommended[dungeon] = true
                    end
                end
            end
        end
    end
    self.recommended = recommended

    -- Primary line, dungeon and priority of each stop.
    for _, stop in ipairs(stops) do
        local best
        for _, entry in ipairs(stop.lines) do
            if not best or entry.line.eval.xpRemaining > best.line.eval.xpRemaining then best = entry end
        end
        stop.primary = best
        stop.leadIn = best and best.line.eval.status == "leadin" or false
        if best then
            local part = best.line.parts[best.line.partOf[stop.questId] or 1]
            stop.dungeon = part and part.dungeon
        end
        if stop.dungeon and recommended[stop.dungeon] then
            stop.priority = PRIORITY_RECOMMENDED
        elseif best then
            stop.priority = PRIORITY_QUESTLINE
        elseif stop.state ~= "pickup" then
            stop.priority = PRIORITY_IN_LOG
        else
            stop.priority = PRIORITY_WORLD
        end
        stop.here = false
        for _, point in ipairs(stop.points) do
            if hereZone and point.zone == hereZone then stop.here = true; break end
        end
    end

    local speed = RUN_SPEED * (1 + self:Riding() / 100)

    -- Value of a stop from a position; zone = only consider points in that zone.
    local function Value(stop, fromX, fromY, fromInstance, opened, zone)
        local bestPoint, bestTime
        for _, point in ipairs(stop.points) do
            if not zone or point.zone == zone then
                local t = self:TravelSeconds(fromX, fromY, fromInstance, point, speed)
                if not bestTime or t < bestTime then bestPoint, bestTime = point, t end
            end
        end
        if not bestPoint then return nil end
        local gain = stop.xp
        for _, entry in ipairs(stop.lines) do
            if not opened[entry.line] then
                gain = gain + math.max(0, entry.line.eval.xpReach - stop.xp) * DOWNSTREAM_WEIGHT
            end
        end
        return gain * stop.priority / bestTime, bestPoint, bestTime
    end

    local candidates, unlocated, notWorth = {}, {}, {}
    local bestValue = 0
    for _, stop in ipairs(stops) do
        if #stop.points == 0 then
            if not stop.world or stop.state ~= "pickup" then unlocated[#unlocated + 1] = stop end
        else
            stop.value = Value(stop, px, py, pInstance, {}) or 0
            if not stop.here and stop.value > bestValue then bestValue = stop.value end
            candidates[#candidates + 1] = stop
        end
    end
    -- New pickups elsewhere that are far away for what they give stay off the route.
    -- Everything in the zone you are in stays on it.
    local remaining = {}
    for _, stop in ipairs(candidates) do
        local limit = stop.leadIn and LEAD_IN_WORTH or NOT_WORTH_SHARE
        if not stop.here and stop.state == "pickup" and bestValue > 0 and stop.value < bestValue * limit then
            stop.reason = stop.leadIn and "grey start that does not fit your route"
                or "far away for the XP it gives"
            notWorth[#notWorth + 1] = stop
        else
            remaining[#remaining + 1] = stop
        end
    end

    -- Zone by zone: finish the zone you are in, then go where the value is
    -- highest and finish that zone, and so on.
    local route, opened = {}, {}
    local cx, cy, cInstance, currentZone = px, py, pInstance, hereZone
    while #remaining > 0 and #route < db.maxStops do
        local top, bestStop, bestPoint, bestIndex, bestTime
        if currentZone then
            for i, stop in ipairs(remaining) do
                local value, point, seconds = Value(stop, cx, cy, cInstance, opened, currentZone)
                if value and (not top or value > top) then
                    top, bestStop, bestPoint, bestIndex, bestTime = value, stop, point, i, seconds
                end
            end
        end
        if not bestStop then
            for i, stop in ipairs(remaining) do
                local value, point, seconds = Value(stop, cx, cy, cInstance, opened)
                if value and (not top or value > top) then
                    top, bestStop, bestPoint, bestIndex, bestTime = value, stop, point, i, seconds
                end
            end
            if not bestStop then break end
            currentZone = bestPoint.zone
        end
        bestStop.point, bestStop.seconds = bestPoint, bestTime
        route[#route + 1] = bestStop
        table.remove(remaining, bestIndex)
        for _, entry in ipairs(bestStop.lines) do opened[entry.line] = true end
        cx, cy, cInstance = bestPoint.wx, bestPoint.wy, bestPoint.instance
    end
    for _, stop in ipairs(remaining) do unlocated[#unlocated + 1] = stop end

    table.sort(upcoming, function(a, b) return a.required < b.required end)
    table.sort(notWorth, function(a, b) return (a.value or 0) > (b.value or 0) end)
    table.sort(trivial, function(a, b) return a.eval.xpRemaining > b.eval.xpRemaining end)
    self.route, self.unlocated, self.upcoming, self.notWorth, self.trivial = route, unlocated, upcoming, notWorth, trivial
end

---------------------------------------------------------------------------------------
-- Text helpers for the interface
---------------------------------------------------------------------------------------

function P:DistanceTo(stop)
    if not stop or not stop.point then return nil end
    local px, py, instance = ns.Pos.Player()
    if not px or (instance and stop.point.instance and instance ~= stop.point.instance) then return nil end
    return ns.Pos.Distance(px, py, stop.point.wx, stop.point.wy)
end

-- "Final quest (Last dungeon)", e.g. "Leaders of the Fang (Wailing Caverns)"
function P:LineName(line)
    local name = self:QuestName(line.id)
    local last = line.parts[#line.parts]
    if last and last.dungeon then name = name .. " (" .. last.dungeon .. ")" end
    return name
end

-- "Step 3 of 12 · Part 2 of 3 (Razorfen Downs)"
function P:StepText(line, index)
    local text = ("Step %d of %d"):format(index, #line.steps)
    if #line.parts > 1 then
        local partIndex = line.partOf[line.steps[index]] or 1
        local part = line.parts[partIndex]
        text = text .. ("  ·  Part %d of %d%s"):format(partIndex, #line.parts,
            part and part.dungeon and (" (" .. part.dungeon .. ")") or "")
    end
    return text
end

-- "XP quest 5,600 (Questchain remaining 34,400)" / "(Total questchain 87,100)"
function P:XPText(stop)
    local fmt = ns.XP.Format
    local mark = stop.xpEstimate and "~" or ""
    local text = "XP quest " .. mark .. fmt(stop.xp)
    local entry = stop.primary
    if entry and #entry.line.steps > 1 then
        local eval = entry.line.eval
        local lineMark = eval.estimate and "~" or ""
        if eval.started then
            text = text .. (" (Questchain remaining %s%s)"):format(lineMark, fmt(eval.xpRemaining))
        else
            text = text .. (" (Total questchain %s%s)"):format(lineMark, fmt(eval.xpTotal))
        end
    end
    return text
end

-- "Finish part 1 (Wailing Caverns) first" when this step opens a later part.
function P:BlockerText(line, index)
    local partIndex = line.partOf[line.steps[index]] or 1
    if partIndex >= #line.parts then return nil end
    local nextPart = line.parts[partIndex + 1]
    local part = line.parts[partIndex]
    return ("Part %d%s must be done before part %d%s"):format(partIndex,
        part.dungeon and (" (" .. part.dungeon .. ")") or "", partIndex + 1,
        nextPart.dungeon and (" (" .. nextPart.dungeon .. ")") or "")
end
