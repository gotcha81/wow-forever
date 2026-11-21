-- ClearTargetFrame: the settings panel (game menu > Options > AddOns > ClearTargetFrame).
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

local function Slider(parent, text, x, y, min, max, step, get, set)
    local label = Label(parent, text, x, y - 4)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(180, 16)
    s:SetPoint("TOPLEFT", x + 130, y - 2)
    s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
                    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8,
                    insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local loading = true -- nothing is saved until the slider shows the real value
    local function Show(v)
        value:SetText(step < 1 and ("%.2f"):format(v) or tostring(v))
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
    panel.name = "ClearTargetFrame"
    self.panel = panel

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local c = CreateFrame("Frame", nil, scroll)
    c:SetSize(600, 900)
    scroll:SetScrollChild(c)

    local db = ns.db
    local y = -12
    Label(c, "ClearTargetFrame", 12, y, "GameFontNormalLarge")
    Label(c, "v" .. ns.Version(), 170, y - 4, "GameFontDisableSmall")
    y = y - 30

    Check(c, "Unlock the frames (drag them to move)", 12, y,
        function() return not db.locked end,
        function(v) return ns.Frames:SetLocked(not v) end)
    y = y - 28
    Check(c, "Hide the game's own player, target and focus frames (needs /reload)", 12, y,
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

    Label(c, "Bars", 12, y, "GameFontNormal")
    y = y - 24
    for _, t in ipairs({
        { "Health text, left", "healthLeft" }, { "Health text, right", "healthRight" },
        { "Power text, left", "powerLeft" }, { "Power text, right", "powerRight" },
    }) do
        local key = t[2]
        Cycle(c, t[1], 16, y, 220, TEXT_CHOICES, function() return db[key] end, function(v) db[key] = v end)
        y = y - 28
    end
    Cycle(c, "Health colour", 16, y, 220, HEALTH_COLORS,
        function() return db.healthColor end, function(v) db.healthColor = v end)
    y = y - 40

    Label(c, "Size", 12, y, "GameFontNormal")
    y = y - 24
    for _, s in ipairs({
        { "Width", "width", 100, 400, 5 },
        { "Name bar height", "nameHeight", 8, 24, 1 },
        { "Health bar height", "healthHeight", 8, 60, 1 },
        { "Power bar height", "powerHeight", 3, 40, 1 },
        { "Border size", "borderSize", 1, 6, 1 },
    }) do
        local key = s[2]
        Slider(c, s[1], 16, y, s[3], s[4], s[5], function() return db[key] end, function(v) db[key] = v end)
        y = y - 28
    end
    y = y - 12

    for _, unit in ipairs(ns.Frames.UNITS) do
        local fs = db.frames[unit]
        Label(c, ns.Frames.LABELS[unit], 12, y, "GameFontNormal")
        y = y - 24
        Check(c, "Show", 16, y, function() return fs.shown end,
            function(v) fs.shown = v; Changed() end)
        y = y - 28
        Slider(c, "Scale", 16, y, 0.5, 2, 0.05, function() return fs.scale end, function(v) fs.scale = v end)
        y = y - 28
        Cycle(c, "Border", 16, y, 160, BORDER_MODES,
            function() return fs.border end, function(v) fs.border = v end)
        Swatch(c, 16 + 130 + 170, y, function() return fs.color end)
        if unit == "player" then
            Label(c, "(level colour = your class colour)", 16 + 130 + 200, y - 4, "GameFontDisableSmall")
        end
        y = y - 40
    end
    c:SetHeight(-y + 20)

    panel:SetScript("OnShow", ns.Safe("options", function()
        for _, w in ipairs(widgets) do w:Load() end
    end))

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "ClearTargetFrame")
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function O:Open()
    if InCombatLockdown() then
        ns.Print("the settings can't be opened in combat.")
        return
    end
    if not self.panel then
        ns.Print("the settings panel could not be created. Type /ctf errors to see why.")
    elseif self.category and Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
