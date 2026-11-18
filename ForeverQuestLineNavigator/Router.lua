-- Router: puts the stops in the order that gives the most XP per hour.
--
-- It plays the route forward from where you stand:
--   * every step it takes the stop with the best XP per second, counting the
--     travel there (Shortest Path Forever when installed, else straight line)
--     and the time spent there (objectives, a dungeon run);
--   * picking a quest up adds its objectives (or straight its turn-in) to what
--     is left; finishing the objectives adds the turn-in; a turn-in unlocks the
--     next quest of its questline. So the route is pickups -> objectives ->
--     turn-ins in a sensible order, not just "what is closest";
--   * dungeon quests are done in one run: their objectives are one block worth
--     all the XP you hold for that dungeon, against the time of one run. The run
--     waits while pickups for that dungeon are still close enough to collect.
-- It plans up to ns.db.maxStops stops or about an hour ahead, and runs again on
-- every update (quest log, level, zone).

local _, ns = ...

local R = {}
ns.Router = R

-- Tuning
local HORIZON          = 3600  -- seconds of route planned ahead
local STOP_OVERHEAD    = 20    -- seconds at a pickup / turn-in (talk, read)
local DEFAULT_KILLS    = 8     -- kills per objective when the count is not known
local DROP_FACTOR      = 1.8   -- an item objective takes this many kills per item
local OBJECT_SECONDS   = 20    -- seconds per object to click / loot
local OTHER_OBJECTIVE  = 90    -- seconds for an event / exploration objective
local GATHER_SECONDS   = 600   -- a dungeon run waits while a pickup for it is closer than this
local DOWNSTREAM_WEIGHT = 0.25 -- XP further down a questline (not yet unlocked in the plan) counts this much
local SPF_CANDIDATES   = 6     -- best stops (by straight line) that get a real travel time each step
local KEEP_FIRST       = 0.85  -- the current first stop stays first unless another is clearly better
local NOT_WORTH_SHARE  = 0.15  -- a pickup below 15% of the best XP/second is "not worth it"
local SAME_PLACE       = 60    -- yards: no real travel estimate needed this close

-- Weights on XP (questlines are what this addon is for)
local WEIGHT = { dungeon = 1.25, class = 1.25, world = 1 }

local P -- ns.Planner

---------------------------------------------------------------------------------------
-- Travel
---------------------------------------------------------------------------------------

local function Straight(from, to, speed)
    if not from.wx or not to.wx then return 600 end
    if from.instance and to.instance and from.instance ~= to.instance then
        return ns.db.boatWait + 120 + 300 -- other continent: boat / zeppelin and the way to it
    end
    local dx, dy = from.wx - to.wx, from.wy - to.wy
    return math.sqrt(dx * dx + dy * dy) / speed
end

-- Seconds from a position { wx, wy, instance, uiMapId, x, y } to a point.
local function Travel(from, to, speed, real)
    local straight = Straight(from, to, speed)
    if not real or straight * speed < SAME_PLACE then return straight end
    local seconds = ns.Travel:Seconds(from.uiMapId, from.x, from.y, to.uiMapId, to.x, to.y)
    return seconds or straight
end

-- Your position as a point (map position too, for Shortest Path Forever).
function R:PlayerPoint(px, py, instance)
    local point = { wx = px, wy = py, instance = instance }
    local map = ns.Pos.PlayerMap()
    if map and C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if ok and pos then
            local x, y = pos.x, pos.y
            if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
            x, y = ns.Pos.Num(x), ns.Pos.Num(y)
            if x and y then point.uiMapId, point.x, point.y = map, x, y end
        end
    end
    return point
end

---------------------------------------------------------------------------------------
-- Time spent at a stop
---------------------------------------------------------------------------------------

local function KillSeconds() return ns.db.killSeconds or 20 end

