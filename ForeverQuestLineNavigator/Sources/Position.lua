-- Player and map positions in world coordinates (yards), straight from the game API.
--
-- On the Forever client some values can be "secret" (unreadable for addons), so
-- every value is checked before use. Nothing here errors; unknown = nil.

local _, ns = ...

local Pos = {}
ns.Pos = Pos

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local CONTINENT_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local function Num(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return type(value) == "number" and value or nil
end
Pos.Num = Num

-- Map position (0-1) -> world x, y (yards) and continent id.
function Pos.World(uiMapId, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and uiMapId and x and y) then return nil end
    local vector = CreateVector2D and CreateVector2D(x, y) or { x = x, y = y }
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapId, vector)
    if not ok or type(pos) ~= "table" then return nil end
    local wx, wy = pos.x, pos.y
    if (wx == nil or wy == nil) and pos.GetXY then wx, wy = pos:GetXY() end
    wx, wy = Num(wx), Num(wy)
    if not wx or not wy then return nil end
    return wx, wy, Num(continent)
end

-- The player's world x, y and continent id (nil when the game does not tell).
function Pos.Player()
    if UnitPosition then
        local ok, px, py, _, continent = pcall(UnitPosition, "player")
        if ok then
            px, py, continent = Num(px), Num(py), Num(continent)
            if px and py then return px, py, continent end
        end
    end
    local mapId = Pos.PlayerMap()
    if mapId and C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
        if ok and type(pos) == "table" then
            local mx, my = pos.x, pos.y
            if (mx == nil or my == nil) and pos.GetXY then mx, my = pos:GetXY() end
            mx, my = Num(mx), Num(my)
            if mx and my then return Pos.World(mapId, mx, my) end
        end
    end
    return nil
end

function Pos.Facing()
    if not GetPlayerFacing then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    return ok and Num(facing) or nil
end

function Pos.PlayerMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and Num(mapId) or nil
end

-- The zone-level map of any map (sub-zones and micro maps go up to their zone).
local zoneCache = {}
function Pos.Zone(uiMapId)
    if not uiMapId then return nil end
    local cached = zoneCache[uiMapId]
    if cached ~= nil then return cached end
    local result, id = uiMapId, uiMapId
    for _ = 1, 6 do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == ZONE_TYPE then result = id; break end
        if info.mapType and info.mapType <= CONTINENT_TYPE then break end
        if not info.parentMapID or info.parentMapID == 0 then break end
        id = info.parentMapID
    end
    zoneCache[uiMapId] = result
    return result
end

function Pos.PlayerZone()
    return Pos.Zone(Pos.PlayerMap())
end

function Pos.MapName(uiMapId)
    local info = uiMapId and C_Map.GetMapInfo(uiMapId)
    local name = info and info.name
    if issecretvalue and issecretvalue(name) then return nil end
    return name
end

-- Yards between two world points on the same continent.
function Pos.Distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Angle to turn (radians, counter-clockwise) from where the player faces to the
-- target, and the distance. nil when the game does not tell.
function Pos.Heading(tx, ty, tContinent)
    local px, py, continent = Pos.Player()
    if not px then return nil, nil, "no position" end
    if tContinent and continent and tContinent ~= continent then return nil, nil, "other continent" end
    local distance = Pos.Distance(px, py, tx, ty)
    local facing = Pos.Facing()
    if not facing then return nil, distance, "no facing" end
    return math.atan2(ty - py, tx - px) - facing, distance
end
