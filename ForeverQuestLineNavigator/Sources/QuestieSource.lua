-- Reads quest, NPC and object data from QuestieDB's public API (LibQuestieDB),
-- and zone/dungeon mapping from Questie's ZoneDB module.
--
-- LibQuestieDB is QuestieDB's documented, versioned interface for other addons.
-- ZoneDB is internal to Questie, so every call into it is protected: if it ever
-- changes, we lose dungeon entrances / map conversion, but nothing errors.

local _, ns = ...

local S = {}
ns.QuestieSource = S

local CONTRACT = 4 -- the LibQuestieDB contract version this code was written against

function S:Init()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then
        return false, "QuestieDB is not loaded. Install or enable Questie and QuestieDB."
    end
    local ok, msg = lib.RequireContract(CONTRACT)
    if not ok then return false, msg end
    if type(lib.Quest) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Object) ~= "table" then
        return false, "QuestieDB has an unexpected layout."
    end
    self.lib = lib

    if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
        local okZ, zoneDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
        if okZ and type(zoneDB) == "table" then self.zoneDB = zoneDB end
    end
    return true
end

-- Safe single-field reads. Return nil instead of erroring.
local function SafeGet(entity, id, field)
    local ok, value = pcall(entity.Get, id, field)
    if ok then return value end
    return nil
end

function S:Quest(id, field)  return SafeGet(self.lib.Quest, id, field) end
function S:Npc(id, field)    return SafeGet(self.lib.Npc, id, field) end
function S:Object(id, field) return SafeGet(self.lib.Object, id, field) end
function S:Item(id, field)
    if type(self.lib.Item) ~= "table" then return nil end
    return SafeGet(self.lib.Item, id, field)
end

function S:AllQuestIds()
    local ok, ids = pcall(self.lib.Quest.GetAllIds)
    if ok and type(ids) == "table" then return ids end
    return {}
end

-- Race and class bitmasks for the player, as QuestieDB encodes them.
function S:PlayerMasks()
    local _, _, raceId = UnitRace("player")
    local _, _, classId = UnitClass("player")
    local enum = self.lib.Enum or {}
    local raceMask = enum.raceMaskById and enum.raceMaskById[raceId] or (raceId and 2 ^ (raceId - 1)) or 0
    local classMask = classId and 2 ^ (classId - 1) or 0
    return raceMask, classMask
end

-- { [areaId] = { name=, areaId=canonical id, entrances={ {zoneAreaId, x, y}, ... } } }
-- Alternative area IDs of a dungeon point at the same entry.
function S:Dungeons()
    if self.dungeonMap then return self.dungeonMap end
    local map = {}
    local zoneDB = self.zoneDB
    if zoneDB and type(zoneDB.GetDungeons) == "function" then
        local ok, dungeons = pcall(zoneDB.GetDungeons, zoneDB)
        if ok and type(dungeons) == "table" then
            for areaId, entry in pairs(dungeons) do
                if type(entry) == "table" and type(entry[1]) == "string" then
                    local info = { name = entry[1], areaId = areaId, entrances = entry[4] or {} }
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

function S:UiMapForArea(areaId)
    local zoneDB = self.zoneDB
    if not zoneDB or type(zoneDB.GetUiMapIdByAreaId) ~= "function" then return nil end
    local ok, uiMapId = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
    if ok and type(uiMapId) == "number" and uiMapId > 0 then return uiMapId end
    return nil
end

function S:AreaForUiMap(uiMapId)
    local zoneDB = self.zoneDB
    if not zoneDB or type(zoneDB.GetAreaIdByUiMapId) ~= "function" or not uiMapId then return nil end
    local ok, areaId = pcall(zoneDB.GetAreaIdByUiMapId, zoneDB, uiMapId)
    if ok and type(areaId) == "number" and areaId > 0 then return areaId end
    return nil
end

-- All spawn points of an NPC or object as { {uiMapId, x(0-1), y(0-1), areaId}, ... }.
-- Spawns inside a dungeon are replaced by the dungeon entrance.
function S:Points(kind, id)
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
                    points[#points + 1] = { uiMapId, e[2] / 100, e[3] / 100, e[1], inside = dungeon.name }
                end
            end
        elseif type(coords) == "table" then
            local uiMapId = self:UiMapForArea(areaId)
            if uiMapId then
                for _, c in ipairs(coords) do
                    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] >= 0 then
                        points[#points + 1] = { uiMapId, c[1] / 100, c[2] / 100, areaId }
                    end
                end
            end
        end
    end
    return points
end
