-- DisenchantInfo: the settings panel (game menu > Options > AddOns > DisenchantInfo).
-- Built from plain widgets (no drop-down menus), so it works whatever templates
-- the client has.

local _, ns = ...
local O = {}
ns.Options = O

local widgets = {} -- each has :Load() to show the current value

local function Label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
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
    cb:SetScript("OnClick", ns.Safe("option", function(self) set(self:GetChecked() and true or false) end))
    function cb:Load() self:SetChecked(get()) end
    widgets[#widgets + 1] = cb
    return cb
end

-- A button that steps through a list of choices.
local function Cycle(parent, text, x, y, width, choices, get, set)
    Label(parent, text, x, y - 4)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x + 210, y)
    local function Index()
        for i, c in ipairs(choices) do if c[1] == get() then return i end end
        return 1
    end
    function b:Load() self:SetText(choices[Index()][2]) end
    b:SetScript("OnClick", ns.Safe("option", function(self)
        set(choices[Index() % #choices + 1][1])
        self:Load()
    end))
    widgets[#widgets + 1] = b
    return b
end

-- A number box (Enter saves, clamped to min..max).
local function Number(parent, text, x, y, min, max, get, set)
    Label(parent, text, x, y - 4)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(60, 20)
    box:SetPoint("TOPLEFT", x + 216, y)
    box:SetAutoFocus(false)
    box:SetJustifyH("CENTER")
    box:SetNumeric(true)
    function box:Load() self:SetText(tostring(get())) end
    box:SetScript("OnEnterPressed", ns.Safe("option", function(self)
        local n = tonumber(self:GetText())
        if n then set(math.max(min, math.min(max, math.floor(n)))) end
        self:ClearFocus()
        self:Load()
    end))
    box:SetScript("OnEditFocusLost", function(self) self:Load() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    widgets[#widgets + 1] = box
    return box
end

local function Button(parent, text, x, y, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", ns.Safe("option", onClick))
    return b
end

function O:Create()
    local panel = CreateFrame("Frame")
    panel.name = "DisenchantInfo"
    self.panel = panel
    local db = ns.db

    Label(panel, "DisenchantInfo", 16, -16, "GameFontNormalLarge")
    Label(panel, "v" .. ns.Version(), 190, -20, "GameFontDisableSmall")
    Label(panel, "What items disenchant into, the chance (with the Arcane Salvager), vendor and AH price.",
        16, -42, "GameFontHighlightSmall")

    local y = -72
    Label(panel, "Tooltip", 16, y, "GameFontNormal")
    y = y - 24
    Cycle(panel, "Show the disenchant lines to", 20, y, 200,
        { { "enchanters", "Enchanters only" }, { "all", "Every character" } },
        function() return db.showFor end, function(v) db.showFor = v end)
    y = y - 30
    Check(panel, "Show the amount (x1-2) after each material", 20, y,
        function() return db.showQty end, function(v) db.showQty = v end)
    y = y - 26
    Check(panel, "Show the \"Average worth\" line", 20, y,
        function() return db.showTotal end, function(v) db.showTotal = v end)
    y = y - 26
    local tsm = (type(TSM_API) == "table") and "|cff40ff40TSM found|r: AH prices are TSM's DBMarket."
        or "|cff999999TSM not found: no AH price (lines end after the vendor price).|r"
    Label(panel, tsm, 24, y - 4, "GameFontHighlightSmall")

    y = y - 36
    Label(panel, "Learning", 16, y, "GameFontNormal")
    y = y - 24
    Check(panel, "Chat line after each logged disenchant", 20, y,
        function() return db.chatLog end, function(v) db.chatLog = v end)
    y = y - 30
    Number(panel, "Logged disenchants needed (per kind)", 20, y, 1, 1000,
        function() return db.minSamples end, function(v) db.minSamples = v end)
    y = y - 22
    Label(panel, "Until then the tooltip uses the standard table, and \"(?)\" for the Salvager.",
        24, y - 4, "GameFontHighlightSmall")

    y = y - 32
    Label(panel, "Arcane Salvager", 16, y, "GameFontNormal")
    y = y - 24
    self.salvagerButton = Cycle(panel, "Count disenchants as with Salvager", 20, y, 200,
        { { "auto", "Auto (detect)" }, { "on", "On (by hand)" }, { "off", "Off (by hand)" } },
        function() return db.salvager end, function(v) db.salvager = v end)
    y = y - 22
    Label(panel, "Auto looks for a Salvager buff. If none is found, set it On by hand while you use one\n"
        .. "(/dei salvager or right-click DisenchantInfo in the addon menu), and Off again after.",
        24, y - 4, "GameFontHighlightSmall")

    y = y - 48
    Button(panel, "Show what's logged", 20, y, 170, function() ns.ShowCopy("DisenchantInfo stats", ns.Logger:StatsReport()) end)
    Button(panel, "Forget all logged disenchants", 200, y, 220, function() StaticPopup_Show("DISENCHANTINFO_RESET") end)

    StaticPopupDialogs["DISENCHANTINFO_RESET"] = {
        text = "DisenchantInfo: forget every logged disenchant? This can't be undone.",
        button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = ns.Safe("reset", function()
            ns.Logger:Reset()
            ns.Print("all logged disenchants forgotten.")
        end),
        timeout = 0, whileDead = true, hideOnEscape = true,
    }

    panel:SetScript("OnShow", ns.Safe("options", function() O:Refresh() end))

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "DisenchantInfo")
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function O:Refresh()
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
        ns.Print("the settings panel could not be created. Type /dei errors to see why.")
    elseif self.category and Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
