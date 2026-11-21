-- ClearTargetFrame: the unit frames (player, target, target of target, focus).
--
-- Each frame, top to bottom, inside a coloured border:
--   name bar   : small, the name on the left, "Elite" / "Boss" on the right
--   health bar : text on the left and on the right, each none / value / percent / both
--                (default: percent left, value right; also "remaining" = current only)
--   power bar  : mana, rage, energy, ... in its own colour, same text choices
--
-- The frames are secure unit buttons, so left-click targets and right-click opens
-- the unit's menu, also in combat. Sizes and positions can only change out of
-- combat (a game rule for secure frames); a change made in combat is applied
-- right after it.

local _, ns = ...
local F = {}
ns.Frames = F

-- "pet" is also the unit you control with Mind Control or another possess:
-- the game has no separate frame or unit for that (its own pet frame shows it).
F.UNITS = { "player", "target", "targettarget", "focus", "pet" }
F.LABELS = { player = "Player", target = "Target", targettarget = "Target of target", focus = "Focus",
             pet = "Pet" }

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frames = {}
F.frames = frames
local layoutPending = false
-- See "Secret values" below; needed this early by the colour helpers.
local IsSecretValue = issecretvalue or function() return false end

---------------------------------------------------------------------------------------
-- Colours and text
---------------------------------------------------------------------------------------

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
        or RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

-- The game's own "con" colour for a level: grey, green, yellow, orange or red.
local function LevelColor(unit)
    local level = UnitLevel(unit)
    if IsSecretValue(level) then return 1, 0.82, 0 end
    if not level or level <= 0 then return 1, 0.1, 0.1 end -- "??" level: much higher than you
    local c
    if GetCreatureDifficultyColor then
        c = GetCreatureDifficultyColor(level)
    elseif GetQuestDifficultyColor then
        c = GetQuestDifficultyColor(level)
    end
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function BorderColor(unit, settings)
    if settings.border == "custom" then
        local c = settings.color
        return c.r, c.g, c.b
    end
    if unit == "player" then return ClassColor("player") end
    return LevelColor(unit)
end

local function Short(v)
    if AbbreviateLargeNumbers then return AbbreviateLargeNumbers(v) end
    return tostring(v)
end

local function BarText(mode, cur, max)
    if mode == "none" or not max or max <= 0 then return "" end
    local pct = math.floor(cur / max * 100 + 0.5)
    if mode == "current" then
        return Short(cur)
    elseif mode == "value" then
        return Short(cur) .. " / " .. Short(max)
    elseif mode == "percent" then
        return pct .. "%"
    end
    return ("%s / %s  (%d%%)"):format(Short(cur), Short(max), pct)
end
F.BarText = BarText

---------------------------------------------------------------------------------------
-- Secret values. The Forever client hides health and power from addon code as
-- "secret" numbers: an addon may not do maths or comparisons with them, only hand
-- them to the game (status bars, SetFormattedText), which shows the real number.
-- So for a secret number the text is built by the game, and the percent comes
-- from the game's own UnitHealthPercent / UnitPowerPercent.
---------------------------------------------------------------------------------------

local IsSecret = issecretvalue or function() return false end
F.IsSecret = IsSecret

local function SafeMax(max)
    if IsSecret(max) then return max end
    return (max and max > 0) and max or 1
end

-- The game's own percent (0-100), or nil when the client can't give one.
local function GamePercent(unit, kind)
    local fn = kind == "health" and UnitHealthPercent or UnitPowerPercent
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if not fn or not curve then return nil end
    local ok, pct = pcall(fn, unit, false, curve)
    if ok then return pct end
end

-- A number for display: shortened (12.3K) when the game allows it for this value.
local function Display(v)
    if AbbreviateLargeNumbers then
        local ok, s = pcall(AbbreviateLargeNumbers, v)
        if ok then return s end
    end
    return v
end

-- Shown where a number can't be read (yet).
local UNKNOWN = ""  -- the user prefers an empty space over "-"

local function SetBarText(fs, mode, cur, max, unit, kind)
    if not IsSecret(cur) and not IsSecret(max) then
        fs:SetText(BarText(mode, cur, max))
        return
    end
    if mode == "none" then fs:SetText(""); return end
    local ok = pcall(function()
        local pct = (mode == "percent" or mode == "both") and GamePercent(unit, kind)
        if mode == "current" then
            fs:SetFormattedText("%s", Display(cur))
        elseif mode == "value" then
            fs:SetFormattedText("%s / %s", Display(cur), Display(max))
        elseif mode == "percent" then
            if pct then fs:SetFormattedText("%.0f%%", pct) else fs:SetText(UNKNOWN) end
        elseif pct then
            fs:SetFormattedText("%s / %s  (%.0f%%)", Display(cur), Display(max), pct)
        else
            fs:SetFormattedText("%s / %s", Display(cur), Display(max))
        end
    end)
    if not ok then fs:SetText(UNKNOWN) end
