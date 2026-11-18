-- The quest list window.
-- Sections: Route (numbered), Not on the map, Unlocks soon, Not worth it right now,
-- Trivial. Click a section header to fold it. Click a route row to aim the arrow.

local ADDON_NAME, ns = ...

local L = { rows = {} }
ns.List = L

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local WIDTH, HEIGHT = 420, 480
local ROW_HEIGHT, HEADER_HEIGHT = 48, 22

local ACTION = {
    pickup   = "|cffffd100Pick up|r",
    turnin   = "|cff40ff40Turn in|r",
    progress = "|cffb0b0b0Objectives|r",
}

local function WhereText(stop)
    if stop.world then return "World quest" end
    if stop.dungeon then return "|cff9fd0ff" .. stop.dungeon .. "|r" end
    if stop.primary and stop.primary.line.kind == "class" then return "|cffff9f40Class quest|r" end
    return "Questline"
end

local function DistanceText(stop)
    local yards = ns.Planner:DistanceTo(stop)
    if yards then return ("%d yd"):format(yards) end
    if stop.point then
        local info = C_Map.GetMapInfo(stop.point.uiMapId)
        return info and info.name or ""
    end
    return ""
end

local function LevelTag(level)
    if not level or level <= 0 then return "" end
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if color then
        return ("|cff%02x%02x%02x[%d]|r "):format(color.r * 255, color.g * 255, color.b * 255, level)
    end
    return ("[%d] "):format(level)
end

function L:Create()
    local db = ns.db
    local f = CreateFrame("Frame", "ForeverQuestLineNavigatorList", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    local p = db.list.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not db.list.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        db.list.point = { a, b, x, y }
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.04, 0.07, 0.13, 0.92)
    f:SetBackdropBorderColor(0.3, 0.55, 0.9, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff4da6ffQuestLine Navigator|r")

    -- Title bar, right to left: close, minimize, cogwheel, padlock.
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() L:SetShown(false) end)

    local W = ns.Widgets
    local minimize = W.TextButton(f, 18, 18, db.list.minimized and "+" or "-", "Minimize / restore the window",
        function(self)
            L:SetMinimized(not db.list.minimized)
            self.label:SetText(db.list.minimized and "+" or "-")
        end)
    minimize:SetPoint("TOPRIGHT", -32, -8)
    local cog = W.IconButton(f, 18, "Cog", "Settings", function() ns.Settings:Toggle() end)
    cog:SetPoint("RIGHT", minimize, "LEFT", -6, 0)
    local lock = W.LockButton(f, 18, function() return db.list.locked end,
        function(v) db.list.locked = v end, "The window")
    lock:SetPoint("RIGHT", cog, "LEFT", -6, 0)

    -- one line shown while minimized: the next stop
    self.mini = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.mini:SetPoint("TOPLEFT", 12, -34)
    self.mini:SetPoint("RIGHT", -12, 0)
    self.mini:SetJustifyH("LEFT")
    self.mini:SetWordWrap(false)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -34)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 40, 10)
    scroll:SetScrollChild(content)
    self.content = content
    self.scroll = scroll

    self:SetTextSize(db.list.textSize)
    self:SetMinimized(db.list.minimized)
    f:SetShown(db.list.shown)
    C_Timer.NewTicker(2, ns.Safe("list distances", function()
        if f:IsShown() and ns.ready then L:UpdateDistances() end
    end))
end

function L:SetShown(shown)
    ns.db.list.shown = shown
    if self.frame then self.frame:SetShown(shown) end
    if shown then self:Update() end
end

function L:Toggle() self:SetShown(not self.frame:IsShown()) end

local MINIMIZED_HEIGHT = 54

function L:SetMinimized(minimized)
    ns.db.list.minimized = minimized
    local f = self.frame
    self.scroll:SetShown(not minimized)
    self.mini:SetShown(minimized)
    -- keep the title bar where it is: grow / shrink downwards
    local top, left = f:GetTop(), f:GetLeft()
    f:SetHeight(minimized and MINIMIZED_HEIGHT or HEIGHT)
    if top and left then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local a, _, b, x, y = f:GetPoint()
        ns.db.list.point = { a, b, x, y }
    end
    self:Update()
end

function L:UpdateMini()
    local stop = ns.Arrow.target or ns.Planner.route[1]
    if not stop then
        self.mini:SetText("|cff808080No stops right now|r")
        return
    end
    local number = 1
    for i, s in ipairs(ns.Planner.route) do if s == stop then number = i; break end end
    local yards = ns.Planner:DistanceTo(stop)
    self.mini:SetText(("%d. %s%s%s"):format(number, ns.Widgets.StateTag(stop.state), stop.name,
        yards and ("  ·  %d yd"):format(yards) or ""))
end

---------------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------------