-- Seconds for the objectives of a quest (what is left of them when it is in your log).
function R:ObjectiveSeconds(questId)
    local recorded = ns.ForeverDBSource:QuestSeconds(questId)
    if recorded then return recorded end
    local kill = KillSeconds()
    local total = 0
    if P.InLog(questId) and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local objectives = C_QuestLog.GetQuestObjectives(questId)
        if type(objectives) == "table" and #objectives > 0 then
            for _, o in ipairs(objectives) do
                if not o.finished then
                    local left = math.max(1, (tonumber(o.numRequired) or 1) - (tonumber(o.numFulfilled) or 0))
                    if o.type == "monster" then total = total + left * kill
                    elseif o.type == "item" then total = total + left * kill * DROP_FACTOR
                    elseif o.type == "object" then total = total + left * OBJECT_SECONDS
                    else total = total + OTHER_OBJECTIVE end
                end
            end
            return total
        end
    end
    local objectives = ns.QuestieSource:Quest(questId, "objectives")
    if type(objectives) ~= "table" then return 0 end
    for _ in ipairs(objectives[1] or {}) do total = total + DEFAULT_KILLS * kill end
    for _ in ipairs(objectives[2] or {}) do total = total + 3 * OBJECT_SECONDS end
    for _ in ipairs(objectives[3] or {}) do total = total + DEFAULT_KILLS * kill * DROP_FACTOR / 2 end
    if objectives[5] then total = total + DEFAULT_KILLS * kill end -- kill credit
    return total
end

local function HasObjectives(questId)
    local objectives = ns.QuestieSource:Quest(questId, "objectives")
    if type(objectives) ~= "table" then return false end
    return #(objectives[1] or {}) + #(objectives[2] or {}) + #(objectives[3] or {}) > 0
        or objectives[5] ~= nil or objectives[4] ~= nil
end

local function DungeonOf(stop)
    if stop.point and stop.point.inside then return stop.point.inside end
    for _, p in ipairs(stop.points or {}) do if p.inside then return p.inside end end
end

---------------------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------------------

local function Weight(stop)
    if stop.primary then return WEIGHT[stop.primary.line.kind] or WEIGHT.dungeon end
    return WEIGHT.world
end

-- XP still to come further down the lines of a stop that the plan has not opened yet.
local function Downstream(stop, opened)
    local extra = 0
    for _, entry in ipairs(stop.lines) do
        local eval = entry.line.eval
        if eval and not opened[entry.line] then extra = extra + math.max(0, eval.xpReach - stop.xp) end
    end
    return extra * DOWNSTREAM_WEIGHT
end

-- A new stop the plan creates (the objectives / turn-in of a quest picked up on the way).
local function MakeStop(template, state)
    local stop = { questId = template.questId, state = state, lines = template.lines, name = template.name,
                   level = template.level, xp = template.xp, xpEstimate = template.xpEstimate,
                   trivial = template.trivial, primary = template.primary, dungeon = template.dungeon,
                   leadIn = template.leadIn, world = template.world, planned = true }
    P:Locate(stop)
    return stop
end

-- Prerequisites done, counting quests the plan has already turned in.
local function PrereqsDone(id, simDone)
    local Q = ns.QuestieSource
    local function Done(q) return P.IsDone(q) or simDone[q] end
    local group = Q:Quest(id, "preQuestGroup")
    if type(group) == "table" then
        for _, pre in ipairs(group) do if not Done(pre) then return false end end
    end
    local single = Q:Quest(id, "preQuestSingle")
    if type(single) == "table" and #single > 0 then
        for _, pre in ipairs(single) do if Done(pre) then return true end end
        return false
    end
    return true
end