end

-- The nameplate unit ("nameplate3", ...) showing the same unit, if one is near.
local function NameplateUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return nil end
    for _, plate in ipairs(plates) do
        local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if token then
            local same, isIt = pcall(UnitIsUnit, token, unit)
            if same and not IsSecret(isIt) and isIt then return token end
        end
    end
end

-- Current and maximum health or power. When the game hides them for the unit
-- itself, they are read from its nameplate when one is near (as nameplate
-- addons do). Returns cur, max and the unit token they came from.
local function Values(unit, kind)
    local cur, max
    if kind == "health" then
        cur, max = UnitHealth(unit), UnitHealthMax(unit)
    else
        cur, max = UnitPower(unit), UnitPowerMax(unit)
    end
    if (IsSecret(cur) or IsSecret(max)) and unit ~= "player" then
        local plate = NameplateUnit(unit)
        if plate then
            local c, m
            if kind == "health" then
                c, m = UnitHealth(plate), UnitHealthMax(plate)
            else
                c, m = UnitPower(plate), UnitPowerMax(plate)
            end
            if not IsSecret(c) and not IsSecret(m) then return c, m, plate end
        end
    end
    return cur, max, unit
end

-- A yes/no from the game, false when it is hidden from addons too.
local function Flag(fn, unit)
    if not fn then return false end
    local ok, v = pcall(fn, unit)
    if not ok or IsSecret(v) then return false end
    return v and true or false
end

-- "Elite" or "Boss" (or nothing).
local function Classification(unit)
    local c = UnitClassification and UnitClassification(unit)
    local level = UnitLevel(unit)
    if IsSecretValue(c) then return "" end
    if IsSecretValue(level) then level = 0 end
    if c == "worldboss" or (level == -1 and (c == "elite" or c == "rareelite")) then
        return "|cffff3030Boss|r"
    elseif c == "elite" or c == "rareelite" then
        return "|cffffd100Elite|r"
    end
    return ""
end

local function PowerColor(unit)
    local ptype, token = UnitPowerType(unit)
    local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[ptype])
    if c then return c.r, c.g, c.b end
    return 0.2, 0.4, 1
end

---------------------------------------------------------------------------------------
-- Drawing one frame
---------------------------------------------------------------------------------------

local function ShowPlaceholder(f)
    -- Unlocked and nothing to show: a sample so the frame can be placed.
    local s = ns.db.frames[f.unit]
    f.name:SetText(F.LABELS[f.unit])
    f.class:SetText(f.unit == "player" and "" or "|cffffd100Elite|r")
    f.health:SetMinMaxValues(0, 100); f.health:SetValue(75)
    f.health:SetStatusBarColor(0, 0.8, 0)
    f.healthLeft:SetText(BarText(ns.db.healthLeft, 7500, 10000))
    f.healthRight:SetText(BarText(ns.db.healthRight, 7500, 10000))
    f.power:SetMinMaxValues(0, 100); f.power:SetValue(50)
    f.power:SetStatusBarColor(0, 0.44, 0.87)
    f.powerLeft:SetText(BarText(ns.db.powerLeft, 500, 1000))
    f.powerRight:SetText(BarText(ns.db.powerRight, 500, 1000))
    local r, g, b = 1, 0.82, 0
    if s.border == "custom" then r, g, b = s.color.r, s.color.g, s.color.b
    elseif f.unit == "player" then r, g, b = ClassColor("player") end
    f.border:SetBackdropBorderColor(r, g, b, 1)
end

function F:Draw(f)
    local unit = f.unit
    if not UnitExists(unit) then
        if not ns.db.locked then ShowPlaceholder(f) end
        return
    end
    local db = ns.db

    f.name:SetText(UnitName(unit) or "")
    local tag = Classification(unit)
    if unit == "pet" and (Flag(UnitIsPossessed, "pet") or Flag(UnitIsCharmed, "pet")) then
        tag = (tag ~= "" and (tag .. "  ") or "") .. "|cffc080ffMind controlled|r"
    end
    f.class:SetText(tag)

    -- health
    local hp, hpMax, hpUnit = Values(unit, "health")
    f.health:SetMinMaxValues(0, SafeMax(hpMax))
    f.health:SetValue(hp)
    if db.healthColor == "class" and Flag(UnitIsPlayer, unit) then
        f.health:SetStatusBarColor(ClassColor(unit))
    else
        f.health:SetStatusBarColor(0, 0.8, 0)
    end
    local status
    if UnitIsConnected and not Flag(UnitIsConnected, unit) and Flag(UnitIsPlayer, unit) then
        status = "Offline"
    elseif Flag(UnitIsGhost, unit) then
        status = "Ghost"
    elseif Flag(UnitIsDead, unit) then
        status = "Dead"
    end
    if status then
        f.healthLeft:SetText(status)
        f.healthRight:SetText("")
    else
        SetBarText(f.healthLeft, db.healthLeft, hp, hpMax, hpUnit, "health")
        SetBarText(f.healthRight, db.healthRight, hp, hpMax, hpUnit, "health")
    end

    -- power (mana, rage, energy, ...)
    local pw, pwMax, pwUnit = Values(unit, "power")
    f.power:SetMinMaxValues(0, SafeMax(pwMax))
    f.power:SetValue(pw)
    f.power:SetStatusBarColor(PowerColor(unit))
    SetBarText(f.powerLeft, db.powerLeft, pw, pwMax, pwUnit, "power")
    SetBarText(f.powerRight, db.powerRight, pw, pwMax, pwUnit, "power")

    f.border:SetBackdropBorderColor(BorderColor(unit, db.frames[unit]))
