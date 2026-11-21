-- Where quest facts come from.
--
-- With Questie installed: QuestieDB's public API (LibQuestieDB) gives every quest,
-- its prerequisites, givers, turn-ins, objectives and reward items, and Questie's
-- ZoneDB module (internal, so every call is protected) turns zone IDs into maps.
-- Without Questie: only what the game client itself knows (see Chains.lua).

local _, ns = ...

local D = {}
ns.Data = D

local CONTRACT = 4 -- the LibQuestieDB contract version this was written against

-- Race bitmasks (Classic race IDs). Used to tell a quest's faction.
local ALLIANCE_RACES = 1 + 4 + 8 + 64 + 1024 -- Human, Dwarf, Night Elf, Gnome, Draenei
local HORDE_RACES    = 2 + 16 + 32 + 128 + 512 -- Orc, Undead, Tauren, Troll, Blood Elf

local band = bit and bit.band

function D:Init()
    self.questie = false
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then return end
    local ok, good = pcall(lib.RequireContract, CONTRACT)
    if not ok or not good then return end
    if type(lib.Quest) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Object) ~= "table" then return end
    self.lib = lib
    self.questie = true
    if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
        local okZ, zoneDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
        if okZ and type(zoneDB) == "table" then self.zoneDB = zoneDB end
    end
end

local function SafeGet(entity, id, field)
    if type(entity) ~= "table" or type(entity.Get) ~= "function" then return nil end
    local ok, value = pcall(entity.Get, id, field)
    if ok then return value end
    return nil
end

function D:Quest(id, field)  return self.lib and SafeGet(self.lib.Quest, id, field) end
function D:Npc(id, field)    return self.lib and SafeGet(self.lib.Npc, id, field) end
function D:Object(id, field) return self.lib and SafeGet(self.lib.Object, id, field) end
function D:Item(id, field)   return self.lib and SafeGet(self.lib.Item, id, field) end

local function AllIds(entity)
    if type(entity) ~= "table" or type(entity.GetAllIds) ~= "function" then return {} end
    local ok, ids = pcall(entity.GetAllIds)
    if ok and type(ids) == "table" then return ids end
    return {}
end

function D:AllQuestIds() return self.lib and AllIds(self.lib.Quest) or {} end
function D:AllItemIds()  return self.lib and AllIds(self.lib.Item) or {} end

-- "Horde", "Alliance" or "Both", from a requiredRaces bitmask.
function D.SideOfRaces(races)
    if type(races) ~= "number" or races == 0 or not band then return "Both" end
    local a, h = band(races, ALLIANCE_RACES) ~= 0, band(races, HORDE_RACES) ~= 0
    if a and not h then return "Alliance" end
    if h and not a then return "Horde" end
    return "Both"
end

function D:PlayerClassMask()
    local _, _, classId = UnitClass("player")
    return classId and 2 ^ (classId - 1) or 0
end

---------------------------------------------------------------------------------------
-- Zones and maps
---------------------------------------------------------------------------------------

-- { [areaId] = { name=, entrances={ {zoneAreaId, x, y}, ... } } }
function D:Dungeons()
    if self.dungeonMap then return self.dungeonMap end
    local map = {}
    local zoneDB = self.zoneDB
    if zoneDB and type(zoneDB.GetDungeons) == "function" then
        local ok, dungeons = pcall(zoneDB.GetDungeons, zoneDB)
        if ok and type(dungeons) == "table" then
            for areaId, entry in pairs(dungeons) do
                if type(entry) == "table" and type(entry[1]) == "string" then
                    local info = { name = entry[1], entrances = type(entry[4]) == "table" and entry[4] or {} }
                    map[areaId] = info
                    if type(entry[2]) == "table" then
                        for _, alt in ipairs(entry[2]) do map[alt] = map[alt] or info end
                    end
                end
            end
        end
    end
    self.dungeonMap = map
    return map
end

function D:UiMapForArea(areaId)
    local zoneDB = self.zoneDB
    if not zoneDB or type(zoneDB.GetUiMapIdByAreaId) ~= "function" then return nil end
    local ok, uiMapId = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
    if ok and type(uiMapId) == "number" and uiMapId > 0 then return uiMapId end
    return nil
end

local mapNames = {}
function D.MapName(uiMapId)
    if not uiMapId then return nil end
    local name = mapNames[uiMapId]
    if name == nil then
        local ok, info = pcall(C_Map.GetMapInfo, uiMapId)
        name = ok and type(info) == "table" and info.name or false
        mapNames[uiMapId] = name
    end
    return name or nil
end

local areaNames = {}
function D:AreaName(areaId)
    if type(areaId) ~= "number" or areaId <= 0 then return nil end
    local name = areaNames[areaId]
    if name == nil then
        name = false
        if C_Map and C_Map.GetAreaInfo then
            local ok, n = pcall(C_Map.GetAreaInfo, areaId)
            if ok and type(n) == "string" and n ~= "" then name = n end
        end
        if not name then name = D.MapName(self:UiMapForArea(areaId)) or false end
        areaNames[areaId] = name
    end
    return name or nil
end

-- All places of an NPC or object as { {uiMapId=, x=(0-1), y=(0-1), inside=dungeon name}, ... }.
-- Spawns inside a dungeon become the dungeon entrance.
function D:Points(kind, id)
    local spawns = (kind == "object") and self:Object(id, "spawns") or self:Npc(id, "spawns")
    local points = {}
    if type(spawns) ~= "table" then return points end
    local dungeons = self:Dungeons()
    for areaId, coords in pairs(spawns) do
        local dungeon = dungeons[areaId]
        if dungeon then
            for _, e in ipairs(dungeon.entrances) do
                local uiMapId = type(e) == "table" and self:UiMapForArea(e[1])
                if uiMapId and type(e[2]) == "number" and type(e[3]) == "number" and e[2] >= 0 then
                    points[#points + 1] = { uiMapId = uiMapId, x = e[2] / 100, y = e[3] / 100, inside = dungeon.name }
                end
            end
        elseif type(coords) == "table" then
            local uiMapId = self:UiMapForArea(areaId)
            if uiMapId then
                for _, c in ipairs(coords) do
                    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] >= 0 then
                        points[#points + 1] = { uiMapId = uiMapId, x = c[1] / 100, y = c[2] / 100 }
                    end
                end
            end
        end
    end
    return points
end

---------------------------------------------------------------------------------------
-- Who gives and takes a quest
---------------------------------------------------------------------------------------

-- { { kind="npc"|"object"|"item", id=, name= }, ... }
local function Who(self, list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, id in ipairs(list[1] or {}) do out[#out + 1] = { kind = "npc", id = id, name = self:Npc(id, "name") } end
    for _, id in ipairs(list[2] or {}) do out[#out + 1] = { kind = "object", id = id, name = self:Object(id, "name") } end
    for _, id in ipairs(list[3] or {}) do out[#out + 1] = { kind = "item", id = id, name = self:Item(id, "name") } end
    return out
end

function D:Givers(questId)   return Who(self, self:Quest(questId, "startedBy")) end
function D:TurnIns(questId)  return Who(self, self:Quest(questId, "finishedBy")) end

-- The zone name of the first place an NPC / object is found ("Inside X" for dungeons).
function D:PlaceText(who)
    if not who or who.kind == "item" then return nil end
    local p = self:Points(who.kind, who.id)[1]
    if not p then return nil end
    local zone = D.MapName(p.uiMapId)
    if p.inside then return p.inside end
    return zone
end
