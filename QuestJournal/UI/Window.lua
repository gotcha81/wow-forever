-- The journal window.
--
--   In progress (N)            chains you are on
--   <zone> (N)                 every other chain, by zone (yours first)
--   Trivial (N)                chains where every quest is grey for you
--   Completed (N)              chains you have finished
--
-- Nothing opens by itself: sections, chains and the earlier / next blocks open or
-- close only with their own +/- button (only "In progress" starts open). An open
-- chain shows the step you are on, with "[+] N earlier quests" above it and
-- "[+] N next quests" below it. Every step shows its XP, the chain header shows
-- the XP of the whole chain. A key icon marks only the quest that rewards a key.
-- The map button on a step puts its start and finish on the world map and minimap.
-- Top row: search box (chain name, quest names, zone), zone drop-down, faction.

local ADDON_NAME, ns = ...

local W = { rows = {} }
ns.Window = W

local WIDTH, HEIGHT = 580, 620
local ROW_WIDTH = WIDTH - 52
local KEY_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"

local HEIGHTS = { section = 24, chain = 22, expander = 18, step = 32, note = 20 }
local INDENT = { section = 2, chain = 14, expander = 32, step = 32, note = 14 }

local GOLD = "|cffffd100"
local GREY = "|cff9d9d9d"
local BLUE = "|cff4da6ff"
local GREEN = "|cff40c040"
local TEAL = "|cff33cccc"

local FACTIONS = { "mine", "Horde", "Alliance", "Both" }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ColorFor(level, done)
    if done then return GREY end
    if not level or not GetQuestDifficultyColor then return "|cffffffff" end
    local c = GetQuestDifficultyColor(level)
    if type(c) ~= "table" then return "|cffffffff" end
    local function B(v) return math.floor((v or 1) * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(B(c.r), B(c.g), B(c.b))
end

local function XPText(xp, estimate)
    if not xp or xp <= 0 then return GREY .. "? XP|r" end
    return (estimate and "~" or "") .. ns.XP.Format(xp) .. " XP"
end

local function ItemName(id)
    local name
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, id)
        if ok then name = n end
    end
    return name or ns.Data:Item(id, "name") or ("item #" .. id)
end

local function WhoText(list)
    local D = ns.Data
    local who = list[1]
    if not who then return nil end
    local name = who.name or (who.kind .. " #" .. who.id)
    if who.kind == "item" then return name .. " (item)" end
    local place = D:PlaceText(who)
    return place and (name .. " (" .. place .. ")") or name
end

local function FactionLabel()
    local f = ns.db.faction
    if f == "mine" then return "My faction" end
    return f -- "Horde", "Alliance" or "Both"
end

local function CurrentZoneName()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, uiMapId = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not uiMapId then return nil end
    return ns.Data.MapName(uiMapId)
end

local function SectionOpen(key, default)
    local v = ns.charDB.sections[key]
    if v == nil then return default end
    return v
end

-- Chains are closed until you open them with their + button.
local function ChainOpen(line)
    return ns.charDB.chains[line.id] == true
end

---------------------------------------------------------------------------------------
-- Search and zone filter (for this session; the search clears when the window closes)
---------------------------------------------------------------------------------------

W.search = ""   -- lower case
W.zone = nil    -- nil = all zones, else a section name (line.group)

