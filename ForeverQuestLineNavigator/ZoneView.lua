-- Zone view (the Zone tab): every quest picked up in one zone, what state it is
-- in for you, and "(MZ)" when the quest itself takes you to more than one zone
-- (its giver, objectives and turn-in are not all in the same zone).
--
-- A quest is listed in the zone(s) where its giver stands. A giver inside a
-- dungeon counts for the zone with the dungeon's entrance (the same goes for MZ).
-- Quests that start from an item use the zone the game files the quest under.
-- The index is built the first time the Zone tab opens (spread over frames).

local _, ns = ...

local Z = { ready = false, building = false, waiting = {}, byZone = {}, mzCache = {} }
ns.ZoneView = Z

local MAX_DROP_SOURCES = 6

---------------------------------------------------------------------------------------
-- Zones of a quest
---------------------------------------------------------------------------------------

-- Spawn area ids of an NPC or object -> zone area ids (dungeons -> entrance zone).
local function AddZones(set, kind, id)
    local Q = ns.QuestieSource
    local spawns = (kind == "object") and Q:Object(id, "spawns") or Q:Npc(id, "spawns")
    if type(spawns) ~= "table" then return end
    local dungeons = Q:Dungeons()
    for area in pairs(spawns) do
        local dungeon = type(area) == "number" and dungeons[area]
        if dungeon then
            for _, e in ipairs(dungeon.entrances) do
                if type(e) == "table" and type(e[1]) == "number" then set[e[1]] = true end
            end
        elseif type(area) == "number" and area > 0 then
            set[area] = true
        end
    end
end

local function GiverZones(questId)
    local Q = ns.QuestieSource
    local set = {}
    local starters = Q:Quest(questId, "startedBy")
    if type(starters) == "table" then
        for _, id in ipairs(starters[1] or {}) do AddZones(set, "npc", id) end
        for _, id in ipairs(starters[2] or {}) do AddZones(set, "object", id) end
    end
    if next(set) == nil then
        local zone = Q:Quest(questId, "zoneOrSort")
        if type(zone) == "number" and zone > 0 and not Q:Dungeons()[zone] then set[zone] = true end
    end
    return set
end

