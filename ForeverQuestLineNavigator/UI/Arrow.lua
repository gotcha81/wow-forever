-- Navigation to route stop #1 (or the stop you clicked):
--  * the blue arrow: turns with you, turns green when you face the right way,
--    shows what to do, where, and how far. Hover it for a padlock (pin its
--    position), text size buttons and a hide button.
-- Hidden inside instances.

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
    f:SetScript("OnDragStart", function(self)
        if not db.arrowFrame.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        db.arrowFrame.point = { a, b, x, y }
    end)
    f:SetScript("OnClick", function() A:Hide() end)
    f:SetScript("OnEnter", function() A:ShowControls() end)

    -- Hover bar: padlock, text smaller / larger, hide.
    local W = ns.Widgets
    local bar = CreateFrame("Frame", nil, f)
    bar:SetSize(104, 20)
    bar:SetPoint("BOTTOM", f, "TOP", 0, 2)
    bar:Hide()
    f.bar = bar
    local lock = W.LockButton(bar, 18, function() return db.arrowFrame.locked end,
        function(v) db.arrowFrame.locked = v end, "The arrow")
    lock:SetPoint("LEFT", 0, 0)
    local smaller = W.TextButton(bar, 26, 18, "A-", "Smaller text", function() A:SetTextSize(db.arrowFrame.textSize - 1) end)
    smaller:SetPoint("LEFT", lock, "RIGHT", 4, 0)
    local larger = W.TextButton(bar, 26, 18, "A+", "Larger text", function() A:SetTextSize(db.arrowFrame.textSize + 1) end)
    larger:SetPoint("LEFT", smaller, "RIGHT", 2, 0)
    local hide = W.TextButton(bar, 20, 18, "x", "Hide the arrow (/fqln arrow on, or the list's Arrow box, shows it again)",
        function() A:Hide() end)
    hide:SetPoint("LEFT", larger, "RIGHT", 4, 0)
    -- the bar stays while the mouse is over the arrow or the bar
    bar:SetScript("OnUpdate", function(self, dt)
        self.idle = (MouseIsOver(f) or MouseIsOver(self)) and 0 or (self.idle or 0) + dt
        if self.idle > 0.4 then self:Hide() end
    end)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture(ARROW_TEXTURE)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.where = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.where:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.info:SetPoint("TOP", f.where, "BOTTOM", 0, -2)

    self:SetTextSize(db.arrowFrame.textSize)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.03 then return end
        elapsed = 0
        A:Tick()
    end)
    f:Hide()
end

local MIN_TEXT, MAX_TEXT = 8, 24

function A:SetTextSize(size)
    size = math.max(MIN_TEXT, math.min(MAX_TEXT, math.floor(size)))
    ns.db.arrowFrame.textSize = size
    local f = self.frame
    local font, _, flags = GameFontNormal:GetFont()
    f.title:SetFont(font, size, flags)
    f.where:SetFont(font, math.max(MIN_TEXT, size - 2), flags)
    f.info:SetFont(font, size, flags)
end

function A:ShowControls()
    self.frame.bar.idle = 0
    self.frame.bar:Show()
end

function A:Hide()
    ns.db.arrow = false
    self:UpdateVisibility()
    ns.List:Update()
    ns.Print("arrow hidden. Tick 'Arrow' in the list, or type /fqln arrow on, to show it again.")
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
end

-- The game-waypoint option (Retail-style marker) was removed in 0.2.x: Forever
-- accepts the waypoint but never draws it. The code is in git history (commit
-- 08ba4f1, UI/Arrow.lua, A:UpdateGameWaypoint); /fqln debug still checks the API.
-- Players who had it on still have our old waypoint set: clear it once.
function A:ClearOldGameWaypoint()
    if ns.db.gameWaypoint == nil then return end
    if ns.db.gameWaypoint and C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    ns.db.gameWaypoint = nil
end

function A:Tick()
    local f, stop = self.frame, self.target
    if not stop or not stop.point then f:Hide(); return end
    local point = stop.point

    local number = 1
    for i, s in ipairs(ns.Planner.route) do if s == stop then number = i; break end end
    f.title:SetText(("%d. %s%s: %s"):format(number, ns.Widgets.StateTag(stop.state), ACTION[stop.state] or "", stop.name))
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