local function SearchText(line)
    if not line.searchText then
        local parts = { line.name, line.group or "" }
        for _, id in ipairs(line.steps) do parts[#parts + 1] = ns.Chains:QuestName(id) end
        line.searchText = table.concat(parts, "\n"):lower()
    end
    return line.searchText
end

function W:Filtering()
    return self.search ~= "" or self.zone ~= nil
end

function W:Matches(line)
    if self.zone and line.group ~= self.zone then return false end
    if self.search ~= "" and not SearchText(line):find(self.search, 1, true) then return false end
    return true
end

---------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------

function W:Create()
    local f = CreateFrame("Frame", "QuestJournalFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.10, 0.07, 0.04, 0.95)
    f:SetBackdropBorderColor(0.85, 0.68, 0.30, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        ns.db.window.point = { point, relPoint, x, y }
    end)
    local p = ns.db.window.point
    f:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
    f:Hide()
    tinsert(UISpecialFrames, "QuestJournalFrame") -- Esc closes it

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 12, -10)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Quest Journal")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- One slim row: search box, zone drop-down, faction button.
    local okBox, box = pcall(CreateFrame, "EditBox", "QuestJournalSearchBox", f, "SearchBoxTemplate")
    if not okBox then box = CreateFrame("EditBox", "QuestJournalSearchBox", f, "InputBoxTemplate") end
    box:SetSize(250, 20)
    box:SetPoint("TOPLEFT", 20, -46)
    box:SetAutoFocus(false)
    if not okBox then
        local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        hint:SetPoint("LEFT", 2, 0)
        hint:SetText("Search")
        box.hint = hint
    end
    box:HookScript("OnTextChanged", ns.Safe("search", function(b)
        local text = (b:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if b.hint then b.hint:SetShown(text == "") end
        if text ~= W.search then
            W.search = text
            W:Update()
        end
    end))
    box:HookScript("OnEscapePressed", function(b) b:ClearFocus() end)
    box:HookScript("OnEnterPressed", function(b) b:ClearFocus() end)
    self.searchBox = box

    local zone = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    zone:SetSize(170, 22)
    zone:SetPoint("LEFT", box, "RIGHT", 10, 0)
    zone:SetScript("OnClick", ns.Safe("zone menu", function() W:ToggleZoneMenu() end))
    self.zoneButton = zone

    -- Faction filter: click to go round yours / Horde / Alliance / both.
    local faction = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    faction:SetSize(100, 22)
    faction:SetPoint("LEFT", zone, "RIGHT", 6, 0)
    faction:SetScript("OnClick", ns.Safe("faction", function()
        local cur = 1
        for i, v in ipairs(FACTIONS) do if v == ns.db.faction then cur = i end end
        ns.db.faction = FACTIONS[cur % #FACTIONS + 1]
        W:Update()
    end))
    faction:SetScript("OnEnter", ns.Safe("faction tooltip", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Faction filter", 1, 0.82, 0)
        GameTooltip:AddLine("Click to switch: yours, Horde, Alliance, both.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Chains you are on or have finished always show.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end))
    faction:SetScript("OnLeave", GameTooltip_Hide)
    self.factionButton = faction

    self.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.info:SetPoint("RIGHT", close, "LEFT", -6, 0)
    self.info:SetJustifyH("RIGHT")

    local scroll = CreateFrame("ScrollFrame", "QuestJournalScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -74)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    f:SetScript("OnShow", ns.Safe("window show", function() W:Update() end))
    f:SetScript("OnHide", ns.Safe("window hide", function()
        if W.zoneMenu then W.zoneMenu:Hide() end
        W.search = ""
        W.searchBox:SetText("")
        W.searchBox:ClearFocus()
    end))
end

---------------------------------------------------------------------------------------
-- Zone drop-down: a small list under the zone button
---------------------------------------------------------------------------------------

local MENU_ROW = 18

local function ZoneNames()
    local seen, names = {}, {}
    for _, line in ipairs(ns.Chains.lines or {}) do
        local g = line.group
        if g and not seen[g] and ns.Chains.FactionAllows(line.side) then
            seen[g] = true
            names[#names + 1] = g
        end
    end
    table.sort(names)
    return names
end

function W:ToggleZoneMenu()
    local menu = self.zoneMenu
    if menu and menu:IsShown() then menu:Hide(); return end
    if not ns.ready then return end
    if not menu then
        menu = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetSize(210, 320)
        menu:SetPoint("TOPLEFT", self.zoneButton, "BOTTOMLEFT", 0, -2)
        menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                           edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                           insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        menu:SetBackdropColor(0.06, 0.04, 0.02, 0.98)
        menu:SetBackdropBorderColor(0.85, 0.68, 0.30, 1)
        menu:EnableMouse(true)
        local scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -26, 6)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(176, 1)
        scroll:SetScrollChild(content)
        menu.content, menu.buttons = content, {}
        self.zoneMenu = menu
    end

    local entries = { false } -- false = all zones
    for _, name in ipairs(ZoneNames()) do entries[#entries + 1] = name end
    for i, name in ipairs(entries) do
        local b = menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menu.content)
            b:SetSize(176, MENU_ROW)
            b:SetPoint("TOPLEFT", 0, -(i - 1) * MENU_ROW)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:SetScript("OnClick", ns.Safe("zone pick", function(btn)
                W.zone = btn.zone or nil
                menu:Hide()
                W:Update()
            end))
            menu.buttons[i] = b
        end
        b.zone = name
        local selected = (name or nil) == self.zone
        b.text:SetText((selected and GOLD or "") .. (name or "All zones") .. (selected and "|r" or ""))
        b:Show()
    end
    for i = #entries + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu.content:SetHeight(#entries * MENU_ROW)
    menu:Show()
end

function W:Toggle()
    if not self.frame then return end
    self.frame:SetShown(not self.frame:IsShown())
    if self.frame:IsShown() and not ns.ready then
        ns.Print("still reading the quest data, one moment...")
    end
end

---------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------

local function RowTooltip(row) W:ShowTooltip(row) end

-- Only the +/- button opens or closes something.
local function ToggleClick(btn)
    local d = btn:GetParent().data
    if not d then return end
    local cdb = ns.charDB
    if d.type == "section" then
        cdb.sections[d.key] = not d.open
    elseif d.type == "chain" then
        cdb.chains[d.line.id] = not d.open
    elseif d.type == "expander" then
        local t = d.which == "earlier" and cdb.earlier or cdb.later
        t[d.line.id] = not d.open or nil
    else
        return
    end
    W:Update()
end

local function MapClick(btn)
    local row = btn:GetParent()
    local d = row.data
    if d and d.type == "step" then
        ns.MapPins:Toggle(d.line.steps[d.index])
        W:Update()
    end
end

function W:GetRow(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, self.content)
    row:SetWidth(ROW_WIDTH)
    row:EnableMouse(true) -- for the tooltips; the row itself is not a button

    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(16, 16)
    row.toggle.tex = row.toggle:CreateTexture(nil, "ARTWORK")
    row.toggle.tex:SetAllPoints()
    row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    row.toggle:SetScript("OnClick", ns.Safe("toggle", ToggleClick))

    row.key = row:CreateTexture(nil, "ARTWORK")
    row.key:SetSize(14, 14)
    row.key:SetTexture(KEY_ICON)
    row.key:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.sub:SetTextColor(0.62, 0.62, 0.62)

    row.map = CreateFrame("Button", nil, row)
    row.map:SetSize(18, 18)
    row.map:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
    row.map.tex = row.map:CreateTexture(nil, "ARTWORK")
    row.map.tex:SetAllPoints()
    row.map.tex:SetTexture(MAP_ICON)
    row.map.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.map:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.map:SetScript("OnClick", ns.Safe("map button", MapClick))
    row.map:SetScript("OnEnter", ns.Safe("map button tooltip", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show on map", 1, 0.82, 0)
        GameTooltip:AddLine("Marks where this quest starts (S) and where you hand it in (E) on the world map and minimap.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Click again to remove the marks.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end))
    row.map:SetScript("OnLeave", GameTooltip_Hide)

    row:SetScript("OnEnter", ns.Safe("row tooltip", RowTooltip))
    row:SetScript("OnLeave", GameTooltip_Hide)
    self.rows[i] = row
    return row
end

function W:Layout(row, d)
    local indent = INDENT[d.type] or 0
    row:SetHeight(HEIGHTS[d.type] or 20)
    row.toggle:Hide(); row.key:Hide(); row.map:Hide(); row.sub:Hide()
    row.text:ClearAllPoints(); row.right:ClearAllPoints(); row.sub:ClearAllPoints()
    row.text:SetFontObject(d.type == "section" and "GameFontNormalLarge" or
                           d.type == "expander" and "GameFontHighlightSmall" or "GameFontNormal")

    local x = indent
    if d.type == "chain" or d.type == "expander" or (d.type == "section" and not d.locked) then
        row.toggle.tex:SetTexture(d.open and MINUS or PLUS)
        row.toggle:ClearAllPoints()
        row.toggle:SetPoint("LEFT", row, "LEFT", x, 0)
        row.toggle:Show()
        x = x + 18
    end
    if d.key then
        row.key:ClearAllPoints()
        if d.type == "step" then
            row.key:SetPoint("TOPLEFT", row, "TOPLEFT", x, -3)
        else
            row.key:SetPoint("LEFT", row, "LEFT", x, 0)
        end
        row.key:Show()
        x = x + 18
    end

    local rightEdge = -4
    if d.type == "step" and d.mapButton then
        row.map:Show()
        row.map.tex:SetDesaturated(not d.pinned)
        row.map:SetAlpha(d.pinned and 1 or 0.75)
        rightEdge = -26
    end

    if d.type == "step" then
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", x, -3)
        row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", rightEdge, -4)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", indent + 18, -17)
        row.sub:SetPoint("RIGHT", row, "RIGHT", rightEdge, 0)
        row.sub:SetText(d.sub or "")
        row.sub:Show()
    else
        row.text:SetPoint("LEFT", row, "LEFT", x, 0)
        row.right:SetPoint("RIGHT", row, "RIGHT", rightEdge, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    end
    row.text:SetText(d.text or "")
    row.right:SetText(d.right or "")
end

---------------------------------------------------------------------------------------
-- Building the row list
---------------------------------------------------------------------------------------

local function StepRow(line, i, isCurrent)
    local C, D = ns.Chains, ns.Data
    local id = line.steps[i]
    local st = line.state
    local done = st.done[i]
    local level = C:QuestLevel(id)
    local tag = ""
    if done then
        tag = GREEN .. " done|r"
    elseif C.IsReady(id) then
        tag = GREEN .. " [Ready to turn in]|r"
    elseif C.InLog(id) then
        tag = BLUE .. " [On quest]|r"
    end
    if line.dungeonOf[id] then tag = tag .. TEAL .. " [Dungeon: " .. line.dungeonOf[id] .. "]|r" end
    local marker = isCurrent and not done and (GOLD .. "> |r") or ""
    local text = ("%s%s%d/%d|r  %s[%s] %s|r%s"):format(marker, GREY, i, #line.steps,
        ColorFor(level, done), level or "?", C:QuestName(id), tag)
    local xp, est = ns.XP:Get(id)

    local sub
    if D.questie then
        local from, to = WhoText(D:Givers(id)), WhoText(D:TurnIns(id))
        sub = ("From: %s   >   To: %s"):format(from or "?", to or "?")
    else
        sub = "Install Questie to see who gives and takes this quest."
    end
    return { type = "step", line = line, index = i, key = line.keyOf[id], text = text, sub = sub,
             right = XPText(xp, est), mapButton = D.questie, pinned = ns.MapPins.questId == id }
end

local function AddChain(rows, line, sectionKey)
    local C = ns.Chains
    local st = line.state
    local open = ChainOpen(line)
    local total, left, est = C:ChainXP(line)
    local levels = st.minLevel and (st.minLevel == st.maxLevel and tostring(st.minLevel)
        or (st.minLevel .. "-" .. st.maxLevel)) or "?"
    local side = ""
    if line.side ~= "Both" and ns.db.faction == "Both" then
        side = line.side == "Horde" and " |cffff4040[H]|r" or " |cff4080ff[A]|r"
    end
    local where = sectionKey == "zone" and "" or (line.group and (GREY .. "  " .. line.group .. "|r") or "")
    local text = ("%s%s|r%s  %s(%s, %d quests)|r%s"):format(GOLD, line.name, side, GREY, levels, #line.steps, where)
    local right
    if st.started and st.status ~= "completed" then
        right = ("%s left of %s"):format(XPText(left, est), XPText(total, est))
    else
        right = "Chain total " .. XPText(total, est)
    end
    rows[#rows + 1] = { type = "chain", line = line, open = open, text = text, right = right }
    if not open then return end

    local cur = st.current
    local cdb = ns.charDB
    if cur > 1 then
        local eo = cdb.earlier[line.id] and true or false
        rows[#rows + 1] = { type = "expander", line = line, which = "earlier", open = eo,
                            text = eo and "Hide earlier quests" or ("%d earlier %s"):format(cur - 1, cur - 1 == 1 and "quest" or "quests") }
        if eo then
            for i = 1, cur - 1 do rows[#rows + 1] = StepRow(line, i, false) end
        end
    end
    rows[#rows + 1] = StepRow(line, cur, true)
    local after = #line.steps - cur
    if after > 0 then
        local lo = cdb.later[line.id] and true or false
        rows[#rows + 1] = { type = "expander", line = line, which = "later", open = lo,
                            text = lo and "Hide next quests" or ("%d next %s"):format(after, after == 1 and "quest" or "quests") }
        if lo then
            for i = cur + 1, #line.steps do rows[#rows + 1] = StepRow(line, i, false) end
        end
    end
end

-- While searching or a zone is picked, sections without matches are left out and
-- the others show their matches (the chains themselves stay closed).
local function AddSection(rows, key, label, lines, defaultOpen, kind)
    local filtering = W:Filtering()
    if filtering then
        local kept = {}
        for _, line in ipairs(lines) do
            if W:Matches(line) then kept[#kept + 1] = line end
        end
        lines = kept
        if #lines == 0 then return 0 end
    end
    local open = filtering or SectionOpen(key, defaultOpen)
    rows[#rows + 1] = { type = "section", key = key, open = open, locked = filtering,
                        text = ("%s %s(%d)|r"):format(label, GREY, #lines) }
    if not open then return #lines end
    if #lines == 0 then
        rows[#rows + 1] = { type = "note", text = GREY .. "Nothing here yet.|r" }
        return 0
    end
    for _, line in ipairs(lines) do AddChain(rows, line, kind or key) end
    return #lines
end

function W:BuildRows()
    local rows = {}
    if not ns.ready then
        rows[1] = { type = "note", text = GREY .. "Reading the quest data, one moment...|r" }
        return rows, 0
    end
    if not ns.Data.questie then
        rows[#rows + 1] = { type = "note",
            text = "|cffff8040Questie not found:|r only chains the game itself knows are shown." }
    end
    local s = ns.Chains:Sections()
    local function ByLevel(a, b)
        local la, lb = a.state.minLevel or 0, b.state.minLevel or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end
    table.sort(s.active, ByLevel)
    table.sort(s.trivial, ByLevel)
    table.sort(s.completed, ByLevel)

    -- Only "In progress" starts open (showing chain names); everything else opens
    -- when you click its + button, and stays as you left it.
    local shown = AddSection(rows, "active", "In progress", s.active, true)

    local here = CurrentZoneName()
    local names = {}
    for name in pairs(s.zones) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == here then return true end
        if b == here then return false end
        return a < b
    end)
    for _, name in ipairs(names) do
        local list = s.zones[name]
        table.sort(list, ByLevel)
        shown = shown + AddSection(rows, "zone:" .. name,
            name == here and (name .. GREEN .. " (you are here)|r") or name, list, false, "zone")
    end

    shown = shown + AddSection(rows, "trivial", "Trivial", s.trivial, false)
    shown = shown + AddSection(rows, "completed", "Completed", s.completed, false)
    if shown == 0 and W:Filtering() then
        rows[#rows + 1] = { type = "note", text = GREY .. "No chains match.|r" }
    end
    return rows, shown
end

function W:Update()
    if not self.frame then return end
    self.factionButton:SetText(FactionLabel())
    self.zoneButton:SetText(self.zone or "All zones")
    if not self.frame:IsShown() then return end -- redrawn on show
    ns.XP:NewDraw()
    local rows, shown = self:BuildRows()
    self.info:SetText(ns.ready and ("%d chains"):format(shown) or "")
    local y = 0
    for i, d in ipairs(rows) do
        local row = self:GetRow(i)
        row.data = d
        self:Layout(row, d)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:Show()
        y = y + row:GetHeight()
    end
    for i = #rows + 1, #self.rows do
        self.rows[i]:Hide()
        self.rows[i].data = nil
    end
    self.content:SetHeight(math.max(y, 1))
end

---------------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------------

local function AddRewards(line, id)
    local items = ns.Chains:RewardItems(line, id)
    local any = false
    if items and #items > 0 then
        GameTooltip:AddLine("Rewards" .. (#items > 1 and " (some may be a choice):" or ":"), 1, 0.82, 0)
        for _, itemId in ipairs(items) do
            local isKey = line.keyOf[id] and ns.Data:Item(itemId, "class") == 13
            GameTooltip:AddLine("  " .. ItemName(itemId) .. (isKey and "  |cffffd100(key)|r" or ""), 1, 1, 1)
        end
        any = true
    end
    if GetQuestLogRewardMoney then
        local ok, money = pcall(GetQuestLogRewardMoney, id)
        if ok and type(money) == "number" and money > 0 and GetCoinTextureString then
            GameTooltip:AddLine((any and "  " or "Rewards: ") .. GetCoinTextureString(money), 1, 1, 1)
        end
    end
end

function W:ShowTooltip(row)
    local d = row.data
    if not d or (d.type ~= "step" and d.type ~= "chain") then return end
    local C, D = ns.Chains, ns.Data
    local line = d.line
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

    if d.type == "chain" then
        GameTooltip:SetText(line.name, 1, 0.82, 0)
        GameTooltip:AddLine(("%d quests, %s"):format(#line.steps,
            line.side == "Both" and "both factions" or line.side .. " only"), 0.8, 0.8, 0.8)
        local first = line.steps[1]
        GameTooltip:AddLine("Starts with: " .. C:QuestName(first), 1, 1, 1, true)
        if D.questie then
            local from = WhoText(D:Givers(first))
            if from then GameTooltip:AddLine("  from " .. from, 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:AddLine("Ends with: " .. C:QuestName(line.id), 1, 1, 1, true)
        if line.hasKey then GameTooltip:AddLine("This chain rewards a key.", 1, 0.82, 0) end
        local total, left, est = C:ChainXP(line)
        GameTooltip:AddLine(("XP: %s for the whole chain, %s left"):format(XPText(total, est), XPText(left, est)), 0.6, 0.85, 1)
        if est then GameTooltip:AddLine("~ = estimate until the game sends the exact value", 0.5, 0.5, 0.5, true) end
        GameTooltip:AddLine("Final reward:", 1, 0.82, 0)
        AddRewards(line, line.id)
        GameTooltip:Show()
        return
    end

    local id = line.steps[d.index]
    local level, scales = C:QuestLevel(id)
    GameTooltip:SetText(C:QuestName(id), 1, 1, 1)
    GameTooltip:AddLine(("Step %d of %d in %s"):format(d.index, #line.steps, line.name), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(("Level %s%s, needs level %d"):format(level or "?", scales and " (scales)" or "", C:RequiredLevel(id)), 0.8, 0.8, 0.8)
    if line.dungeonOf[id] then GameTooltip:AddLine("Done inside " .. line.dungeonOf[id], 0.2, 0.8, 0.8) end

    if D.questie then
        local givers, turnIns = D:Givers(id), D:TurnIns(id)
        if givers[1] then GameTooltip:AddLine("Start: " .. WhoText(givers), 1, 1, 1, true) end
        if turnIns[1] then GameTooltip:AddLine("Finish: " .. WhoText(turnIns), 1, 1, 1, true) end
    end

    -- Objectives: live progress if it is in your log, else Questie's text.
    local shown = false
    if C.InLog(id) and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and type(objs) == "table" and #objs > 0 then
            GameTooltip:AddLine("Objectives:", 1, 0.82, 0)
            for _, o in ipairs(objs) do
                if type(o) == "table" and o.text then
                    local c = o.finished and 0.25 or 1
                    GameTooltip:AddLine("  " .. o.text, c, 1, c, true)
                end
            end
            shown = true
        end
    end
    if not shown and D.questie then
        local texts = D:Quest(id, "objectivesText")
        if type(texts) == "table" and #texts > 0 then
            GameTooltip:AddLine("Objectives:", 1, 0.82, 0)
            for _, t in ipairs(texts) do
                if type(t) == "string" then GameTooltip:AddLine("  " .. t, 1, 1, 1, true) end
            end
        end
    end

    local xp, est = ns.XP:Get(id)
    GameTooltip:AddLine("XP: " .. XPText(xp, est), 0.6, 0.85, 1)
    AddRewards(line, id)
    local alts = line.alternatives[id]
    if alts then GameTooltip:AddLine("You can do another quest instead of this one; either counts.", 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end