local function AddItemZones(set, itemId)
    local Q = ns.QuestieSource
    local drops = Q:Item(itemId, "npcDrops")
    if type(drops) == "table" then
        for i = 1, math.min(#drops, MAX_DROP_SOURCES) do AddZones(set, "npc", drops[i]) end
    end
    local objects = Q:Item(itemId, "objectDrops")
    if type(objects) == "table" then
        for i = 1, math.min(#objects, MAX_DROP_SOURCES) do AddZones(set, "object", objects[i]) end
    end
end

-- Whether the quest itself spans zones: true/false and the zone names (sorted).
function Z:MultiZone(questId)
    local cached = self.mzCache[questId]
    if cached then return cached.mz, cached.names end
    local Q = ns.QuestieSource
    local set = GiverZones(questId)
    local finishers = Q:Quest(questId, "finishedBy")
    if type(finishers) == "table" then
        for _, id in ipairs(finishers[1] or {}) do AddZones(set, "npc", id) end
        for _, id in ipairs(finishers[2] or {}) do AddZones(set, "object", id) end
    end
    local objectives = Q:Quest(questId, "objectives")
    if type(objectives) == "table" then
        for _, o in ipairs(objectives[1] or {}) do if type(o) == "table" and o[1] then AddZones(set, "npc", o[1]) end end
        for _, o in ipairs(objectives[2] or {}) do if type(o) == "table" and o[1] then AddZones(set, "object", o[1]) end end
        for _, o in ipairs(objectives[3] or {}) do if type(o) == "table" and o[1] then AddItemZones(set, o[1]) end end
    end
    local trigger = Q:Quest(questId, "triggerEnd")
    if type(trigger) == "table" and type(trigger[2]) == "table" then
        for area in pairs(trigger[2]) do if type(area) == "number" then set[area] = true end end
    end
    -- by name: two area ids for the same zone count once
    local names, seen = {}, {}
    for area in pairs(set) do
        local name = self:ZoneName(area)
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    cached = { mz = #names > 1, names = names }
    self.mzCache[questId] = cached
    return cached.mz, cached.names
end

local zoneNames = {}
function Z:ZoneName(area)
    if zoneNames[area] == nil then
        local map = ns.QuestieSource:UiMapForArea(area)
        zoneNames[area] = map and ns.Pos.MapName(map) or false
    end
    return zoneNames[area] or nil
end

---------------------------------------------------------------------------------------
-- Index: zone -> quests picked up there
---------------------------------------------------------------------------------------

function Z:Build(onDone)
    if self.ready then onDone(); return end
    if not ns.ready then return end -- the quest catalog (race / class checks) comes first
    self.waiting[#self.waiting + 1] = onDone
    if self.building then return end
    self.building = true

    local Q, P, O = ns.QuestieSource, ns.Planner, ns.Overrides
    local byZone = {}

    local function Scan()
        local all = Q:AllQuestIds()
        for index = 1, #all do
            local id = all[index]
            if not O.hiddenQuests[id] and P.RaceOk(id) and P.ClassOk(id) then
                for area in pairs(GiverZones(id)) do
                    local list = byZone[area]
                    if not list then list = {}; byZone[area] = list end
                    list[#list + 1] = id
                end
            end
            if index % 300 == 0 then coroutine.yield() end
        end
        -- one entry per zone name (a zone can have more than one area id)
        local zones, byName, count = {}, {}, 0
        for area, ids in pairs(byZone) do
            local name = self:ZoneName(area)
            if name then
                local z = byName[name]
                if not z then
                    z = { name = name, area = area, quests = {}, seen = {} }
                    byName[name] = z
                    zones[#zones + 1] = z
                end
                for _, id in ipairs(ids) do
                    if not z.seen[id] then
                        z.seen[id] = true
                        z.quests[#z.quests + 1] = id
                    end
                end
            end
            count = count + 1
            if count % 20 == 0 then coroutine.yield() end
        end
        for _, z in ipairs(zones) do
            z.seen = nil
            z.min, z.max = self:LevelRange(z)
        end
        table.sort(zones, function(a, b)
            if (a.min or 999) ~= (b.min or 999) then return (a.min or 999) < (b.min or 999) end
            return a.name < b.name
        end)
        self.list, self.byName = zones, byName
    end

    local co = coroutine.create(Scan)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(f)
        local ok, err = coroutine.resume(co)
        if not ok then
            f:SetScript("OnUpdate", nil)
            Z.building = false
            ns.LogError("zone index", err, debugstack and debugstack(co) or "")
            return
        end
        if coroutine.status(co) == "dead" then
            f:SetScript("OnUpdate", nil)
            Z.ready, Z.building = true, false
            local waiting = Z.waiting
            Z.waiting = {}
            for _, fn in ipairs(waiting) do ns.Safe("zone view", fn)() end
        end
    end)
end

-- Level range from the quest levels, leaving out stray quests far below the rest.
function Z:LevelRange(z)
    local levels = {}
    for _, id in ipairs(z.quests) do
        local level = ns.Planner:QuestLevel(id)
        if level and level > 0 then levels[#levels + 1] = level end
    end
    if #levels == 0 then return nil end
    table.sort(levels)
    local median = levels[math.floor((#levels + 1) / 2)]
    local min
    for _, level in ipairs(levels) do
        if level >= median - 8 then min = level; break end
    end
    return min, levels[#levels]
end

function Z:Zones() return self.list or {} end

function Z:Find(name)
    if not name or not self.ready then return nil end
    if self.byName[name] then return self.byName[name] end
    local lower = name:lower()
    for _, z in ipairs(self.list) do
        if z.name:lower() == lower then return z end
    end
    for _, z in ipairs(self.list) do
        if z.name:lower():find(lower, 1, true) then return z end
    end
end

-- The zone you are in (nil when unknown or not in the index).
function Z:Current()
    local name = ns.Pos.MapName(ns.Pos.PlayerZone())
    return name and self.byName and self.byName[name] or nil
end

---------------------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------------------

-- All quests of a zone: open, grey (hidden behind a + row), done, ignored.
function Z:Entries(name)
    local z = self:Find(name)
    local result = { open = {}, grey = {}, done = {}, ignored = {}, zone = z }
    if not z then return result end
    local D = ns.DungeonView
    local level = UnitLevel("player")
    local levelXP = UnitXPMax("player") or 0
    for _, id in ipairs(z.quests) do
        local e = D:Entry(id, level, levelXP)
        e.mz, e.mzZones = self:MultiZone(id)
        if e.state == "done" then
            result.done[#result.done + 1] = e
        elseif e.ignored then
            result.ignored[#result.ignored + 1] = e
        elseif e.trivialHidden then
            result.grey[#result.grey + 1] = e
        else
            result.open[#result.open + 1] = e
        end
    end
    for _, list in pairs({ result.open, result.grey, result.done, result.ignored }) do
        table.sort(list, D.SortEntries)
    end
    return result
end

-- Quests in a zone you can do something about now: count for the picker.
function Z:OpenCount(z)
    local level, count = UnitLevel("player"), 0
    local P = ns.Planner
    for _, id in ipairs(z.quests) do
        if not P.IsDone(id) and not ns.Ignore:Hidden(id) then
            if P.InLog(id) or (P:RequiredLevel(id) <= level and not P.IsTrivial(P:QuestLevel(id), level)) then
                count = count + 1
            end
        end
    end
    return count
end

-- Entering a new zone: the Zone tab follows you (like the Dungeon tab does in a dungeon).
function Z:OnZoneChanged()
    if not self.ready then return end
    local z = self:Current()
    if z and z.name ~= self.lastZone then
        self.lastZone = z.name
        ns.db.list.zone = z.name
        if ns.db.list.tab == "zone" then ns.List:Update() end
    end
end
