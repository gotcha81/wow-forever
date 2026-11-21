-- QuestJournal: core (namespace, saved settings, error log, events, start-up).
-- Everything lives in the private addon namespace `ns`. The only globals are the
-- SavedVariables tables, the slash command, the Addon Compartment functions and a
-- few uniquely named frames.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME
ns.ready = false

local PREFIX = "|cffffd100QuestJournal|r: "

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
-- QuestJournalDB.errorLog. /qj errors shows it, /qj errors clear empties it.
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
        ns.Print(("|cffff8040caught an error (%d different so far). Type /qj errors to see them.|r"):format(#log))
    end
end

-- Catch-all: every Lua error whose message or stack points into this addon's
-- folder goes into the log too, also errors outside ns.Safe (while the files
-- load, in tooltips, ...). The handler that was there before (the game's error
-- popup, or BugSack/BugGrabber) still gets every error, unchanged.
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

function ns.LogError(where, message, stack)
    Record(where, { message = tostring(message), stack = stack or "" })
end

function ns.ErrorReport()
    local log = ErrorLog()
    if #log == 0 then return "QuestJournal " .. ns.Version() .. ": no errors recorded." end
    local out = { ("QuestJournal %s error log: %d different errors"):format(ns.Version(), #log) }
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
        f = CreateFrame("Frame", "QuestJournalCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(560, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.08, 0.06, 0.04, 0.96)
        f:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
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
        tinsert(UISpecialFrames, "QuestJournalCopyFrame")
        ns.copyFrame = f
    end
    f.title:SetText(title)
    f.box:SetText(text)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
end

---------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------

ns.defaults = {
    faction = "mine",   -- browse filter: "mine", "Horde", "Alliance" or "Both"
    minimap = { shown = true, angle = 225 },
    window  = { point = { "CENTER", "CENTER", 0, 0 } },
    errorLog = {},
}

-- Per character: which sections, chains and earlier/next blocks are open.
ns.charDefaults = {
    sections = { active = true },  -- [sectionKey] = true when open
    chains   = {},                 -- [finalQuestId] = true / false (nil = section default)
    earlier  = {},                 -- [finalQuestId] = true when "earlier quests" is open
    later    = {},                 -- [finalQuestId] = true when "next quests" is open
}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            if k ~= "errorLog" then ApplyDefaults(db[k], v) end
        elseif db[k] == nil then
            db[k] = v
        end
    end
end

---------------------------------------------------------------------------------------
-- Refresh: many events become one redraw.
---------------------------------------------------------------------------------------

local refreshQueued = false
local DoRefresh = ns.Safe("refresh", function()
    refreshQueued = false
    if ns.ready then ns.Window:Update() end
end)

function ns.RequestRefresh(delay)
    if refreshQueued or not ns.ready then return end
    refreshQueued = true
    C_Timer.After(delay or 0.5, DoRefresh)
end

local starting = false
local Start = ns.Safe("start", function()
    if ns.ready or starting then return end
    starting = true
    ns.Chains:Build(ns.Safe("start", function()
        ns.ready = true
        ns.Print(("ready. %d quest chains found%s. Type /qj to open the journal.")
            :format(ns.Chains.count or 0, ns.Data.questie and "" or " (Questie not found: only the game's own data)"))
        ns.Window:Update()
    end))
end)

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

local function TryRegister(event)
    pcall(events.RegisterEvent, events, event)
end

local function OnEvent(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        QuestJournalDB = QuestJournalDB or {}
        ApplyDefaults(QuestJournalDB, ns.defaults)
        ns.db = QuestJournalDB
        QuestJournalCharDB = QuestJournalCharDB or {}
        ApplyDefaults(QuestJournalCharDB, ns.charDefaults)
        ns.charDB = QuestJournalCharDB
        for _, e in ipairs(pendingErrors) do table.insert(ns.db.errorLog, e) end
        wipe(pendingErrors)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        ns.Data:Init()
        ns.Window:Create()
        ns.MapPins:Create()
        ns.MinimapButton:Create()

        if ns.Data.questie then
            -- Questie's public API says when its data is ready; a timer as backup.
            if Questie and Questie.API and type(Questie.API.RegisterOnReady) == "function" then
                pcall(Questie.API.RegisterOnReady, Start)
            end
            C_Timer.After(20, Start)
        else
            C_Timer.After(3, Start)
        end

        for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
                             "PLAYER_LEVEL_UP", "QUEST_DATA_LOAD_RESULT", "PLAYER_ENTERING_WORLD" }) do
            TryRegister(e)
        end

    elseif event == "PLAYER_LEVEL_UP" then
        ns.XP:Clear() -- quest XP depends on your level
        ns.RequestRefresh(0.5)
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        ns.XP:OnQuestDataLoaded(arg1, arg2)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.MapPins:Draw() -- minimap pins are left out inside instances
    elseif event == "QUEST_LOG_UPDATE" then
        ns.RequestRefresh(1.5) -- fires very often
    else
        if event == "QUEST_TURNED_IN" then ns.Chains:ClearStateCache() end
        ns.RequestRefresh()
    end
end

events:SetScript("OnEvent", ns.Safe("events", OnEvent))

---------------------------------------------------------------------------------------
-- Addon Compartment (the game's addon menu by the minimap). Named in the TOC.
---------------------------------------------------------------------------------------

local CompartmentClick = ns.Safe("addon menu click", function()
    if ns.Window then ns.Window:Toggle() end
end)

local CompartmentEnter = ns.Safe("addon menu tooltip", function(_, button)
    local owner = button or (type(_) == "table" and _) or UIParent
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("QuestJournal", 1, 0.82, 0)
    GameTooltip:AddLine("Click: open or close the journal", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

function QuestJournal_OnAddonCompartmentClick(...) CompartmentClick(...) end
function QuestJournal_OnAddonCompartmentEnter(...) CompartmentEnter(...) end
function QuestJournal_OnAddonCompartmentLeave() GameTooltip:Hide() end