local function AddLineDetails(line, index)
    local planner = ns.Planner
    local eval = line.eval
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Questline: " .. planner:LineName(line), 0.6, 0.85, 1)
    if index then GameTooltip:AddLine(planner:StepText(line, index), 0.8, 0.8, 0.8) end
    if eval then
        GameTooltip:AddLine(("%d of %d quests done  ·  %s XP left (%d%% of this level)"):format(
            eval.done, #line.steps, ns.XP.Format(eval.xpRemaining), eval.xpShare * 100), 0.8, 0.8, 0.8)
    end
    if #line.parts > 1 then
        for i, part in ipairs(line.parts) do
            local doneAll = true
            for s = part.first, part.last do
                if not planner:StepDone(line, line.steps[s]) then doneAll = false; break end
            end
            local mark = doneAll and "|cff40ff40done|r" or ""
            GameTooltip:AddLine(("  Part %d: %s  %s"):format(i, part.dungeon or "open world", mark), 0.7, 0.7, 0.7)
        end
    end
    if index then
        local blocker = planner:BlockerText(line, index)
        if blocker then GameTooltip:AddLine(blocker, 1, 0.6, 0.2, true) end
    end
end

local function RowTooltip(row)
    local item = row.item
    if not item or item.header then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    local planner = ns.Planner
    if item.stop then
        local stop = item.stop
        GameTooltip:SetText(stop.name, 1, 1, 1)
        GameTooltip:AddLine(ACTION[stop.state] .. "  ·  " .. WhereText(stop))
        GameTooltip:AddLine(planner:XPText(stop), 1, 0.82, 0)
        if stop.reason then GameTooltip:AddLine("Not on the route: " .. stop.reason, 1, 0.5, 0.3) end
        if stop.leadIn then GameTooltip:AddLine("Grey quest, but it leads into a good questline", 0.8, 0.8, 0.8) end
        if stop.startItem then GameTooltip:AddLine("Starts from an item: " .. stop.startItem, 1, 0.82, 0) end
        if stop.point and stop.point.inside then
            GameTooltip:AddLine("Inside " .. stop.point.inside .. " (the arrow points to the entrance)", 0.8, 0.8, 0.8)
        elseif stop.point and stop.point.note then
            GameTooltip:AddLine("Location: " .. stop.point.note, 0.8, 0.8, 0.8)
        end
        if stop.primary then AddLineDetails(stop.primary.line, stop.primary.index) end
        if item.number then GameTooltip:AddLine("Click: point the arrow here", 0.5, 0.5, 0.5) end
    elseif item.upcoming then
        local u = item.upcoming
        GameTooltip:SetText(u.name, 1, 1, 1)
        GameTooltip:AddLine(("Unlocks at level %d"):format(u.required), 1, 0.82, 0)
        AddLineDetails(u.line, u.index)
    elseif item.line then
        local line = item.line
        GameTooltip:SetText(planner:LineName(line), 1, 1, 1)
        if line.eval.reason then GameTooltip:AddLine("Trivial: " .. line.eval.reason, 0.7, 0.7, 0.7, true) end
        AddLineDetails(line, nil)
    elseif item.message then
        return
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------

function L:GetRow(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.content)
    row:SetSize(WIDTH - 40, ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.badge = row:CreateTexture(nil, "ARTWORK")
    row.badge:SetSize(22, 22)
    row.badge:SetPoint("TOPLEFT", 2, -4)
    row.badge:SetTexture(MEDIA .. "Pin")
    row.number = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.number:SetPoint("CENTER", row.badge, "CENTER", 0, 0)

    local function Line(font)
        local fs = row:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.line1 = Line("GameFontHighlight")
    row.line2 = Line("GameFontDisableSmall")
    row.line3 = Line("GameFontNormalSmall")

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 4, 4)
    self:ApplyFont(row)

    row:SetScript("OnEnter", ns.Safe("list tooltip", RowTooltip))
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if not item then return end
        if item.header then
            ns.db.collapsed[item.section] = not ns.db.collapsed[item.section]
            L:Update()
        elseif item.number then
            ns.Arrow:Pin(item.stop)
        end
    end)
    self.rows[index] = row
    return row
end

-- Text size (Settings): line 1 and headers at the chosen size, lines 2-3 a bit smaller.
local function SetSize(fs, size)
    local font, _, flags = fs:GetFont()
    fs:SetFont(font, size, flags)
end

function L:ApplyFont(row)
    local size = ns.db.list.textSize
    local small = size - 2
    SetSize(row.line1, size)
    SetSize(row.line2, small)
    SetSize(row.line3, small)
    SetSize(row.header, size + 1)
    local y2 = -(3 + size + 3)
    local y3 = y2 - (small + 3)
    for fs, y in pairs({ [row.line1] = -3, [row.line2] = y2, [row.line3] = y3 }) do
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 30, y)
        fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    ROW_HEIGHT = -y3 + small + 6
    HEADER_HEIGHT = size + 12
