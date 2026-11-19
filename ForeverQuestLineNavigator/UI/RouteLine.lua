-- Route line on the world map: from you to stop 1, then 2, 3 ... in route order,
-- under the numbered pins. Works on Blizzard's map and on OpenMap's stitched map
-- (through OpenMap's public API, OpenMapAPI.CanvasFromWorldPos, when it is installed).
--
-- The lines live in our own frame on the map canvas; nothing of Blizzard's or
-- OpenMap's is changed. A segment that changes continent (boat, zeppelin, portal)
-- is left out. Setting: "Route line on the world map" (db.routeLine).

local _, ns = ...

local RL = { lines = {} }
ns.RouteLine = RL

local COLOR      = { 0.30, 0.65, 1.00, 0.80 } -- the addon's blue
local COLOR_NEXT = { 1.00, 0.85, 0.20, 0.90 } -- you -> stop 1: the arrow's gold
local THICKNESS  = 3     -- screen pixels
local REDRAW     = 0.1   -- seconds between redraws while the map is open

local function OpenMapStitched()
    local api = _G.OpenMapAPI
    if type(api) ~= "table" or type(api.IsStitched) ~= "function" then return nil end
    local ok, stitched = pcall(api.IsStitched)
    return ok and stitched and api or nil
end

-- World position (yards, continent) -> canvas position (0-1 of the canvas).
local function ToCanvas(api, wx, wy, continent)
    if not (wx and wy and continent) then return nil end
    if api then
        local ok, x, y = pcall(api.CanvasFromWorldPos, continent, wx, wy)
        if ok and type(x) == "number" and type(y) == "number" then return x, y end
        return nil
    end
    local mapId = WorldMapFrame:GetMapID()
    if not (mapId and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(wx, wy), mapId)
    if not ok or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
    x, y = ns.Pos.Num(x), ns.Pos.Num(y)
    if not x or not y then return nil end
    return x, y
end

-- Cuts the segment to the box lo..hi (Liang-Barsky). nil when it is all outside.
local function Clip(x1, y1, x2, y2, lo, hi)
    local t0, t1 = 0, 1
    local dx, dy = x2 - x1, y2 - y1
    local checks = { { -dx, x1 - lo }, { dx, hi - x1 }, { -dy, y1 - lo }, { dy, hi - y1 } }
    for _, c in ipairs(checks) do
        local p, q = c[1], c[2]
        if p == 0 then
            if q < 0 then return nil end
        else
            local r = q / p
            if p < 0 then
                if r > t1 then return nil end
                if r > t0 then t0 = r end
            else
                if r < t0 then return nil end
                if r < t1 then t1 = r end
            end
        end
    end
    return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

function RL:Create()
    if not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
    local canvas = WorldMapFrame:GetCanvas()
    if not canvas then return end
    local f = CreateFrame("Frame", nil, canvas)
    f:SetAllPoints(canvas)
    self.frame, self.canvas = f, canvas
    local elapsed = REDRAW
    local SafeDraw = ns.Safe("route line", function() RL:Draw() end)
    f:SetScript("OnUpdate", function(_, dt) -- only runs while the map is open
        elapsed = elapsed + dt
        if elapsed < REDRAW then return end
        elapsed = 0
        SafeDraw()
    end)
    f:SetScript("OnShow", function() elapsed = REDRAW end)

    -- Tells the quest markers when the map closed (Esc closes the map first,
    -- the markers only on the next Esc; see UI/QuestMarkers.lua).
    local watch = CreateFrame("Frame", nil, WorldMapFrame)
    watch:SetScript("OnHide", function() ns.mapHiddenAt = GetTime() end)
end

function RL:Line(i)
    local line = self.lines[i]
    if not line then
        line = self.frame:CreateLine(nil, "OVERLAY")
        self.lines[i] = line
    end
    return line
end

-- Under the route pins (HereBeDragons puts them at "area POI" level), over the map art.
function RL:FrameLevel(api)
    local level
    local ok, manager = pcall(WorldMapFrame.GetPinFrameLevelsManager, WorldMapFrame)
    if ok and manager and manager.GetValidFrameLevel then
        local ok2, value = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_AREA_POI")
        if ok2 and type(value) == "number" then level = value - 1 end
    end
    level = level or (self.canvas:GetFrameLevel() + 10)
    if api and type(api.ArtTopLevel) == "function" then
        local okArt, top = pcall(api.ArtTopLevel)
        if okArt and type(top) == "number" and top >= level then level = top + 1 end
    end
    return level
end

function RL:Draw()
    local used = 0
    local canvas = self.canvas
    local width, height = canvas:GetSize()
    if ns.ready and ns.db.routeLine and width and width > 0 and height and height > 0 then
        local api = OpenMapStitched()
        self.frame:SetFrameLevel(self:FrameLevel(api))
        local okScale, scale = pcall(WorldMapFrame.GetCanvasScale, WorldMapFrame)
        local thickness = THICKNESS / ((okScale and type(scale) == "number" and scale > 0) and scale or 1)
        -- OpenMap shows the world beyond the map's own rectangle; Blizzard's map does not
        local lo, hi = 0, 1
        if api then lo, hi = -4, 5 end

        -- you, then each stop shown on the map (the same ones the pins show)
        local points = {}
        local px, py, pc = ns.Pos.Player()
        points[1] = { px, py, pc, player = true }
        for _, stop in ipairs(ns.Planner.route) do
            local p = stop.point
            local hidden = stop.trivial and not ns.Planner.InLog(stop.questId)
            if not hidden and p and p.wx and p.wy then points[#points + 1] = { p.wx, p.wy, p.instance } end
        end

        for i = 1, #points - 1 do
            local a, b = points[i], points[i + 1]
            if a[3] and b[3] and a[3] == b[3] then
                local x1, y1 = ToCanvas(api, a[1], a[2], a[3])
                local x2, y2 = ToCanvas(api, b[1], b[2], b[3])
                if x1 and x2 then
                    x1, y1, x2, y2 = Clip(x1, y1, x2, y2, lo, hi)
                end
                if x1 and x2 and (math.abs(x2 - x1) * width + math.abs(y2 - y1) * height) > 1 then
                    used = used + 1
                    local line = self:Line(used)
                    local color = a.player and COLOR_NEXT or COLOR
                    line:SetColorTexture(color[1], color[2], color[3], color[4])
                    line:SetThickness(thickness)
                    line:SetStartPoint("TOPLEFT", canvas, x1 * width, -y1 * height)
                    line:SetEndPoint("TOPLEFT", canvas, x2 * width, -y2 * height)
                    line:Show()
                end
            end
        end
    end
    for i = used + 1, #self.lines do self.lines[i]:Hide() end
end