end

function F:DrawAll()
    for _, f in pairs(frames) do self:Draw(f) end
end

---------------------------------------------------------------------------------------
-- Sizes and positions (out of combat only)
---------------------------------------------------------------------------------------

local function ApplyLayout(f)
    local db = ns.db.frames[f.unit] -- every size is per frame
    local s = db
    local b = db.borderSize
    f:SetScale(s.scale)
    f:SetSize(db.width + 2 * b, db.nameHeight + db.healthHeight + db.powerHeight + 2 * b + 2)
    f:ClearAllPoints()
    f:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])

    f.border:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = b,
                           insets = { left = b, right = b, top = b, bottom = b } })
    f.border:SetBackdropColor(0, 0, 0, 0.65)

    f.nameBar:ClearAllPoints()
    f.nameBar:SetPoint("TOPLEFT", f, "TOPLEFT", b, -b)
    f.nameBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -b, -b)
    f.nameBar:SetHeight(db.nameHeight)
    local fontSize = math.max(7, db.nameHeight - 2)
    f.name:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    f.class:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")

    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", f.nameBar, "BOTTOMLEFT", 0, -1)
    f.health:SetPoint("TOPRIGHT", f.nameBar, "BOTTOMRIGHT", 0, -1)
    f.health:SetHeight(db.healthHeight)
    local hpFont = math.max(8, math.min(14, db.healthHeight - 6))
    f.healthLeft:SetFont(STANDARD_TEXT_FONT, hpFont, "OUTLINE")
    f.healthRight:SetFont(STANDARD_TEXT_FONT, hpFont, "OUTLINE")

    f.power:ClearAllPoints()
    f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
    f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -1)
    f.power:SetHeight(db.powerHeight)
    local pwFont = math.max(7, math.min(12, db.powerHeight - 1))
    f.powerLeft:SetFont(STANDARD_TEXT_FONT, pwFont, "OUTLINE")
    f.powerRight:SetFont(STANDARD_TEXT_FONT, pwFont, "OUTLINE")
    f.powerLeft:SetShown(db.powerHeight >= 8)  -- too thin for text below that
    f.powerRight:SetShown(db.powerHeight >= 8)
end

-- Shown / hidden. Locked: the game shows the frame only while its unit exists.
-- Unlocked: every enabled frame is shown, so it can be dragged.
local function ApplyVisibility(f)
    local s = ns.db.frames[f.unit]
    UnregisterUnitWatch(f)
    if not s.shown then
        f:Hide()
    elseif ns.db.locked then
        RegisterUnitWatch(f)
    else
        f:Show()
    end
    f.dragHint:SetShown(not ns.db.locked)
end

-- Call after any setting changed. Colours and text change at once; sizes,
-- positions and visibility wait until combat ends.
function F:Refresh()
    if InCombatLockdown() then
        if not layoutPending then
            layoutPending = true
            ns.Print("in combat: the new size and position are applied when combat ends.")
        end
    else
        layoutPending = false
        for _, f in pairs(frames) do
            ApplyLayout(f)
            ApplyVisibility(f)
        end
    end
    self:DrawAll()
end

function F:SetLocked(locked)
    if InCombatLockdown() then
        ns.Print("can't unlock the frames in combat.")
        return false
    end
    ns.db.locked = locked and true or false
    self:Refresh()
    return true
end

function F:ResetPositions()
    if InCombatLockdown() then
        ns.Print("can't move the frames in combat.")
        return
    end
    for _, unit in ipairs(F.UNITS) do ns.db.frames[unit].point = ns.DefaultsFor(unit) end
    self:Refresh()
end

---------------------------------------------------------------------------------------
-- Creating the frames
---------------------------------------------------------------------------------------