end

function L:SetTextSize(size)
    ns.db.list.textSize = math.max(9, math.min(18, math.floor(size)))
    for _, row in ipairs(self.rows) do self:ApplyFont(row) end
    SetSize(self.mini, ns.db.list.textSize)
    self:Update()
end

function L:Fill(row, item)
    row.item = item
    row.header:SetText("")
    row.line1:SetText("")
    row.line2:SetText("")
    row.line3:SetText("")
    row.badge:Hide()
    row.number:SetText("")
    row:SetHeight(item.header and HEADER_HEIGHT or ROW_HEIGHT)

    if item.header then
        local folded = ns.db.collapsed[item.section]
        row.header:SetText(("%s %s |cff808080(%d)|r"):format(folded and "+" or "-", item.header, item.count or 0))
        return
    end
    if item.message then
        row:SetHeight(HEADER_HEIGHT)
        row.line1:SetText(item.message)
        return
    end
    local planner = ns.Planner
    if item.stop then
        local stop = item.stop
        local stepText = ""
        if stop.primary and #stop.primary.line.steps > 1 then
            stepText = (" |cff808080(%d/%d)|r"):format(stop.primary.index, #stop.primary.line.steps)
        end
        row.line1:SetText(LevelTag(stop.level) .. ns.Widgets.StateTag(stop.state) .. stop.name .. stepText)
        local parts = ""
        if stop.primary and #stop.primary.line.parts > 1 then
            local line = stop.primary.line
            parts = ("  ·  part %d/%d"):format(line.partOf[stop.questId] or 1, #line.parts)
        end
        row.line2:SetText(ACTION[stop.state] .. "  ·  " .. WhereText(stop) .. parts .. "  ·  " .. DistanceText(stop))
        row.line3:SetText(planner:XPText(stop))
        if item.number then
            row.badge:Show()
            row.number:SetText(item.number)
            local isTarget = ns.Arrow.target == stop
            row.badge:SetVertexColor(1, isTarget and 0.85 or 1, isTarget and 0.2 or 1)
        end
    elseif item.upcoming then
        local u = item.upcoming
        row.line1:SetText(("|cff808080[%d]|r %s"):format(u.required, u.name))
        row.line2:SetText(("Unlocks at level %d  ·  %s"):format(u.required, planner:StepText(u.line, u.index)))
        row.line3:SetText(("Questline: %s  ·  %s XP left"):format(planner:LineName(u.line),
            ns.XP.Format(u.line.eval and u.line.eval.xpRemaining or 0)))
    elseif item.line then
        local line = item.line
        local eval = line.eval
        row.line1:SetText("|cff9d9d9d" .. planner:LineName(line) .. "|r")
        row.line2:SetText(("%d of %d done  ·  %s"):format(eval.done, #line.steps, eval.reason or "grey"))
        row.line3:SetText(("XP left %s (%d%% of this level)"):format(ns.XP.Format(eval.xpRemaining), eval.xpShare * 100))
    end
end

function L:Update()
    if not self.frame or not self.frame:IsShown() or not ns.ready then return end
    if ns.Settings.frame and ns.Settings.frame:IsShown() then ns.Settings:Refresh() end
    if ns.db.list.minimized then
        self:UpdateMini()
        return
    end
    local planner = ns.Planner
    local collapsed = ns.db.collapsed
    local items = {}

    local function Section(key, title, list, make)
        if #list == 0 then return end
        items[#items + 1] = { header = title, section = key, count = #list }
        if collapsed[key] then return end
        for i, entry in ipairs(list) do items[#items + 1] = make(entry, i) end
    end

    Section("route", "Route", planner.route, function(stop, i) return { stop = stop, number = i } end)
    Section("unlocated", "Not on the map", planner.unlocated, function(stop) return { stop = stop } end)
    Section("upcoming", "Unlocks soon", planner.upcoming, function(u) return { upcoming = u } end)
    Section("notWorth", "Not worth it right now", planner.notWorth, function(stop) return { stop = stop } end)
    Section("trivial", "Trivial (grey)", planner.trivial, function(line) return { line = line } end)

    if #items == 0 then
        items[1] = { message = "No dungeon quests found for your level right now." }
        items[2] = { message = "|cff808080Try /fqln ahead 5 to look further ahead.|r" }
    end

    local y = 0
    for i, item in ipairs(items) do
        local row = self:GetRow(i)
        self:Fill(row, item)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()
        y = y + row:GetHeight()
    end
    for i = #items + 1, #self.rows do self.rows[i]:Hide() end
    self.content:SetHeight(math.max(10, y))
end

function L:UpdateDistances()
    if ns.db.list.minimized then
        self:UpdateMini()
        return
    end
    for _, row in ipairs(self.rows) do
        if row:IsShown() and row.item and row.item.stop then self:Fill(row, row.item) end
    end
end
