-- Navigation to route stop #1 (or the stop you clicked):
--  * the blue arrow: turns with you, turns green when you face the right way,
--    shows what to do, where, and how far;
--  * optional: the game's own waypoint (Retail-style map pin + in-world marker).
--    Off by default, because the waypoint API is reported unreliable on Forever.
-- Both are hidden / cleared inside instances.

local ADDON_NAME, ns = ...

local ARROW_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Arrow"

local A = {}
ns.Arrow = A

local ACTION = { pickup = "Pick up", turnin = "Turn in", progress = "Do objectives" }
local ARRIVED_YARDS = 10
local ON_COURSE = math.rad(15)

function A:Create()
    local db = ns.db
    local f = CreateFrame("Button", "ForeverQuestLineNavigatorArrow", UIParent)
    self.frame = f
    f:SetSize(64, 64)
    local p = db.arrowFrame.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("RightButtonUp")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        db.arrowFrame.point = { a, b, x, y }
    end)
    f:SetScript("OnClick", function()
        db.arrow = false
        A:UpdateVisibility()
        ns.Print("arrow hidden. Type /fqln arrow on to show it again.")
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("QuestLine Navigator", 0.3, 0.65, 1)
        GameTooltip:AddLine("Drag to move. Right-click to hide.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture(ARROW_TEXTURE)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.where = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.where:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.info:SetPoint("TOP", f.where, "BOTTOM", 0, -2)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.03 then return end
        elapsed = 0
        A:Tick()
    end)
    f:Hide()
end

-- Called after each route update. Keeps a clicked stop if it is still on the route.
function A:SetTarget(defaultStop)
    local target = defaultStop
    local pinned = self.pinned
    if pinned then
        local found
        for _, stop in ipairs(ns.Planner.route) do
            if stop.questId == pinned.questId and stop.state == pinned.state then found = stop; break end
        end
        if found then target = found else self.pinned = nil end
    end
    self.target = target
    self:UpdateVisibility()
end

-- Point at a specific stop (clicked in the list or on a pin).
function A:Pin(stop)
    self.pinned = { questId = stop.questId, state = stop.state }
    self.target = stop
    self:UpdateVisibility()
    ns.Pins:Update()
    ns.List:Update()
end

function A:UpdateVisibility()
    if not self.frame then return end
    local inInstance = IsInInstance()
    local hasTarget = self.target ~= nil and self.target.point ~= nil
    self.frame:SetShown(ns.db.arrow and hasTarget and not inInstance)
    self:UpdateGameWaypoint(hasTarget and not inInstance and ns.db.gameWaypoint)
end

-- Optional: the game's own waypoint and super-tracking (Retail-style marker).
function A:UpdateGameWaypoint(enabled)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return end
    local point = enabled and self.target and self.target.point
    if not point then
        if self.waypointSet then
            pcall(C_Map.ClearUserWaypoint)
            self.waypointSet = nil
        end
        return
    end
    local key = point.uiMapId .. ":" .. point.x .. ":" .. point.y
    if self.waypointSet == key then return end
    local okMap = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(point.uiMapId)
    if not okMap then return end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(point.uiMapId, point.x, point.y))
    if ok then
        self.waypointSet = key
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
end

function A:Tick()
    local f, stop = self.frame, self.target
    if not stop or not stop.point then f:Hide(); return end
    local point = stop.point

    local number = 1
    for i, s in ipairs(ns.Planner.route) do if s == stop then number = i; break end end
    f.title:SetText(("%d. %s: %s"):format(number, ACTION[stop.state] or "", stop.name))
    local zone = ns.Pos.MapName(point.zone or point.uiMapId) or ""
    f.where:SetText(point.inside and (point.inside .. " entrance, " .. zone) or zone)

    local turn, distance, problem = ns.Pos.Heading(point.wx, point.wy, point.instance)
    if problem == "other continent" then
        f.tex:SetRotation(0)
        f.tex:SetVertexColor(0.5, 0.5, 0.5)
        f.info:SetText("|cffaaaaaaOn another continent: take a boat, zeppelin or portal|r")
        return
    end
    if not distance then
        f.tex:SetVertexColor(0.5, 0.5, 0.5)
        f.info:SetText("|cffaaaaaaPosition unknown here|r")
        return
    end
    if distance <= ARRIVED_YARDS then
        f.tex:SetRotation(0)
        f.tex:SetVertexColor(0.3, 1, 0.3)
        f.info:SetText(point.inside and ("|cff40ff40At the entrance of " .. point.inside .. "|r")
            or "|cff40ff40You are there|r")
        return
    end
    if turn then
        f.tex:SetRotation(turn)
        -- normalise to -pi..pi to see whether we are on course
        local off = (turn + math.pi) % (2 * math.pi) - math.pi
        if math.abs(off) <= ON_COURSE then
            f.tex:SetVertexColor(0.45, 1, 0.45)
        else
            f.tex:SetVertexColor(1, 1, 1)
        end
    else
        f.tex:SetRotation(0)
        f.tex:SetVertexColor(0.5, 0.5, 0.5)
    end
    f.info:SetText(("%d yd"):format(distance))
end
