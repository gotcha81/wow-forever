-- DisenchantInfo: core (namespace, saved settings, error log, events).
-- Everything lives in the private addon namespace `ns`. The only globals are the
-- SavedVariables table, the slash commands, the Addon Compartment functions and a
-- few uniquely named frames.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

local PREFIX = "|cffffd100DisenchantInfo|r: "

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
-- DisenchantInfoDB.errorLog. /dei errors shows it, /dei errors clear empties it.
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
        ns.Print(("|cffff8040caught an error (%d different so far). Type /dei errors to see them.|r"):format(#log))
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
    if #log == 0 then return "DisenchantInfo " .. ns.Version() .. ": no errors recorded." end
    local out = { ("DisenchantInfo %s error log: %d different errors"):format(ns.Version(), #log) }
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
        f = CreateFrame("Frame", "DisenchantInfoCopyFrame", UIParent, "BackdropTemplate")
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
        tinsert(UISpecialFrames, "DisenchantInfoCopyFrame")
        ns.copyFrame = f
    end
    f.title:SetText(title)
    f.box:SetText(text)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
end

---------------------------------------------------------------------------------------
-- Settings and learned data (account wide: every enchanter on the account learns
-- into the same numbers).
---------------------------------------------------------------------------------------

ns.defaults = {
    showFor     = "enchanters", -- "enchanters" (characters that know Disenchant) or "all"
    showTotal   = true,         -- the "Average worth" line
    showQty     = true,         -- "x1-2" after the material name
    chatLog     = true,         -- a chat line after each logged disenchant
    minSamples  = 20,           -- logged disenchants needed before your own % replace the table %
    salvager    = "auto",       -- "auto" (detect), "on" (always count as with Salvager), "off"
    stats       = {},           -- learned results, see Logger.lua
    log         = {},           -- the last disenchants in full (for working out the Salvager)
    errorLog    = {},
}

local NO_DEEP = { stats = true, log = true, errorLog = true }

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            if not NO_DEEP[k] then ApplyDefaults(db[k], v) end
        elseif db[k] == nil then
            db[k] = v
        end
    end
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", ns.Safe("events", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        DisenchantInfoDB = DisenchantInfoDB or {}
        ApplyDefaults(DisenchantInfoDB, ns.defaults)
        ns.db = DisenchantInfoDB
        for _, e in ipairs(pendingErrors) do table.insert(ns.db.errorLog, e) end
        wipe(pendingErrors)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Separate steps: if one fails (logged), the others still run.
        ns.Safe("create settings", function() ns.Options:Create() end)()
        ns.Safe("tooltip hook", function() ns.Tooltip:Hook() end)()
        ns.Safe("disenchant logger", function() ns.Logger:Start() end)()
    end
end))

---------------------------------------------------------------------------------------
-- Addon Compartment (the game's addon menu by the minimap). Named in the TOC.
-- Left-click: settings. Right-click: switch the Salvager between auto / on / off.
---------------------------------------------------------------------------------------

local CompartmentClick = ns.Safe("addon menu click", function(_, button)
    if button == "RightButton" then
        ns.Logger:CycleSalvager()
    else
        ns.Options:Open()
    end
end)

local CompartmentEnter = ns.Safe("addon menu tooltip", function(_, button)
    local owner = button or (type(_) == "table" and _) or UIParent
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("DisenchantInfo", 1, 0.82, 0)
    GameTooltip:AddLine("Arcane Salvager: " .. ns.Logger:SalvagerText(), 1, 1, 1)
    GameTooltip:AddLine("Left-click: open the settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: Salvager auto / on / off", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

function DisenchantInfo_OnAddonCompartmentClick(...) CompartmentClick(...) end
function DisenchantInfo_OnAddonCompartmentEnter(...) CompartmentEnter(...) end
function DisenchantInfo_OnAddonCompartmentLeave() GameTooltip:Hide() end