-- Plans the route. ctx = { from = point, level = n }.
-- Returns route, notWorth, left (stops that did not fit in the plan).
function R:Plan(stops, ctx)
    P = ns.Planner
    ns.Travel:NewPass()
    local db = ns.db
    local speed = 7 * (1 + P:Riding() / 100)
    local level = ctx.level

    local remaining, byKey = {}, {}
    for _, stop in ipairs(stops) do
        if #stop.points > 0 then
            remaining[#remaining + 1] = stop
            byKey[stop.questId .. ":" .. stop.state] = stop
        end
    end

    -- Value of a stop from `pos`: xp, seconds, point, and for a dungeon run the group.
    local function Evaluate(stop, pos, opened, real, simTime)
        local bestPoint, bestTravel
        for _, point in ipairs(stop.points) do
            local t = Straight(pos, point, speed)
            if not bestTravel or t < bestTravel then bestPoint, bestTravel = point, t end
        end
        if not bestPoint then return nil end
        if real then bestTravel = Travel(pos, bestPoint, speed, true) end
        local xp, seconds = stop.xp, bestTravel + STOP_OVERHEAD
        local group
        if stop.state == "pickup" then
            xp = stop.xp + Downstream(stop, opened)
            if not DungeonOf(stop) then
                -- the quest's own work: objectives, and roughly the way back to turn it in
                seconds = seconds + R:ObjectiveSeconds(stop.questId) + STOP_OVERHEAD
            end
        elseif stop.state == "progress" then
            local dungeon = DungeonOf(stop)
            if dungeon then
                -- one run for all the quests you hold for this dungeon
                group, xp = {}, 0
                for _, other in ipairs(remaining) do
                    if other.state == "progress" and DungeonOf(other) == dungeon then
                        group[#group + 1] = other
                        xp = xp + other.xp
                    end
                end
                seconds = seconds + (db.dungeonMinutes or 40) * 60
            else
                seconds = seconds + R:ObjectiveSeconds(stop.questId)
            end
        else -- turnin
            xp = stop.xp + Downstream(stop, opened)
        end
        return xp * Weight(stop), math.max(seconds, 1), bestPoint, bestTravel, group
    end

    -- A dungeon run waits while a pickup for the same dungeon is still close.
    local function RunWaits(dungeon, pos)
        for _, other in ipairs(remaining) do
            if other.state == "pickup" and (other.dungeon == dungeon or DungeonOf(other) == dungeon) then
                for _, point in ipairs(other.points) do
                    if Straight(pos, point, speed) < GATHER_SECONDS then return true end
                end
            end
        end
        return false
    end

    -- Not worth it: pickups far below the best XP per second from where you stand.
    local notWorth, keep, best = {}, {}, 0
    for _, stop in ipairs(remaining) do
        local xp, seconds = Evaluate(stop, ctx.from, {}, false)
        stop.value = xp and xp / seconds or 0
        if stop.value > best then best = stop.value end
    end
    for _, stop in ipairs(remaining) do
        local limit = stop.leadIn and 0.35 or NOT_WORTH_SHARE
        if stop.state == "pickup" and best > 0 and stop.value < best * limit then
            stop.reason = stop.leadIn and "grey start that does not fit your route" or "slow for the XP it gives"
            notWorth[#notWorth + 1] = stop
        else
            keep[#keep + 1] = stop
        end
    end
    remaining = keep

    local route, opened, simDone = {}, {}, {}
    local pos, clock = ctx.from, 0
    local previousFirst = self.firstKey

    local function Remove(stop)
        for i, s in ipairs(remaining) do if s == stop then table.remove(remaining, i); return end end
    end

    local function Add(stop)
        local key = stop.questId .. ":" .. stop.state
        if byKey[key] then return end
        byKey[key] = stop
        if #stop.points > 0 then remaining[#remaining + 1] = stop end
    end

    -- What doing a stop adds to the plan.
    local function Follow(stop)
        if stop.state == "pickup" then
            local nextState = HasObjectives(stop.questId) and "progress" or "turnin"
            Add(MakeStop(stop, nextState))
        elseif stop.state == "progress" then
            Add(MakeStop(stop, "turnin"))
        elseif stop.state == "turnin" then
            simDone[stop.questId] = true
            for _, entry in ipairs(stop.lines) do
                local line = entry.line
                local nextId = line.steps[entry.index + 1]
                if nextId and not P:StepDone(line, nextId) and not P.InLog(nextId)
                    and P:RequiredLevel(nextId) <= level and PrereqsDone(nextId, simDone) then
                    local xp, isEstimate = ns.XP:Get(nextId)
                    local template = { questId = nextId, lines = { { line = line, index = entry.index + 1 } },
                                       name = P:QuestName(nextId), level = P:QuestLevel(nextId), xp = xp,
                                       xpEstimate = isEstimate, primary = { line = line, index = entry.index + 1 } }
                    template.trivial = P.IsTrivial(template.level, level)
                    local part = line.parts[line.partOf[nextId] or 1]
                    template.dungeon = part and part.dungeon
                    Add(MakeStop(template, "pickup"))
                end
            end
        end
    end

    while #remaining > 0 and #route < db.maxStops and clock < HORIZON do
        -- straight-line pass, then real travel times for the best few
        local scored = {}
        for _, stop in ipairs(remaining) do
            local xp, seconds = Evaluate(stop, pos, opened, false)
            if xp then scored[#scored + 1] = { stop = stop, rate = xp / seconds } end
        end
        table.sort(scored, function(a, b) return a.rate > b.rate end)
        local top, choice
        for i, s in ipairs(scored) do
            local real = i <= SPF_CANDIDATES
            local xp, seconds, point, travel, group = Evaluate(s.stop, pos, opened, real)
            local dungeon = group and DungeonOf(s.stop)
            if xp and not (dungeon and RunWaits(dungeon, pos)) then
                local rate = xp / seconds
                if #route == 0 and previousFirst == s.stop.questId .. ":" .. s.stop.state then
                    rate = rate / KEEP_FIRST -- do not flip the first stop for a small gain
                end
                if not top or rate > top then
                    top, choice = rate, { stop = s.stop, point = point, travel = travel, seconds = seconds, group = group }
                end
            end
            if i > SPF_CANDIDATES and choice then break end
        end
        if not choice then break end

        local stop = choice.stop
        stop.point, stop.seconds = choice.point, choice.travel
        clock = clock + choice.seconds
        stop.eta = clock
        route[#route + 1] = stop
        Remove(stop)
        for _, entry in ipairs(stop.lines) do opened[entry.line] = true end
        Follow(stop)
        if choice.group then
            -- the rest of the dungeon's quests are done in the same run
            for _, other in ipairs(choice.group) do
                if other ~= stop then
                    other.point, other.seconds, other.eta = choice.point, 0, clock
                    route[#route + 1] = other
                    Remove(other)
                    for _, entry in ipairs(other.lines) do opened[entry.line] = true end
                    Follow(other)
                end
            end
        end
        pos = choice.point
    end

    if not ns.Travel.missing then self.fillPasses = 0 end
    self.firstKey = route[1] and (route[1].questId .. ":" .. route[1].state) or nil
    self.minutes = math.floor(clock / 60 + 0.5)
    local xpTotal = 0
    for _, stop in ipairs(route) do if stop.state == "turnin" then xpTotal = xpTotal + (stop.xp or 0) end end
    self.xpPerHour = clock > 0 and math.floor(xpTotal / clock * 3600) or 0
    self.realTravel = ns.Travel:Available()
    if ns.Travel.missing and (self.fillPasses or 0) < 3 then
        self.fillPasses = (self.fillPasses or 0) + 1
        ns.RequestRefresh(3) -- more travel times to fetch (at most 3 extra passes in a row)
    elseif ns.Travel.retry and not InCombatLockdown() and not self.retryPending then
        self.retryPending = true -- Shortest Path Forever was still loading: one retry at a time
        C_Timer.After(15, function() R.retryPending = false; ns.RequestRefresh(0) end)
    end

    local left = {}
    for _, stop in ipairs(remaining) do if not stop.planned then left[#left + 1] = stop end end
    return route, notWorth, left
end
