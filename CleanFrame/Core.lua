-- CleanFrame: core (namespace, saved settings, error log, events).
-- Everything lives in the private addon namespace `ns`. The only globals are the
-- SavedVariables table, the slash commands, the Addon Compartment functions and a
-- few uniquely named frames.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

local PREFIX = "|cffffd100CleanFrame|r: "

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

function ns.Version()
    return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
end

---------------------------------------------------------------------------------------
-- Error log. Our own code runs through ns.Safe, so an error is logged instead of
-- popping up every frame. The same error only counts up, the chat notice shows at
-- most once per 10 seconds, at most 50 different errors are kept. It is saved in
-- CleanFrameDB.errorLog. /cfr errors shows it, /cfr errors clear empties it.
---------------------------------------------------------------------------------------

local MAX_ERRORS = 50
local NOTICE_EVERY = 10
local pendingErrors = {}
local lastNotice = -100

local function ErrorLog()
    return ns.db and ns.db.errorLog or pendingErrors
end

local function Handler(err)
    return { message = tostring(err), stack = debugstack and debugstack(2, 12, 0) or "" }
end

local function Record(where, info)
    local log = ErrorLog()
    local now = date and date("%Y-%m-%d %H:%M:%S") or ""
    for _, entry in ipairs(log) do
        if entry.message == info.message then
            entry.count = entry.count + 1
            entry.last = now
            return
        end
    end
    if #log >= MAX_ERRORS then table.remove(log, 1) end
    log[#log + 1] = { message = info.message, stack = info.stack, count = 1, where = where,
                      first = now, last = now, version = ns.Version() }
    local t = GetTime and GetTime() or 0
    if t - lastNotice > NOTICE_EVERY then
        lastNotice = t
        ns.Print(("|cffff8040caught an error (%d different so far). Type /cfr errors to see them.|r"):format(#log))
    end
end

-- Catch-all: every Lua error whose message or stack points into this addon's
-- folder goes into the log too. The handler that was there before (the game's
-- error popup, or BugSack/BugGrabber) still gets every error, unchanged.
do
    local previous = geterrorhandler and geterrorhandler()
    local busy = false
    local PATTERN = "AddOns[\\/]" .. ADDON_NAME .. "[\\/]"
    if seterrorhandler and type(previous) == "function" then
        seterrorhandler(function(msg, ...)
            if not busy then
                busy = true
                pcall(function()
                    local text = tostring(msg)
                    local stack = debugstack and debugstack(2, 20, 0) or ""
                    if text:find(PATTERN) or stack:find(PATTERN) then
                        Record("lua error", { message = text, stack = stack })
                    end
                end)
                busy = false
            end
            return previous(msg, ...)
        end)
    end
end

function ns.Safe(where, fn)
    return function(...)
        local args, n = { ... }, select("#", ...)
        local ok, info = xpcall(function() return fn(unpack(args, 1, n)) end, Handler)
        if not ok then Record(where, type(info) == "table" and info or { message = tostring(info), stack = "" }) end
    end
end

function ns.ErrorReport()
    local log = ErrorLog()
    if #log == 0 then return "CleanFrame " .. ns.Version() .. ": no errors recorded." end
    local out = { ("CleanFrame %s error log: %d different errors"):format(ns.Version(), #log) }
    for i, e in ipairs(log) do
        out[#out + 1] = ""
        out[#out + 1] = ("--- Error %d: %d %s (in %s, version %s, first %s, last %s) ---"):format(
            i, e.count, e.count == 1 and "time" or "times", e.where or "?", e.version or "?", e.first or "?", e.last or "?")
        out[#out + 1] = e.message
        if e.stack and e.stack ~= "" then out[#out + 1] = e.stack end
    end
    return table.concat(out, "\n")
end

function ns.ClearErrors()
    wipe(ErrorLog())
end

-- A window with selectable text, for copying (Ctrl+A, Ctrl+C).
function ns.ShowCopy(title, text)
    local f = ns.copyFrame
    if not f then
        f = CreateFrame("Frame", "CleanFrameCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(560, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 12, -10)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -30, 12)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal)
        box:SetWidth(510)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(box)
        f.box = box
        tinsert(UISpecialFrames, "CleanFrameCopyFrame")
        ns.copyFrame = f
    end
    f.title:SetText(title)
    f.box:SetText(text)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
end

---------------------------------------------------------------------------------------
-- Settings (account wide)
---------------------------------------------------------------------------------------

local function FrameDefaults(point, x, y, scale, debuffs)
    return {
        shown = true,
        scale = scale,
        -- Text on each side of a bar: "none", "current" (1234), "value" (1234 / 2000),
        -- "percent" or "both".
        healthLeft   = "percent",
        healthRight  = "value",
        powerLeft    = "percent",
        powerRight   = "value",
        healthColor  = "green",   -- "green" or "class" (class colour for players)
        barStyle     = "solid",   -- solid / gradient / glossy / striped / classic
        width        = 200,
        nameHeight   = 12,
        healthHeight = 22,
        powerHeight  = 10,
        borderSize   = 2,
        point = { point, "TOPLEFT", x, y },
        -- Debuffs, in rows outside the frame, under it (on by default for target and target of target).
        debuffs = { shown = debuffs, max = 16, size = 20, perRow = 8 },
        border = "auto",                     -- "auto" (level colour; class colour on your own frame) or "custom"
        color = { r = 0.6, g = 0.6, b = 0.6 }, -- the custom border colour
    }
end

ns.defaults = {
    locked       = true,
    hideBlizzard = true,      -- hide the game's own frames (needs /reload)
    minimap      = { shown = true, angle = 200 },
    frames = {     -- every frame has all its own settings (one settings tab each)
        player       = FrameDefaults("TOPLEFT", 20, -20, 1, false),
        target       = FrameDefaults("TOPLEFT", 260, -20, 1, true),
        targettarget = FrameDefaults("TOPLEFT", 480, -40, 0.75, true),
        focus        = FrameDefaults("TOPLEFT", 260, -110, 0.9, false),
        pet          = FrameDefaults("TOPLEFT", 20, -90, 0.8, false), -- also a mind-controlled unit
    },
    errorLog = {},
}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then
                db[k] = {}
                if k ~= "errorLog" then ApplyDefaults(db[k], v) end
            elseif k ~= "errorLog" then
                ApplyDefaults(db[k], v)
            end
        elseif db[k] == nil then
            db[k] = v
        end
    end
end

-- Copy of the default values for one key (used by "reset positions").
function ns.DefaultsFor(unit)
    local d = ns.defaults.frames[unit]
    return { d.point[1], d.point[2], d.point[3], d.point[4] }
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CleanFrameDB = CleanFrameDB or {}
        -- Settings that used to be shared by all frames (sizes up to 0.2.4, texts and
        -- health colour up to 0.5.0): give each frame those values once.
        local old = CleanFrameDB
        local SHARED = { "width", "nameHeight", "healthHeight", "powerHeight", "borderSize",
                         "healthLeft", "healthRight", "powerLeft", "powerRight", "healthColor" }
        if type(old.frames) == "table" then
            if not old.perFrameDebuffs then
                -- 0.5.0 saved debuffs as on for every frame, but showed them only on
                -- target and target of target: keep it that way.
                for unit, s in pairs(old.frames) do
                    if type(s) == "table" and type(s.debuffs) == "table"
                        and unit ~= "target" and unit ~= "targettarget" then
                        s.debuffs.shown = false
                    end
                end
            end
            for _, key in ipairs(SHARED) do
                if old[key] ~= nil then
                    for _, s in pairs(old.frames) do
                        if type(s) == "table" and s[key] == nil then s[key] = old[key] end
                    end
                end
            end
        end
        for _, key in ipairs(SHARED) do old[key] = nil end
        old.perFrameDebuffs = true
        ApplyDefaults(CleanFrameDB, ns.defaults)
        ns.db = CleanFrameDB
        ns.db.healthText, ns.db.powerText = nil, nil -- 0.1.0 settings, replaced by left/right
        for _, e in ipairs(pendingErrors) do table.insert(ns.db.errorLog, e) end
        wipe(pendingErrors)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.db.locked = true -- always start locked
        -- Separate steps: if one fails (logged), the others still run.
        ns.Safe("create settings", function() ns.Options:Create() end)()
        ns.Safe("create minimap button", function() ns.MinimapButton:Create() end)()
        ns.Safe("create frames", function() ns.Frames:Create() end)()
    end
end

events:SetScript("OnEvent", ns.Safe("events", OnEvent))

---------------------------------------------------------------------------------------
-- Addon Compartment (the game's addon menu by the minimap). Named in the TOC.
---------------------------------------------------------------------------------------

local CompartmentClick = ns.Safe("addon menu click", function() ns.Options:Open() end)

local CompartmentEnter = ns.Safe("addon menu tooltip", function(_, button)
    local owner = button or (type(_) == "table" and _) or UIParent
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("CleanFrame", 1, 0.82, 0)
    GameTooltip:AddLine("Click: open the settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

function CleanFrame_OnAddonCompartmentClick(...) CompartmentClick(...) end
function CleanFrame_OnAddonCompartmentEnter(...) CompartmentEnter(...) end
function CleanFrame_OnAddonCompartmentLeave() GameTooltip:Hide() end
