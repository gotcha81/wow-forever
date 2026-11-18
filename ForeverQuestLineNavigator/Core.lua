-- Forever QuestLine Navigator: core (namespace, saved settings, events, start-up).
-- Everything lives in the private addon namespace `ns`; the only globals are the
-- SavedVariables table, the slash command and a few uniquely named frames.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME
ns.ready = false

local PREFIX = "|cff4da6ffQuestLine Navigator|r: "

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

---------------------------------------------------------------------------------------
-- Error log: our own code runs through ns.Safe, so an error is logged instead of
-- popping up every frame.
--  * Rate limited: the same error only counts up ("Error B occurred 89 times"),
--    the chat notice shows at most once per 10 seconds, at most 50 different
--    errors are kept.
--  * Saved in the SavedVariables (ForeverQuestLineNavigatorDB.errorLog), so it
--    survives /reload and logout and can be read from the saved file directly.
--  * /fqln errors opens it in a copy window, /fqln errors clear empties it.
---------------------------------------------------------------------------------------

local MAX_ERRORS = 50
local NOTICE_EVERY = 10 -- seconds
local pendingErrors = {} -- errors before the saved settings are loaded
local lastErrorNotice = -100

local function ErrorLog()
    return ns.db and ns.db.errorLog or pendingErrors
end

local function Handler(err)
    local stack = debugstack and debugstack(2, 12, 0) or ""
    return { message = tostring(err), stack = stack }
end

local function Version()
    return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
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
                      first = now, last = now, version = Version() }
    local t = GetTime and GetTime() or 0
    if t - lastErrorNotice > NOTICE_EVERY then
        lastErrorNotice = t
        ns.Print(("|cffff8040caught an error (%d different so far). Type /fqln errors to see or copy them.|r")
            :format(#log))
    end
end

-- Wraps fn so errors are caught and recorded. `where` names the place for the log.
function ns.Safe(where, fn)
    return function(...)
        local args, n = { ... }, select("#", ...)
        local ok, info = xpcall(function() return fn(unpack(args, 1, n)) end, Handler)
        if not ok then Record(where, type(info) == "table" and info or { message = tostring(info), stack = "" }) end
    end
end

-- "A", "B", ... "Z", "AA", "AB", ...
local function Letter(i)
    local s = ""
    repeat
        local r = (i - 1) % 26
        s = string.char(65 + r) .. s
        i = math.floor((i - 1) / 26)
    until i == 0
    return s
end

function ns.ErrorReport()
    local log = ErrorLog()
    if #log == 0 then return "QuestLine Navigator " .. Version() .. ": no errors recorded." end
    local out = { ("QuestLine Navigator %s error log: %d different errors"):format(Version(), #log), "" }
    for i, e in ipairs(log) do
        out[#out + 1] = ("Error %s occurred %d %s (in %s, version %s, first %s, last %s)"):format(
            Letter(i), e.count, e.count == 1 and "time" or "times", e.where or "?", e.version or "?",
            e.first or "?", e.last or "?")
    end
    for i, e in ipairs(log) do
        out[#out + 1] = ""
        out[#out + 1] = ("--- Error %s ---"):format(Letter(i))
        out[#out + 1] = e.message
        if e.stack and e.stack ~= "" then out[#out + 1] = e.stack end
    end
    return table.concat(out, "\n")
end

function ns.ClearErrors()
    wipe(ErrorLog())
end

---------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------

ns.defaults = {
    dungeonFocus = true,   -- only dungeon quest chains (plus class quests if enabled)
    classQuests  = true,   -- include class quests for your class
    travelTime   = false,  -- count boat / zeppelin "just missed it" waits
    arrow        = true,   -- show the blue arrow (always hidden inside instances)
    minimap      = { shown = true, angle = 200 },
    pins         = true,   -- numbered pins on the world map / OpenMap and minimap
    riding       = "auto", -- "auto", "none", "60" or "100"
    levelAhead   = 2,      -- list chains whose first step unlocks within this many levels
    boatWait     = 300,    -- seconds: "just missed it" wait for a boat or zeppelin
    maxStops     = 25,     -- numbered stops on the route
    list   = { shown = true, locked = false, minimized = false, textSize = 12, point = { "RIGHT", "RIGHT", -80, 60 } },
    collapsed = { notWorth = true, trivial = true }, -- list sections folded shut
    arrowFrame = { locked = false, textSize = 12, point = { "TOP", "TOP", 0, -140 } },
    errorLog = {}, -- see the error log above
}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            ApplyDefaults(db[k], v)
        elseif db[k] == nil then
            db[k] = v
        end
    end
end

---------------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------------

-- Coalesce many events into one refresh.
local refreshQueued = false
local DoRefresh

function ns.RequestRefresh(delay)
    if refreshQueued or not ns.ready then return end
    refreshQueued = true
    C_Timer.After(delay or 0.6, function()
        refreshQueued = false
        DoRefresh()
    end)
end

function ns.Refresh()
    if not ns.ready then return end
    ns.Planner:Update()
    ns.Arrow:SetTarget(ns.Planner.route[1])
    ns.List:Update()
    ns.Pins:Update()
end
DoRefresh = ns.Safe("refresh", ns.Refresh)

local starting = false
local function Start()
    if ns.ready or starting then return end
    starting = true
    ns.Planner:BuildCatalog(ns.Safe("start", function()
        ns.ready = true
        ns.Refresh()
        local dj = ns.DungeonJournalSource.available and "on" or "off"
        ns.Print(("ready. %d dungeon and class questlines found (DungeonJournal data: %s). Type /fqln for options.")
            :format(ns.Planner.catalogCount or 0, dj))
    end))
end
Start = ns.Safe("start", Start)

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

-- Events that may not exist on every client are registered carefully.
local function TryRegister(frame, event)
    pcall(frame.RegisterEvent, frame, event)
end

local function OnEvent(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        ForeverQuestLineNavigatorDB = ForeverQuestLineNavigatorDB or {}
        ApplyDefaults(ForeverQuestLineNavigatorDB, ns.defaults)
        ns.db = ForeverQuestLineNavigatorDB
        -- errors caught before this point move into the saved log
        for _, e in ipairs(pendingErrors) do table.insert(ns.db.errorLog, e) end
        wipe(pendingErrors)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        local ok, msg = ns.QuestieSource:Init()
        if not ok then
            ns.Print("|cffff5555cannot start:|r " .. tostring(msg))
            return
        end
        ns.DungeonJournalSource:Init()
        ns.List:Create()
        ns.Arrow:Create()
        ns.Arrow:ClearOldGameWaypoint()
        ns.MinimapButton:Create()

        -- Questie's public API tells us when its data is ready; a timer as backup.
        if Questie and Questie.API and type(Questie.API.RegisterOnReady) == "function" then
            pcall(Questie.API.RegisterOnReady, Start)
        end
        C_Timer.After(20, Start)

        for _, e in ipairs({
            "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
            "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
            "QUEST_DATA_LOAD_RESULT",
        }) do
            TryRegister(self, e)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Arrow:UpdateVisibility()
        ns.RequestRefresh(1)
    elseif event == "PLAYER_LEVEL_UP" then
        ns.XP:Clear() -- quest XP depends on your level
        ns.RequestRefresh(0.5)
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        ns.XP:OnQuestDataLoaded(arg1, arg2)
    elseif event == "QUEST_LOG_UPDATE" then
        ns.RequestRefresh(1.5) -- fires very often; wait a little longer
    else
        ns.RequestRefresh()
    end
end

events:SetScript("OnEvent", ns.Safe("events", OnEvent))
