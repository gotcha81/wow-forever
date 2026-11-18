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
-- Error catcher: our own code runs through ns.Safe, so an error is logged once
-- (with a count) instead of popping up every frame. /fqln errors shows them.
---------------------------------------------------------------------------------------

ns.errors = {}          -- { { message = , stack = , count = , where = }, ... }
local errorIndex = {}   -- message -> entry
local lastErrorNotice = -100

local function Handler(err)
    local stack = debugstack and debugstack(2, 12, 0) or ""
    return { message = tostring(err), stack = stack }
end

local function Record(where, info)
    local entry = errorIndex[info.message]
    if entry then
        entry.count = entry.count + 1
        return
    end
    entry = { message = info.message, stack = info.stack, count = 1, where = where }
    errorIndex[info.message] = entry
    ns.errors[#ns.errors + 1] = entry
    local now = GetTime and GetTime() or 0
    if now - lastErrorNotice > 10 then
        lastErrorNotice = now
        ns.Print(("|cffff8040hit an error (%d so far). Type /fqln errors to copy the details.|r"):format(#ns.errors))
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

function ns.ErrorReport()
    if #ns.errors == 0 then return "No errors recorded since the last /reload." end
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
    local out = { ("QuestLine Navigator %s: %d different errors"):format(version, #ns.errors) }
    for i, e in ipairs(ns.errors) do
        out[#out + 1] = ""
        out[#out + 1] = ("#%d  (%dx, in %s)"):format(i, e.count, e.where)
        out[#out + 1] = e.message
        out[#out + 1] = e.stack
    end
    return table.concat(out, "\n")
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
