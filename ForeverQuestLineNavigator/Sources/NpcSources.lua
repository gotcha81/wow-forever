-- Where NPCs stand, from every source we may use (for the NPCs tab):
--
--  1. Learned as you play (account-wide, ForeverQuestLineNavigatorDB.npcSpots):
--     - exact: where you stand when you talk to an NPC (you are within a few yards)
--     - rough: where you stand when you target / mouse over a friendly or neutral
--       NPC that is close (about 28 yards); only used when nothing better is known
--  2. The game's own flight data (C_TaxiMap): exact flight master positions;
--     spots recorded on Forever by forever-db (optional addon ForeverDB)
--  3. QuestieDB spawns (and its walking paths for NPCs that move around)
--  4. Coordinates you type yourself (/fqln pin, see Commands.lua)
--
-- Learned exact spots come first; Questie spots right next to one are left out
-- (same place twice). Nothing here goes online.

local _, ns = ...

local S = {}
ns.NpcSources = S

local SAME_SPOT = 15          -- yards: a new spot this close to a known one replaces it
local DUPLICATE = 25          -- yards: a Questie spot this close to a better one is left out
local MAX_SPOTS = 8           -- learned spots kept per NPC
local ROUGH_RANGE_INDEX = 4   -- CheckInteractDistance index 4 = about 28 yards
local FLIGHT_SNAP = 40        -- yards: a flight master this close to a flight point stands there
local FLIGHT_MASTER_FLAG = 8  -- QuestieDB npcFlags.FLIGHT_MASTER

local QUALITY = { exact = 2, rough = 1 }

-- A map point in the format the planner uses for quest stops.
function S.MakePoint(uiMapId, x, y, source)
    local wx, wy, instance = ns.Pos.World(uiMapId, x, y)
    if not wx then return nil end
    return { uiMapId = uiMapId, x = x, y = y, zone = ns.Pos.Zone(uiMapId), wx = wx, wy = wy,
             instance = instance, source = source }
end

local function Close(a, b, yards)
    return a.wx and b.wx and (not a.instance or not b.instance or a.instance == b.instance)
        and ns.Pos.Distance(a.wx, a.wy, b.wx, b.wy) <= yards
end

local function FactionLetter()
    local faction = UnitFactionGroup("player")
    return faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
end
S.FactionLetter = FactionLetter

local function Readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

