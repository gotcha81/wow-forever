-- The quest list window, three tabs:
--  Route:   Route (numbered), Not on the map, Unlocks soon, Not worth it right now,
--           Trivial, Ignored.
--  Dungeon: pick a dungeon, see all its quests and what you are missing.
--  NPCs:    search friendly NPCs and mark one on the map (UI/NpcFinder.lua).
-- Click a section header to fold it. Click a row to aim the arrow.
-- Right-click a quest to ignore its questline (right-click in Ignored to bring it back).

local ADDON_NAME, ns = ...

local L = { rows = {}, expanded = {} } -- expanded[chainKey] = true while a questline is open
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

    -- Tabs, and the dungeon picker button (Dungeon tab only)
    local function Tab(label, key)
        local b = W.TextButton(f, 64, 18, label, label, function()
            db.list.tab = key
            L.picking = false
            L:Update()
        end)
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
        return b
    end
    self.tabRoute = Tab("Route", "route")
    self.tabRoute:SetPoint("TOPLEFT", 10, -32)
    self.tabDungeon = Tab("Dungeon", "dungeon")
    self.tabDungeon:SetPoint("LEFT", self.tabRoute, "RIGHT", 4, 0)
    self.tabNpc = Tab("NPCs", "npc")
    self.tabNpc:SetPoint("LEFT", self.tabDungeon, "RIGHT", 4, 0)
    self.picker = W.TextButton(f, WIDTH - 238, 18, "", "Choose a dungeon", function()
        L.picking = not L.picking
        L:Update()
    end)
    self.picker:SetPoint("LEFT", self.tabNpc, "RIGHT", 8, 0)
    self.picker.label:ClearAllPoints()
    self.picker.label:SetPoint("LEFT", 6, 0)
    self.picker.label:SetPoint("RIGHT", -6, 0)
    self.picker.label:SetJustifyH("LEFT")
    self.picker.label:SetWordWrap(false)

    -- Search box: quests on the Route and Dungeon tabs, NPCs on the NPCs tab.
    local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 10, -54)
    box:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    box:SetHeight(20)
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.3, 0.55, 0.9, 1)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 22, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 7, 0)
    self.placeholder = placeholder
    local clear = W.TextButton(box, 16, 16, "x", "Clear the search", function()
        box:SetText("")
        box:ClearFocus()
    end)
    clear:SetPoint("RIGHT", -2, 0)
    clear:Hide()
    local pending
    box:SetScript("OnTextChanged", ns.Safe("search box", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "" and not self:HasFocus())
        clear:SetShown(text ~= "")
        if pending then pending:Cancel() end
        pending = C_Timer.NewTimer(0.3, ns.Safe("search", function()
            L.searchText = text:match("^%s*(.-)%s*$")
            L:Update() -- builds the quest or NPC index the first time (see Update)
        end))
    end))
    box:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) placeholder:SetShown((self:GetText() or "") == "") end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.searchBox = box
    -- the search starts empty each time the window opens
    f:SetScript("OnHide", function() box:SetText(""); L.searchText = nil; L.showGrey = false end)

    -- one line shown while minimized: the next stop
    self.mini = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.mini:SetPoint("TOPLEFT", 12, -34)
    self.mini:SetPoint("RIGHT", -12, 0)
    self.mini:SetJustifyH("LEFT")
    self.mini:SetWordWrap(false)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -80)
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
    self.tabRoute:SetShown(not minimized)
    self.tabDungeon:SetShown(not minimized)
    self.tabNpc:SetShown(not minimized)
    self.picker:SetShown(not minimized and ns.db.list.tab == "dungeon")
    self.searchBox:SetShown(not minimized)
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
        GameTooltip:AddLine("Right-click: ignore this questline", 0.5, 0.5, 0.5)
    elseif item.entry then
        local e = item.entry
        GameTooltip:SetText(e.name, 1, 1, 1)
        GameTooltip:AddLine(L.EntryStatus(e), 1, 0.82, 0, true)
        GameTooltip:AddLine(L.EntryXP(e), 1, 0.82, 0)
        if e.line then AddLineDetails(e.line, e.lineIndex) end
        if e.stop and e.stop.point then
            if e.stop.point.inside then
                GameTooltip:AddLine("Inside " .. e.stop.point.inside .. " (the arrow points to the entrance)", 0.8, 0.8, 0.8)
            end
            GameTooltip:AddLine("Click: point the arrow there", 0.5, 0.5, 0.5)
        end
        if e.state ~= "done" then
            GameTooltip:AddLine(e.ignored and "Right-click: bring it back" or "Right-click: ignore this questline",
                0.5, 0.5, 0.5)
        end
    elseif item.dungeonPick then
        local d = item.dungeonPick
        GameTooltip:SetText(d.name, 1, 1, 1)
        GameTooltip:AddLine(("%d quests in total"):format(#d.quests), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click: show its quests", 0.5, 0.5, 0.5)
    elseif item.toggleGrey then
        GameTooltip:SetText(L.showGrey and "Hide grey quests" or "Show grey quests too", 1, 1, 1)
        GameTooltip:AddLine("Grey quests give little XP at your level and lead to nothing worth it.", 0.8, 0.8, 0.8, true)
    elseif item.ignoredEntry then
        GameTooltip:SetText(tostring(item.ignoredEntry.name), 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Ignored on this character", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: bring it back", 0.5, 0.5, 0.5)
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
    elseif item.chainStep then
        local c = item.chainStep
        local start, finish = ns.DungeonView:Ends(c.id)
        GameTooltip:SetText(planner:QuestName(c.id), 1, 1, 1)
        GameTooltip:AddLine(("Step %d of %d  ·  %s"):format(c.index, #c.line.steps, planner:LineName(c.line)), 0.6, 0.85, 1)
        GameTooltip:AddLine("Starts: " .. (start or "not known"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Ends: " .. (finish or "not known"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L.ChainXP(c.id), 1, 0.82, 0)
        local blocker = planner:BlockerText(c.line, c.index)
        if blocker then GameTooltip:AddLine(blocker, 1, 0.6, 0.2, true) end
        if L.ChainState(c) ~= "done" then GameTooltip:AddLine("Click: point the arrow there", 0.5, 0.5, 0.5) end
    elseif item.npc then
        local n = item.npc
        GameTooltip:SetText(n.name, 0.4, 1, 0.4)
        if n.sub then GameTooltip:AddLine("<" .. n.sub .. ">", 1, 1, 1) end
        if n.minLevel then
            GameTooltip:AddLine(n.minLevel == n.maxLevel and ("Level %d"):format(n.minLevel)
                or ("Level %d-%d"):format(n.minLevel, n.maxLevel or n.minLevel), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(("%d %s on the map"):format(#n.points, #n.points == 1 and "place" or "places"), 0.8, 0.8, 0.8)
        if n.nearest and n.nearest.inside then GameTooltip:AddLine("Inside " .. n.nearest.inside, 0.8, 0.8, 0.8) end
        local sources = {}
        for _, p in ipairs(n.points) do
            if p.source and not sources[p.source] then
                sources[p.source] = true
                GameTooltip:AddLine("Position: " .. p.source, 0.8, 0.8, 0.8)
            end
        end
        local url = ns.NpcFinder.WowheadUrl(n.id)
        if url then GameTooltip:AddLine(url, 0.6, 0.85, 1) end
        GameTooltip:AddLine(url and "Click: mark on the map  ·  Shift-click: Wowhead link to copy"
            or "Click: mark on the map", 0.5, 0.5, 0.5, true)
    elseif item.npcMarked then
        local stop = item.npcMarked
        GameTooltip:SetText(stop.name, 0.4, 1, 0.4)
        GameTooltip:AddLine(ns.NpcFinder.keep and "Kept until you talk to this NPC, or remove it"
            or "Removed by Esc, by marking another NPC, or when you talk to it", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Click: point the arrow here  ·  Right-click: remove", 0.5, 0.5, 0.5)
    elseif item.npcKeep then
        GameTooltip:SetText("Keep pinned", 1, 1, 1)
        GameTooltip:AddLine("The marker stays through Esc and /reload, until you talk to the NPC or remove it.",
            0.8, 0.8, 0.8, true)
    elseif item.npcRemove then
        GameTooltip:SetText("Remove the marker", 1, 1, 1)
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

    -- +/- : show / hide every quest of the questline under this row
    row.expand = ns.Widgets.TextButton(row, 16, 16, "+", "Show / hide the whole questline", function(self)
        local key = self:GetParent().item and self:GetParent().item.chainKey
        if not key then return end
        L.expanded[key] = not L.expanded[key] or nil
        L:Update()
    end)
    row.expand:SetPoint("TOPRIGHT", -2, -3)
    row.expand:Hide()
    self:ApplyFont(row)

    row:SetScript("OnEnter", ns.Safe("list tooltip", RowTooltip))
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", ns.Safe("list click", function(self, button)
        local item = self.item
        if not item then return end
        if button == "RightButton" then
            if item.stop then
                ns.Ignore:AskIgnoreStop(item.stop)
            elseif item.entry and item.entry.state ~= "done" then
                if item.entry.ignored then
                    ns.Ignore:RestoreQuest(item.entry.questId)
                    ns.Print(('"%s" is back.'):format(item.entry.name))
                    ns.RequestRefresh(0)
                else
                    ns.Ignore:AskIgnoreQuest(item.entry.questId)
                end
            elseif item.ignoredEntry then
                ns.Ignore:AskRestore(item.ignoredEntry)
            elseif item.npcMarked then
                ns.NpcFinder:Unmark()
            end
            return
        end
        if item.header then
            if item.section == "search" then return end
            ns.db.collapsed[item.section] = not ns.db.collapsed[item.section]
            L:Update()
        elseif item.toggleGrey then
            L.showGrey = not L.showGrey
            L:Update()
        elseif item.number then
            ns.Arrow:Pin(item.stop)
        elseif item.entry and item.entry.stop and item.entry.stop.point then
            ns.Arrow:Pin(item.entry.stop)
        elseif item.dungeonPick then
            ns.db.list.dungeon = item.dungeonPick.name
            L.picking = false
            L:Update()
        elseif item.chainStep then
            local c = item.chainStep
            local state = L.ChainState(c)
            if state ~= "done" then
                local stop = ns.DungeonView.MakeStop(c.id, state == "todo" and "pickup" or state)
                if stop.point then ns.Arrow:Pin(stop) else ns.Print("no map position known for that quest.") end
            end
        elseif item.npc then
            if IsShiftKeyDown() then
                ns.NpcFinder:ShareUrl(item.npc.id)
            else
                ns.NpcFinder:Mark(item.npc.id, ns.db.list.npcKeep)
            end
        elseif item.npcMarked then
            ns.NpcFinder.arrowOff = false
            ns.Arrow:SetTarget(ns.Planner.route[1])
            ns.List:Update()
        elseif item.npcKeep then
            ns.db.list.npcKeep = not ns.db.list.npcKeep
            ns.NpcFinder:SetKeep(ns.db.list.npcKeep)
            L:Update()
        elseif item.npcRemove then
            ns.NpcFinder:Unmark()
        end
    end))
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
    row.line1:SetPoint("RIGHT", row, "RIGHT", -22, 0) -- room for the +/- button
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
    row.expand:SetShown(item.chainKey ~= nil)
    if item.chainKey then row.expand.label:SetText(L.expanded[item.chainKey] and "-" or "+") end
    if item.chainStep then
        self:FillChainStep(row, item.chainStep)
        return
    end

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
    if item.toggleGrey then
        row:SetHeight(HEADER_HEIGHT)
        row.header:SetText(("|cff9d9d9d%s %d grey (trivial) %s|r"):format(L.showGrey and "-" or "+",
            item.count, item.count == 1 and "quest" or "quests"))
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
    elseif item.entry then
        local e = item.entry
        local step = ""
        if e.lineIndex and e.line then
            step = (" |cff808080(%d/%d)|r"):format(e.lineIndex, #e.line.steps)
        end
        local grey = e.state == "done" or e.ignored
        row.line1:SetText(LevelTag(e.level) .. L.EntryTag(e) .. (grey and ("|cff9d9d9d" .. e.name .. "|r") or e.name) .. step)
        local status = L.EntryStatus(e)
        local yards = e.stop and ns.Planner:DistanceTo(e.stop)
        if yards then status = status .. ("  ·  %d yd"):format(yards) end
        row.line2:SetText(status)
        row.line3:SetText(L.EntryXP(e))
        local target = ns.Arrow.target
        if e.stop and target and target.questId == e.stop.questId and target.state == e.stop.state then
            row.badge:Show()
            row.badge:SetVertexColor(1, 0.85, 0.2)
        end
    elseif item.dungeonPick then
        local d = item.dungeonPick
        local range = ""
        if d.min then
            range = d.min == d.max and ("[%d]"):format(d.min) or ("[%d-%d]"):format(d.min, d.max)
            local color = GetQuestDifficultyColor and GetQuestDifficultyColor(math.floor((d.min + d.max) / 2))
            if color then range = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, range) end
        end
        local selected = d.name == ns.db.list.dungeon and "|cff4da6ff> |r" or ""
        row.line1:SetText(selected .. range .. " " .. d.name)
        local open = ns.DungeonView:OpenCount(d)
        local recommended = ns.Planner.recommended and ns.Planner.recommended[d.name]
        row.line2:SetText((open > 0 and ("%d %s for you now"):format(open, open == 1 and "quest" or "quests")
            or "nothing for you right now") .. (recommended and "  ·  |cff40ff40recommended|r" or ""))
    elseif item.npc then
        self:FillNpc(row, item.npc)
    elseif item.npcMarked then
        local stop = item.npcMarked
        local yards = ns.Planner:DistanceTo(stop)
        local zone = stop.point and ns.Pos.MapName(stop.point.zone or stop.point.uiMapId) or ""
        row.line1:SetText("|cff60ff60Marked:|r " .. stop.name .. (stop.npc.sub and ("  |cffb0b0b0<" .. stop.npc.sub .. ">|r") or ""))
        row.line2:SetText(zone .. (yards and ("  ·  %d yd"):format(yards) or "")
            .. (ns.NpcFinder.arrowOff and "  ·  |cff808080click to point the arrow here|r" or "  ·  the arrow points here"))
        row.line3:SetText(ns.NpcFinder.keep and "Kept until you talk to it  ·  right-click to remove"
            or "Esc or right-click removes it")
        row.badge:Show()
        row.badge:SetVertexColor(0.35, 1, 0.35)
    elseif item.npcKeep then
        row:SetHeight(HEADER_HEIGHT)
        row.header:SetText((ns.db.list.npcKeep and "|cff40ff40[x]|r" or "|cff808080[  ]|r") .. " Keep pinned until I talk to the NPC")
    elseif item.npcRemove then
        row:SetHeight(HEADER_HEIGHT)
        row.header:SetText("|cffff6060x|r Remove the marker")
    elseif item.ignoredEntry then
        local entry = item.ignoredEntry
        row.line1:SetText("|cff9d9d9d" .. tostring(entry.name) .. "|r")
        row.line2:SetText((entry.kind == "line" and "Ignored questline" or "Ignored quest") .. "  ·  right-click to bring it back")
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
    local tab = ns.db.list.tab
    if tab ~= "dungeon" and tab ~= "npc" then tab = "route" end
    self:StyleTabs(tab)

    if tab == "npc" then
        self:NpcItems(items)
        self:Layout(items)
        return
    end

    local function Section(key, title, list, make)
        if #list == 0 then return end
        items[#items + 1] = { header = title, section = key, count = #list }
        if collapsed[key] then return end
        for i, entry in ipairs(list) do items[#items + 1] = make(entry, i) end
    end

    if self.searchText and self.searchText ~= "" then
        if not ns.Search.ready then ns.Search:Build(function() L:Update() end) end
        self:SearchItems(items)
        self:Layout(items)
        return
    end

    if tab == "dungeon" then
        self:DungeonItems(items, Section)
        self:Layout(self:WithChains(items))
        return
    end

    Section("route", "Route", planner.route, function(stop, i) return { stop = stop, number = i } end)
    Section("unlocated", "Not on the map", planner.unlocated, function(stop) return { stop = stop } end)
    Section("upcoming", "Unlocks soon", planner.upcoming, function(u) return { upcoming = u } end)
    Section("notWorth", "Not worth it right now", planner.notWorth, function(stop) return { stop = stop } end)
    Section("trivial", "Trivial (grey)", planner.trivial, function(line) return { line = line } end)
    Section("ignored", "Ignored", ns.Ignore:List(), function(entry) return { ignoredEntry = entry } end)

    if #items == 0 then
        items[1] = { message = "No dungeon quests found for your level right now." }
        items[2] = { message = "|cff808080Try /fqln ahead 5 to look further ahead.|r" }
    end
    self:Layout(self:WithChains(items))
end

function L:Layout(items)
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
        local item = row:IsShown() and row.item
        if item and (item.stop or item.entry or item.npc or item.npcMarked) then self:Fill(row, item) end
    end
end

---------------------------------------------------------------------------------------
-- Dungeon tab
---------------------------------------------------------------------------------------

function L:StyleTabs(tab)
    for key, b in pairs({ route = self.tabRoute, dungeon = self.tabDungeon, npc = self.tabNpc }) do
        local on = key == tab
        b:SetBackdropBorderColor(on and 0.3 or 0.25, on and 0.55 or 0.3, on and 0.9 or 0.4, 1)
        b.label:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
    end
    self.picker:SetShown(tab == "dungeon" and not ns.db.list.minimized)
    self.placeholder:SetText(tab == "npc" and "Search friendly NPCs: name, title (flight master, innkeeper), zone"
        or "Search quests, questlines, dungeons, zones, NPCs")
    local name = ns.db.list.dungeon
    self.picker.label:SetText((self.picking and "|cff4da6ffChoose a dungeon:|r" or (name or "Choose a dungeon"))
        .. "  |cff808080v|r")
end

local ENTRY_TAG = {
    done        = "|cff40c040[Done]|r ",
    chain       = "|cff4dc3ff[On the chain]|r ",
    missing     = "|cffff9f40[Missing chain]|r ",
    locked      = "|cff808080[Locked]|r ",
    unavailable = "|cff808080[Not available]|r ",
}

function L.EntryTag(e)
    if e.ignored then return "|cff808080[Ignored]|r " end
    return ENTRY_TAG[e.state] or ns.Widgets.StateTag(e.state)
end

local function WhereStarts(e)
    local zone = e.stop and e.stop.point and ns.Pos.MapName(e.stop.point.zone or e.stop.point.uiMapId)
    local parts = {}
    if e.starter then parts[#parts + 1] = e.starter end
    if zone then parts[#parts + 1] = zone end
    if #parts == 0 then return "start not on the map" end
    return "starts at " .. table.concat(parts, ", ")
end

function L.EntryStatus(e)
    if e.state == "done" then return "Done" end
    if e.state == "turnin" then return "|cff40ff40Turn in|r" end
    if e.state == "progress" then return "On this quest: do the objectives" end
    if e.state == "chain" then
        return ("On step %d of %d: %s"):format(e.missingIndex, e.chainLength, e.missingName)
    end
    if e.state == "pickup" then return "|cffffd100Pick up|r  ·  " .. WhereStarts(e) end
    if e.state == "missing" then
        return ("Missing: start with %s (step %d of %d)  ·  %s"):format(e.missingName, e.missingIndex,
            e.chainLength, WhereStarts(e))
    end
    if e.state == "locked" then
        if e.missingId and e.missingId ~= e.questId then
            return ("Unlocks at level %d (first: %s, step %d of %d)"):format(e.required, e.missingName,
                e.missingIndex, e.chainLength)
        end
        return ("Unlocks at level %d"):format(e.required)
    end
    if e.state == "unavailable" then return "Not available: you did or took a quest that excludes it" end
    return ""
end

function L.EntryXP(e)
    local fmt = ns.XP.Format
    local text = "XP quest " .. (e.xpEstimate and "~" or "") .. fmt(e.xp)
    if e.lineRemaining then
        if e.lineStarted then
            text = text .. (" (Questchain remaining %s)"):format(fmt(e.lineRemaining))
        else
            text = text .. (" (Total questchain %s)"):format(fmt(e.lineTotal))
        end
    end
    return text
end

---------------------------------------------------------------------------------------
-- Search results
---------------------------------------------------------------------------------------

local MAX_ROWS = 60

function L:SearchItems(items)
    local S = ns.Search
    if not S.ready then
        items[1] = { message = "|cff808080Building the quest index...|r" }
        return
    end
    local r = S:Find(self.searchText)
    local shown = #r.open + (self.showGrey and #r.grey or 0)
    items[#items + 1] = { header = ("Search: \"%s\""):format(self.searchText), section = "search",
                          count = #r.open }
    for i, e in ipairs(r.open) do
        if i > MAX_ROWS then break end
        items[#items + 1] = { entry = e }
    end
    if #r.open == 0 then
        items[#items + 1] = { message = #r.grey > 0 and "|cff808080Only grey quests match.|r"
            or "|cff808080No quests match.|r" }
    end
    if #r.grey > 0 then
        items[#items + 1] = { toggleGrey = true, count = #r.grey }
        if self.showGrey then
            for i, e in ipairs(r.grey) do
                if i > MAX_ROWS then break end
                items[#items + 1] = { entry = e }
            end
        end
    end
    if r.capped or #r.open > MAX_ROWS or (self.showGrey and #r.grey > MAX_ROWS) then
        items[#items + 1] = { message = ("|cff808080%d quests match, not all are shown. Type more to narrow it.|r")
            :format(r.total) }
    end
end

function L:DungeonItems(items, Section)
    local DV = ns.DungeonView
    local name = ns.db.list.dungeon
    if self.picking or not name or not DV:Find(name) then
        for _, d in ipairs(DV:Dungeons()) do items[#items + 1] = { dungeonPick = d } end
        if #items == 0 then items[1] = { message = "No dungeon quests found." } end
        return
    end
    local r = DV:Entries(name)
    Section("dungeonOpen", "Quests", r.open, function(e) return { entry = e } end)
    if #r.open == 0 then items[#items + 1] = { message = "Nothing open for you in this dungeon." } end
    if r.greyHidden > 0 then
        items[#items + 1] = { message = ("|cff808080%d grey %s hidden (not worth the XP)|r"):format(r.greyHidden,
            r.greyHidden == 1 and "quest" or "quests") }
    end
    Section("dungeonDone", "Done", r.done, function(e) return { entry = e } end)
    Section("dungeonIgnored", "Ignored", r.ignored, function(e) return { entry = e } end)
end

---------------------------------------------------------------------------------------
-- NPCs tab
---------------------------------------------------------------------------------------

function L:FillNpc(row, n)
    local level = ""
    if n.minLevel then
        level = ("|cff808080[%s]|r "):format(n.minLevel == n.maxLevel and n.minLevel
            or (n.minLevel .. "-" .. (n.maxLevel or n.minLevel)))
    end
    row.line1:SetText(level .. n.name .. (n.sub and ("  |cffb0b0b0<" .. n.sub .. ">|r") or ""))
    local nearest, yards = ns.NpcFinder.Nearest(n.points)
    local where = nearest and ns.Pos.MapName(nearest.zone or nearest.uiMapId) or "position not known"
    if nearest and nearest.inside then where = nearest.inside .. ", " .. where end
    local places = #n.points > 1 and ("  ·  %d places"):format(#n.points) or ""
    row.line2:SetText(where .. (yards and ("  ·  %d yd"):format(yards) or "") .. places)
    local source = nearest and nearest.source and ("Position: " .. nearest.source .. "  ·  ") or ""
    row.line3:SetText("|cff808080" .. source .. "click: mark on the map|r")
    local marked = ns.NpcFinder.stop
    if marked and marked.npcId == n.id then
        row.badge:Show()
        row.badge:SetVertexColor(0.35, 1, 0.35)
    end
end

function L:NpcItems(items)
    local F = ns.NpcFinder
    if F.stop then
        items[#items + 1] = { npcMarked = F.stop }
        items[#items + 1] = { npcRemove = true }
    end
    items[#items + 1] = { npcKeep = true }
    local text = self.searchText
    if not text or text == "" then
        items[#items + 1] = { message = "|cff808080Type a name, a title (flight master, innkeeper,|r" }
        items[#items + 1] = { message = "|cff808080weapon trainer ...) or a zone in the box above.|r" }
        items[#items + 1] = { message = "|cff808080Own coordinates: /fqln pin [zone] x y [name]|r" }
        return
    end
    if not F.ready then
        items[#items + 1] = { message = "|cff808080Building the NPC index...|r" }
        F:Build(function() L:Update() end)
        return
    end
    local r = F:Find(text)
    items[#items + 1] = { header = ("NPCs: \"%s\""):format(text), section = "search", count = r.total }
    for _, n in ipairs(r.list) do items[#items + 1] = { npc = n } end
    if r.total == 0 then
        items[#items + 1] = { message = "|cff808080No friendly NPC matches.|r" }
    elseif r.total > #r.list then
        items[#items + 1] = { message = ("|cff808080%d match, the nearest %d are shown. Type more to narrow it.|r")
            :format(r.total, #r.list) }
    end
end

---------------------------------------------------------------------------------------
-- Whole questline under a row (the +/- button), Route and Dungeon tabs
---------------------------------------------------------------------------------------

local function ChainOf(item)
    if item.stop and item.stop.primary then
        return item.stop.primary.line, "s:" .. item.stop.questId .. ":" .. item.stop.state, item.stop.questId
    end
    if item.entry and item.entry.line then
        return item.entry.line, "e:" .. item.entry.questId, item.entry.questId
    end
end

-- done / turnin / progress (in your log) / todo
function L.ChainState(c)
    local P = ns.Planner
    if P:StepDone(c.line, c.id) then return "done" end
    if P.InLog(c.id) then return P.IsReadyToTurnIn(c.id) and "turnin" or "progress" end
    return "todo"
end

function L.ChainXP(id)
    local xp, estimate = ns.XP:Get(id)
    return "XP " .. (estimate and "~" or "") .. ns.XP.Format(xp)
end

function L:WithChains(items)
    local out = {}
    for _, item in ipairs(items) do
        out[#out + 1] = item
        local line, key, questId = ChainOf(item)
        if line and #line.steps > 1 then
            item.chainKey = key
            if self.expanded[key] then
                for index, id in ipairs(line.steps) do
                    out[#out + 1] = { chainStep = { line = line, index = index, id = id, current = id == questId } }
                end
            end
        end
    end
    return out
end

local CHAIN_TAG = {
    done     = "|cff40c040[Done]|r ",
    turnin   = "|cff40ff40[Ready to turn in]|r ",
    progress = "|cff4dc3ff[On quest]|r ",
    todo     = "",
}

function L:FillChainStep(row, c)
    local P = ns.Planner
    local state = L.ChainState(c)
    local name = P:QuestName(c.id)
    if state == "done" then name = "|cff9d9d9d" .. name .. "|r" end
    if c.current then name = "|cffffd100> |r" .. name end
    local level = P:QuestLevel(c.id)
    row.line1:SetText(("    |cff808080%d/%d|r %s%s%s"):format(c.index, #c.line.steps, LevelTag(level),
        CHAIN_TAG[state], name))
    local start, finish = ns.DungeonView:Ends(c.id)
    row.line2:SetText("      Start: " .. (start or "?") .. "   ->   End: " .. (finish or "?"))
    row.line3:SetText("      " .. L.ChainXP(c.id))
end