local function OnDragStart(f)
    if not ns.db.locked and not InCombatLockdown() then f:StartMoving() end
end

local function OnDragStop(f)
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    ns.db.frames[f.unit].point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function OnEnter(f)
    if not UnitExists(f.unit) then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, f)
    GameTooltip:SetUnit(f.unit)
    GameTooltip:Show()
end

local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    return bar
end

-- A text on the left and one on the right of a bar.
local function SideTexts(bar, size)
    local left = bar:CreateFontString(nil, "OVERLAY")
    left:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    left:SetPoint("LEFT", 4, 0)
    left:SetJustifyH("LEFT")
    local right = bar:CreateFontString(nil, "OVERLAY")
    right:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    right:SetPoint("RIGHT", -4, 0)
    right:SetJustifyH("RIGHT")
    return left, right
end

local function CreateUnitFrame(unit)
    local f = CreateFrame("Button", "ClearTargetFrame_" .. unit, UIParent, "SecureUnitButtonTemplate")
    f.unit = unit
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", ns.Safe("drag", OnDragStart))
    f:SetScript("OnDragStop", ns.Safe("drag", OnDragStop))
    f:SetScript("OnEnter", ns.Safe("tooltip", OnEnter))
    f:SetScript("OnLeave", GameTooltip_Hide)

    -- The border and background sit on a plain child frame (not the secure one).
    f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.border:SetAllPoints()
    f.border:SetFrameLevel(f:GetFrameLevel())

    f.nameBar = CreateFrame("Frame", nil, f)
    f.nameBar.bg = f.nameBar:CreateTexture(nil, "BACKGROUND")
    f.nameBar.bg:SetAllPoints()
    f.nameBar.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    f.name = f.nameBar:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    f.name:SetPoint("LEFT", 3, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.class = f.nameBar:CreateFontString(nil, "OVERLAY")
    f.class:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    f.class:SetPoint("RIGHT", -3, 0)
    f.class:SetJustifyH("RIGHT")
    f.name:SetPoint("RIGHT", f.class, "LEFT", -4, 0)

    f.health = NewBar(f)
    f.healthLeft, f.healthRight = SideTexts(f.health, 11)

    f.power = NewBar(f)
    f.powerLeft, f.powerRight = SideTexts(f.power, 9)

    f.dragHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.dragHint:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f.dragHint:SetText(F.LABELS[unit] .. " (drag)")
    f.dragHint:Hide()

    frames[unit] = f
    return f
end

-- Hide the game's own frames. They are moved under a hidden parent, so the game
-- can still update them without them showing. Done once at login, out of combat.
local function HideBlizzard()
    local hidden = CreateFrame("Frame")
    hidden:Hide()
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "TargetFrameToT", "PetFrame" }) do
        local frame = _G[name]
        if frame then
            pcall(frame.SetParent, frame, hidden)
            pcall(frame.Hide, frame)
        end
    end
end

---------------------------------------------------------------------------------------
-- Events: instant updates for the units the game reports, and a light timer for
-- the target of target (no events of its own) and the focus.
---------------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
                      "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL",
                      "UNIT_CLASSIFICATION_CHANGED", "UNIT_CONNECTION", "UNIT_FACTION", "UNIT_TARGET", "UNIT_PET" }

local function OnEvent(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if layoutPending then F:Refresh() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        F:Draw(frames.target); F:Draw(frames.targettarget)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        F:Draw(frames.focus)
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        F:Draw(frames.target); F:Draw(frames.focus) -- numbers may now be readable (or not)
    elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then
        F:DrawAll() -- the level colours depend on your level
    elseif event == "UNIT_PET" then
        if unit == "player" then F:Draw(frames.pet) end -- pet summoned, dismissed or mind control
    elseif event == "UNIT_TARGET" then
        if unit == "target" then F:Draw(frames.targettarget) end
    elseif unit and frames[unit] then
        F:Draw(frames[unit])
    end
end

function F:Create()
    for _, unit in ipairs(F.UNITS) do CreateUnitFrame(unit) end
    if ns.db.hideBlizzard then HideBlizzard() end

    local ev = CreateFrame("Frame")
    for _, e in ipairs(UNIT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_LEVEL_UP",
                         "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
                         "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", ns.Safe("unit events", OnEvent))

    local elapsed = 0
    local Tick = ns.Safe("timer", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        -- focus too: when it is the same unit as the target, the game reports
        -- changes only for "target"
        if frames.targettarget:IsShown() then F:Draw(frames.targettarget) end
        if frames.focus:IsShown() then F:Draw(frames.focus) end
        if frames.pet:IsShown() then F:Draw(frames.pet) end -- catches mind control starting or ending
    end)
    ev:SetScript("OnUpdate", Tick)

    self:Refresh()
end
