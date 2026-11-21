-- CleanFrame: the settings panel (game menu > Options > AddOns > CleanFrame).
-- Built from plain widgets (no drop-down menus), so it works whatever templates
-- the client has.

local _, ns = ...
local O = {}
ns.Options = O

local TEXT_CHOICES = {
    { "none", "None" }, { "current", "Remaining (1234)" }, { "value", "Value (1234 / 2000)" },
    { "percent", "Percent (62%)" }, { "both", "Both (1234 / 2000  (62%))" },
}
local HEALTH_COLORS = { { "green", "Green" }, { "class", "Class colour for players" } }
local BAR_STYLES = {
    { "solid", "Solid" }, { "gradient", "Gradient" }, { "glossy", "Glossy" },
    { "striped", "Striped" }, { "classic", "Classic (the game's look)" },
}
local BORDER_MODES = {
    { "auto", "Level colour" }, -- on the player frame: class colour
    { "custom", "Custom colour" },
}

local widgets = {} -- each has :Load() to show the current value

local function Changed()
    ns.Frames:Refresh()
end

---------------------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------------------

local function Label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Check(parent, text, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetText(text)
    cb:SetScript("OnClick", ns.Safe("option", function(self)
        if set(self:GetChecked() and true or false) == false then self:SetChecked(get()) end
    end))
    function cb:Load() self:SetChecked(get()) end
    widgets[#widgets + 1] = cb
    return cb
end

-- A button that steps through a list of choices.
local function Cycle(parent, text, x, y, width, choices, get, set)
    Label(parent, text, x, y - 4)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x + 130, y)
    local function Index()
        for i, c in ipairs(choices) do if c[1] == get() then return i end end
        return 1
    end
    function b:Load() self:SetText(choices[Index()][2]) end
    b:SetScript("OnClick", ns.Safe("option", function(self)
        set(choices[Index() % #choices + 1][1])
        self:Load()
        Changed()
    end))
    widgets[#widgets + 1] = b
    return b
end

-- withBox: a box next to the slider where the exact number can be typed (Enter).
local function Slider(parent, text, x, y, min, max, step, get, set, withBox)
    local label = Label(parent, text, x, y - 4)
    -- Drawn with plain colours, so it shows whatever artwork the client has.
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(180, 16)
    s:SetPoint("TOPLEFT", x + 130, y - 2)
    s:EnableMouse(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.25, 1)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 0.82, 0, 1)
    s:SetThumbTexture(thumb)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local loading = true -- nothing is saved until the slider shows the real value
    local box
    if withBox then
        value:Hide()
        box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        box:SetSize(60, 20)
        box:SetPoint("LEFT", s, "RIGHT", 14, 0)
        box:SetAutoFocus(false)
        box:SetJustifyH("CENTER")
        local function Commit(self)
            local n = tonumber(self:GetText())
            self:ClearFocus()
            if not n then s:Load(); return end
            n = math.max(min, math.min(max, math.floor(n / step + 0.5) * step))
            s:SetValue(n) -- the slider saves it and redraws
            self:SetText(tostring(n))
        end
        box:SetScript("OnEnterPressed", ns.Safe("option", Commit))
        box:SetScript("OnEditFocusLost", function(self) s:Load() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    local function Show(v)
        local text = step < 1 and ("%.2f"):format(v) or tostring(v)
        value:SetText(text)
        if box and not box:HasFocus() then box:SetText(text) end
    end
    s:SetScript("OnValueChanged", ns.Safe("option", function(self, v)
        v = math.floor(v / step + 0.5) * step
        Show(v)
        if loading or v == get() then return end
        set(v)
        Changed()
    end))
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(min, math.min(max, self:GetValue() + delta * step)))
    end)
    function s:Load()
        loading = true
        self:SetValue(get())
        Show(get())
        loading = false
    end
    s.label = label
    widgets[#widgets + 1] = s
    return s
end

local function PickColor(c, onChange)
    local before = { r = c.r, g = c.g, b = c.b }
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        c.r, c.g, c.b = r, g, b
        onChange()
    end
    local function Cancel()
        c.r, c.g, c.b = before.r, before.g, before.b
        onChange()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = c.r, g = c.g, b = c.b, hasOpacity = false,
                                                  swatchFunc = Apply, cancelFunc = Cancel })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = Apply
        ColorPickerFrame.cancelFunc = Cancel
        ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function Swatch(parent, x, y, getColor)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(22, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    function b:Load()
        local c = getColor()
        self:SetBackdropColor(c.r, c.g, c.b, 1)
    end
    b:SetScript("OnClick", ns.Safe("colour", function(self)
        PickColor(getColor(), function() self:Load(); Changed() end)
    end))
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Custom border colour")
        GameTooltip:AddLine("Used when the border is set to Custom colour.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    widgets[#widgets + 1] = b
    return b
end

---------------------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------------------

function O:Create()
    local panel = CreateFrame("Frame")
    panel.name = "CleanFrame"
    self.panel = panel

    local db = ns.db
    Label(panel, "CleanFrame", 12, -12, "GameFontNormalLarge")
    Label(panel, "v" .. ns.Version(), 170, -16, "GameFontDisableSmall")

    -- Tabs: General, then one per frame. Each tab is a page in the scroll area.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -70)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local holder = CreateFrame("Frame", nil, scroll)
    holder:SetSize(600, 600)
    scroll:SetScrollChild(holder)

    local pages, tabs = {}, {}
    local function NewPage()
        local p = CreateFrame("Frame", nil, holder)
        p:SetPoint("TOPLEFT")
        p:SetSize(600, 600)
        p:Hide()
        pages[#pages + 1] = p
        return p
    end
    local function Select(n)
        for i, p in ipairs(pages) do
            p:SetShown(i == n)
            if i == n then holder:SetHeight(p:GetHeight()) end
        end
        for i, t in ipairs(tabs) do
            if i == n then t:LockHighlight(); t:Disable() else t:UnlockHighlight(); t:Enable() end
        end
        scroll:SetVerticalScroll(0)
        O.selected = n
    end
    local TAB_NAMES = { "General" }
    for _, unit in ipairs(ns.Frames.UNITS) do
        TAB_NAMES[#TAB_NAMES + 1] = unit == "targettarget" and "Target of target" or ns.Frames.LABELS[unit]
    end
    local tx = 12
    for i, name in ipairs(TAB_NAMES) do
        local t = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        t:SetText(name)
        t:SetSize(math.max(70, t:GetFontString():GetStringWidth() + 24), 24)
        t:SetPoint("TOPLEFT", tx, -40)
        tx = tx + t:GetWidth() + 4
        t:SetScript("OnClick", function() Select(i) end)
        tabs[i] = t
    end

    -- General
    local c = NewPage()
    local y = -8
    Check(c, "Unlock the frames (drag them to move)", 12, y,
        function() return not db.locked end,
        function(v) return ns.Frames:SetLocked(not v) end)
    y = y - 28
    Check(c, "Test mode: show every frame with sample data (ends when you close the settings or combat starts)", 12, y,
        function() return ns.Frames.testMode end,
        function(v) return ns.Frames:SetTestMode(v) end)
    y = y - 28
    Check(c, "Hide the game's own player, target, focus and pet frames (needs /reload)", 12, y,
        function() return db.hideBlizzard end,
        function(v) db.hideBlizzard = v; ns.Print("type /reload to apply this.") end)
    y = y - 28
    Check(c, "Show the minimap button", 12, y,
        function() return db.minimap.shown end,
        function(v) ns.MinimapButton:SetShown(v) end)
    y = y - 28
    local reset = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPLEFT", 16, y)
    reset:SetText("Reset positions")
    reset:SetScript("OnClick", ns.Safe("reset", function() ns.Frames:ResetPositions() end))
    y = y - 40

    Label(c, "Import / export", 12, y, "GameFontNormal")
    y = y - 22
    Label(c, "All settings as one line of text, to keep or share.", 16, y, "GameFontDisableSmall")
    y = y - 20
    local export = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    export:SetSize(140, 22)
    export:SetPoint("TOPLEFT", 16, y)
    export:SetText("Export settings")
    export:SetScript("OnClick", ns.Safe("export", function() ns.Profiles:ShowExport() end))
    local import = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    import:SetSize(140, 22)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetText("Import settings")
    import:SetScript("OnClick", ns.Safe("import", function() ns.Profiles:ShowImport() end))
    y = y - 40
    c:SetHeight(-y + 20)

    -- One tab per frame, every frame with the same settings.
    local SIZES = {
        { "Width", "width", 100, 400, 5 },
        { "Name bar height", "nameHeight", 8, 24, 1 },
        { "Health bar height", "healthHeight", 8, 60, 1 },
        { "Power bar height", "powerHeight", 3, 40, 1 },
        { "Border size", "borderSize", 1, 6, 1 },
        { "Scale", "scale", 0.5, 2, 0.05 },
    }
    for _, unit in ipairs(ns.Frames.UNITS) do
        local fs = db.frames[unit]
        c = NewPage()
        y = -8
        Check(c, "Show this frame", 12, y, function() return fs.shown end,
            function(v) fs.shown = v; Changed() end)
        y = y - 36

        Label(c, "Bars", 12, y, "GameFontNormal")
        y = y - 24
        for _, t in ipairs({
            { "Health text, left", "healthLeft" }, { "Health text, right", "healthRight" },
            { "Power text, left", "powerLeft" }, { "Power text, right", "powerRight" },
        }) do
            local key = t[2]
            Cycle(c, t[1], 16, y, 220, TEXT_CHOICES, function() return fs[key] end, function(v) fs[key] = v end)
            y = y - 28
        end
        Cycle(c, "Health colour", 16, y, 220, HEALTH_COLORS,
            function() return fs.healthColor end, function(v) fs.healthColor = v end)
        y = y - 28
        Cycle(c, "Bar style", 16, y, 220, BAR_STYLES,
            function() return fs.barStyle end, function(v) fs.barStyle = v end)
        y = y - 36

        -- What is about to change: heals on the way, and the cost of the spell being cast.
        Label(c, "Incoming heals and spell cost", 12, y, "GameFontNormal")
        y = y - 24
        Check(c, "Show incoming heals on the health bar", 16, y, function() return fs.healPrediction end,
            function(v) fs.healPrediction = v; Changed() end)
        y = y - 28
        Slider(c, "Heal transparency %", 16, y, 0, 100, 5,
            function() return fs.healTransparency end, function(v) fs.healTransparency = v end)
        y = y - 28
        Check(c, "Show the cost of the spell you're casting on the power bar", 16, y,
            function() return fs.powerCost end, function(v) fs.powerCost = v; Changed() end)
        y = y - 28
        Slider(c, "Cost transparency %", 16, y, 0, 100, 5,
            function() return fs.costTransparency end, function(v) fs.costTransparency = v end)
        y = y - 36

        Label(c, "Size", 12, y, "GameFontNormal")
        y = y - 24
        for _, s in ipairs(SIZES) do
            local key = s[2]
            Slider(c, s[1], 16, y, s[3], s[4], s[5], function() return fs[key] end, function(v) fs[key] = v end)
            y = y - 28
        end
        y = y - 8

        -- Position: offset of the frame's centre from the screen centre. Slider or
        -- type the number (both work); dragging the frame updates them too.
        Label(c, "Position (offset from the screen centre)", 12, y, "GameFontNormal")
        y = y - 24
        for i, axis in ipairs({ { "X offset", 3, 2000 }, { "Y offset", 4, 1500 } }) do
            local index, range = axis[2], axis[3]
            Slider(c, axis[1], 16, y, -range, range, 1,
                function() return fs.point[index] end,
                function(v)
                    if fs.point[1] ~= "CENTER" then return end -- converted on the next layout
                    fs.point[index] = v
                end, true)
            y = y - 28
        end
        y = y - 8

        Label(c, "Border", 12, y, "GameFontNormal")
        y = y - 24
        Cycle(c, "Border colour", 16, y, 160, BORDER_MODES,
            function() return fs.border end, function(v) fs.border = v end)
        Swatch(c, 16 + 130 + 170, y, function() return fs.color end)
        if unit == "player" then
            Label(c, "(level colour = your class colour)", 16 + 130 + 200, y - 4, "GameFontDisableSmall")
        end
        y = y - 36

        Label(c, "Debuffs", 12, y, "GameFontNormal")
        y = y - 24
        local d = fs.debuffs
        Check(c, "Show debuffs (under the frame)", 16, y, function() return d.shown end,
            function(v) d.shown = v; Changed() end)
        y = y - 28
        for _, s in ipairs({
            { "Debuffs shown", "max", 1, 40, 1 },
            { "Debuff size", "size", 12, 40, 1 },
            { "Debuffs per row", "perRow", 2, 20, 1 },
        }) do
            local key = s[2]
            Slider(c, s[1], 16, y, s[3], s[4], s[5], function() return d[key] end, function(v) d[key] = v end)
            y = y - 28
        end
        c:SetHeight(-y + 20)
    end

    panel:SetScript("OnShow", ns.Safe("options", function()
        for _, w in ipairs(widgets) do w:Load() end
        Select(O.selected or 1)
    end))
    -- Leaving the settings ends test mode, so the sample frames don't stay up.
    panel:SetScript("OnHide", ns.Safe("options", function()
        if ns.Frames.testMode and not InCombatLockdown() then ns.Frames:SetTestMode(false) end
    end))

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "CleanFrame")
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- Shows the current values again (after an import or a drag), if the panel is open.
function O:Reload()
    if self.panel and self.panel:IsVisible() then
        for _, w in ipairs(widgets) do w:Load() end
    end
end

function O:Open()
    if InCombatLockdown() then
        ns.Print("the settings can't be opened in combat.")
        return
    end
    if not self.panel then
        ns.Print("the settings panel could not be created. Type /cfr errors to see why.")
    elseif self.category and Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