local function NpcIdOf(unit)
    local guid = UnitGUID(unit)
    if not Readable(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" then return tonumber(id) end
end
S.NpcIdOf = NpcIdOf

---------------------------------------------------------------------------------------
-- 1. Learned spots
---------------------------------------------------------------------------------------

local function Store()
    ns.db.npcSpots = ns.db.npcSpots or {}
    return ns.db.npcSpots
end

-- "exact" when talking to it, "rough" for target / mouseover close by.
function S:Learn(unit, kind)
    if IsInInstance() then return end -- the game does not give positions in there
    local id = NpcIdOf(unit)
    if not id or UnitIsPlayer(unit) then return end
    local reaction = UnitReaction(unit, "player")
    if not Readable(reaction) or not reaction or reaction < 4 then return end -- hostile
    if kind == "rough" then
        local ok, near = pcall(CheckInteractDistance, unit, ROUGH_RANGE_INDEX)
        if not ok or not Readable(near) or not near then return end
    end
    local map = ns.Pos.PlayerMap()
    if not map then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
    x, y = ns.Pos.Num(x), ns.Pos.Num(y)
    if not x or not y or (x == 0 and y == 0) then return end

    local store = Store()
    local entry = store[id]
    local isNew = entry == nil
    if not entry then
        entry = { s = {} }
        store[id] = entry
    end
    local name = UnitName(unit)
    if Readable(name) and type(name) == "string" then entry.n = name end
    local letter = FactionLetter()
    if letter and not (entry.f or ""):find(letter, 1, true) then entry.f = (entry.f or "") .. letter end

    local quality = QUALITY[kind]
    local new = S.MakePoint(map, x, y)
    if not new then return end
    for _, spot in ipairs(entry.s) do
        local old = S.MakePoint(spot[1], spot[2], spot[3])
        if old and Close(old, new, SAME_SPOT) then
            if quality >= spot[4] then spot[1], spot[2], spot[3], spot[4] = map, x, y, quality end
            return
        end
    end
    table.insert(entry.s, 1, { map, x, y, quality })
    -- too many: drop a rough one first, else the oldest
    if #entry.s > MAX_SPOTS then
        local drop = #entry.s
        for i = #entry.s, 1, -1 do if entry.s[i][4] == QUALITY.rough then drop = i; break end end
        table.remove(entry.s, drop)
    end
    if isNew and ns.NpcFinder.OnLearned then ns.NpcFinder:OnLearned(id) end
end

function S:Learned(id)
    local entry = ns.db.npcSpots and ns.db.npcSpots[id]
    return type(entry) == "table" and entry or nil
end

function S:LearnedCount()
    local count = 0
    for _ in pairs(ns.db.npcSpots or {}) do count = count + 1 end
    return count
end

---------------------------------------------------------------------------------------
-- 2. The game's flight data
---------------------------------------------------------------------------------------

-- All flight points: { { id, name, faction letter or "N", point }, ... } (once).
function S:FlightNodes()
    if self.flights then return self.flights end
    local list = {}
    self.flights = list
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return list end
    local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
    local factions = Enum and Enum.FlightPathFaction or {}
    local seen = {}
    for mapId = 1, 3000 do
        local info = C_Map.GetMapInfo(mapId)
        if info and info.mapType == continentType then
            local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapId)
            if ok and type(nodes) == "table" then
                for _, node in ipairs(nodes) do
                    local pos = node.position
                    local x, y = pos and pos.x, pos and pos.y
                    if (x == nil or y == nil) and pos and pos.GetXY then x, y = pos:GetXY() end
                    if node.nodeID and not seen[node.nodeID] and type(x) == "number" and type(node.name) == "string" then
                        local point = S.MakePoint(mapId, x, y, "the game's flight data")
                        if point then
                            seen[node.nodeID] = true
                            local letter = "N"
                            if node.faction == (factions.Horde or 1) then letter = "H"
                            elseif node.faction == (factions.Alliance or 2) then letter = "A" end
                            local atlas = type(node.atlasName) == "string" and node.atlasName or ""
                            if atlas:find("Horde") then letter = "H" elseif atlas:find("Alliance") then letter = "A" end
                            list[#list + 1] = { id = node.nodeID, name = node.name, faction = letter, point = point }
                        end
                    end
                end
            end
        end
    end
    return list
end

-- Flight points your faction can use (neutral ones too).
function S:UsableFlightNodes()
    local letter, out = FactionLetter(), {}
    for _, node in ipairs(self:FlightNodes()) do
        if node.faction == "N" or node.faction == letter then out[#out + 1] = node end
    end
    return out
end

function S:NearestFlightNode(point)
    local best, bestDistance
    for _, node in ipairs(self:FlightNodes()) do
        if Close(node.point, point, FLIGHT_SNAP) then
            local d = ns.Pos.Distance(node.point.wx, node.point.wy, point.wx, point.wy)
            if not bestDistance or d < bestDistance then best, bestDistance = node, d end
        end
    end
    return best
end

local function IsFlightMaster(id)
    local flags = ns.QuestieSource:Npc(id, "npcFlags")
    return type(flags) == "number" and bit and bit.band and bit.band(flags, FLIGHT_MASTER_FLAG) ~= 0
end
S.IsFlightMaster = IsFlightMaster

---------------------------------------------------------------------------------------
-- All points of one NPC, best first
---------------------------------------------------------------------------------------

function S:Points(id)
    local out = {}
    local function Known(point)
        for _, p in ipairs(out) do if Close(p, point, DUPLICATE) then return true end end
        return false
    end

    if id < 0 then -- a flight point without a Questie NPC (see NpcFinder)
        for _, node in ipairs(self:FlightNodes()) do
            if node.id == -id then out[1] = node.point end
        end
        return out
    end

    local learned = self:Learned(id)
    if learned then
        for _, spot in ipairs(learned.s) do
            if spot[4] == QUALITY.exact then
                local p = S.MakePoint(spot[1], spot[2], spot[3], "seen by you")
                if p and not Known(p) then out[#out + 1] = p end
            end
        end
    end

    -- spots recorded on Forever by forever-db's players
    for _, spot in ipairs(ns.ForeverDBSource:NpcSpots(id) or {}) do
        local p = S.MakePoint(spot[1], spot[2], spot[3], "recorded on Forever (forever-db)")
        if p and not Known(p) then out[#out + 1] = p end
    end

    local flightMaster = IsFlightMaster(id)
    for _, p in ipairs(ns.Planner:NpcPoints(id)) do
        p.source = "Questie"
        if flightMaster and not p.inside then
            local node = self:NearestFlightNode(p)
            if node then
                local exact = node.point
                p = { uiMapId = exact.uiMapId, x = exact.x, y = exact.y, zone = exact.zone, wx = exact.wx,
                      wy = exact.wy, instance = exact.instance, source = "the game's flight data", flight = node.name }
            end
        end
        if not Known(p) then out[#out + 1] = p end
    end

    if learned then
        for _, spot in ipairs(learned.s) do
            if spot[4] == QUALITY.rough then
                local p = S.MakePoint(spot[1], spot[2], spot[3], "seen by you (rough, within ~30 yd)")
                if p and not Known(p) then out[#out + 1] = p end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------------------
-- 3. Questie's walking paths (for NPCs that move around)
---------------------------------------------------------------------------------------

-- { { uiMapId, x(0-1), y(0-1) }, ... } at most `limit` dots, spread over the paths.
function S:PathDots(id, limit)
    local Q = ns.QuestieSource
    local paths = id > 0 and Q:Npc(id, "waypoints")
    local all = {}
    if type(paths) ~= "table" then return all end
    for areaId, list in pairs(paths) do
        local uiMapId = Q:UiMapForArea(areaId)
        if uiMapId and type(list) == "table" then
            for _, path in ipairs(list) do
                if type(path) == "table" then
                    for _, c in ipairs(path) do
                        if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] >= 0 then
                            all[#all + 1] = { uiMapId, c[1] / 100, c[2] / 100 }
                        end
                    end
                end
            end
        end
    end
    if #all <= limit then return all end
    local out, step = {}, #all / limit
    for i = 1, limit do out[i] = all[math.floor((i - 1) * step) + 1] end
    return out
end

---------------------------------------------------------------------------------------
-- 4. Typed coordinates: zone names -> map ids
---------------------------------------------------------------------------------------

function S:FindZone(text)
    if not self.zones then
        self.zones = {}
        local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
        for mapId = 1, 3000 do
            local info = C_Map.GetMapInfo(mapId)
            if info and info.mapType == zoneType and type(info.name) == "string" and Readable(info.name) then
                local key = info.name:lower()
                self.zones[key] = self.zones[key] or mapId
            end
        end
    end
    local lower = text:lower()
    if self.zones[lower] then return self.zones[lower] end
    for name, mapId in pairs(self.zones) do
        if name:find(lower, 1, true) then return mapId end
    end
end

-- "/fqln pin [zone] x y [name]", Wowhead style "[45.3, 62.1]" works too.
-- Returns uiMapId, x, y (0-1), name, or nil and an error text.
function S:ParsePin(text)
    local tokens = {}
    for t in text:gsub("[%[%],]", " "):gmatch("%S+") do tokens[#tokens + 1] = t end
    for i = 1, #tokens - 1 do
        local x, y = tonumber(tokens[i]), tonumber(tokens[i + 1])
        if x and y then
            if x < 0 or x > 100 or y < 0 or y > 100 then return nil, "coordinates go from 0 to 100." end
            local zoneText = table.concat(tokens, " ", 1, i - 1)
            local name = table.concat(tokens, " ", i + 2)
            local map
            if zoneText ~= "" then
                map = self:FindZone(zoneText)
                if not map then return nil, ("no zone called \"%s\"."):format(zoneText) end
            else
                map = ns.Pos.PlayerZone()
                if not map then return nil, "your zone is not known here; put the zone name first." end
            end
            return map, x / 100, y / 100, name ~= "" and name or "Map marker"
        end
    end
    return nil, "use: /fqln pin [zone] x y [name], for example /fqln pin Orgrimmar 32.2 37.8 Thrall"
end
