-- Settings window, opened with the cogwheel on the arrow or the quest window.
-- Kept small for now: text sizes and the on/off switches.

local _, ns = ...

local S = {}
ns.Settings = S

local WIDTH = 300

local function Header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 14, y)
    fs:SetText(text)
    return fs
end

local function Checkbox(parent, label, y, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", 18, y)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb.Refresh = function(self) self:SetChecked(get()) end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Arrow:UpdateVisibility()
        ns.RequestRefresh(0)
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
    end
    return cb
end

-- Horizontal slider built from the game's standard slider textures.
local function Slider(parent, label, y, min, max, get, set)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 22, y)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(WIDTH - 60, 16)
    s:SetPoint("TOPLEFT", 22, y - 16)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local function Label(value) text:SetText(("%s: |cffffffff%d|r"):format(label, value)) end
    s.Refresh = function(self)
        self.updating = true
        self:SetValue(get())
        self.updating = false
        Label(get())
    end
    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Label(value)
        if not self.updating then set(value) end
    end)
    return s
end

function S:Create()
    local db = ns.db
    local f = CreateFrame("Frame", "ForeverQuestLineNavigatorSettings", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.04, 0.07, 0.13, 0.96)
    f:SetBackdropBorderColor(0.3, 0.55, 0.9, 1)
    tinsert(UISpecialFrames, f:GetName()) -- Esc closes it

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff4da6ffSettings|r")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    self.controls = {}
    local function Add(control) self.controls[#self.controls + 1] = control; return control end

    Header(f, "Arrow", -40)
    Add(Checkbox(f, "Show the arrow", -58, function() return db.arrow end, function(v) db.arrow = v end,
        "Always hidden inside dungeons, raids, battlegrounds and arenas."))
    Add(Slider(f, "Text size", -84, 8, 24, function() return db.arrowFrame.textSize end,
        function(v) ns.Arrow:SetTextSize(v) end))

    Header(f, "Quest window", -130)
    Add(Slider(f, "Text size", -150, 9, 18, function() return db.list.textSize end,
        function(v) ns.List:SetTextSize(v) end))

    Header(f, "Route", -196)
    Add(Checkbox(f, "Dungeon focus", -214, function() return db.dungeonFocus end, function(v) db.dungeonFocus = v end,
        "On: dungeon questlines and the zone you are in.\nOff: also open-world quests in the zones your route passes through."))
    Add(Checkbox(f, "Class quests", -238, function() return db.classQuests end, function(v) db.classQuests = v end,
        "Include questlines for your class."))
    Add(Checkbox(f, "Travel time: boats and zeppelins", -262, function() return db.travelTime end,
        function(v) db.travelTime = v end,
        "Count a full 'just missed it' wait when the route changes continent. Off: a rough fixed estimate."))
    Add(Checkbox(f, "Numbered map pins", -286, function() return db.pins end, function(v) db.pins = v end,
        "On the world map (OpenMap too) and the minimap."))
    Add(Checkbox(f, "Minimap button", -310, function() return db.minimap.shown end,
        function(v) ns.MinimapButton:SetShown(v) end))

    Header(f, "Dungeons", -344)
    Add(Checkbox(f, "Check quests when entering a dungeon", -362, function() return db.dungeonCheck end,
        function(v) db.dungeonCheck = v end,
        "When you enter a dungeon, list in chat the quests for it you could have picked up but don't have."))

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 12)
    hint:SetText("Right-click a quest to ignore it. Ignored ones: bottom of the Route tab.")

    f:SetScript("OnShow", function() S:Refresh() end)
    f:Hide()
end

function S:Refresh()
    for _, control in ipairs(self.controls or {}) do control:Refresh() end
end

function S:Toggle()
    if not self.frame then self:Create() end
    self.frame:SetShown(not self.frame:IsShown())
end
