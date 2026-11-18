-- Forever QuestLine Navigator: core (namespace, saved settings, events, start-up).
-- Everything lives in the private addon namespace `ns`; the only globals are the
-- SavedVariables table and the slash command, both with unique names.

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME
ns.ready = false

local PREFIX = "|cff4da6ffQuestLine Navigator|r: "

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- Defaults for the account-wide settings table.
ns.defaults = {
    dungeonFocus = true,   -- only dungeon quest chains (plus class quests if enabled)
    classQuests  = true,   -- include class quests for your class
    travelTime   = false,  -- route by estimated travel time instead of plain distance
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

-- Coalesce many events into one refresh.
local refreshQueued = false
function ns.RequestRefresh(delay)
    if refreshQueued or not ns.ready then return end
    refreshQueued = true
    C_Timer.After(delay or 0.4, function()
        refreshQueued = false
        ns.Refresh()
    end)
end

function ns.Refresh()
    if not ns.ready then return end
    ns.Planner:Update()
    ns.Arrow:SetTarget(ns.Planner.route[1])
    ns.List:Update()
    ns.Pins:Update()
end

local function Start()
    if ns.ready then return end
    ns.Planner:BuildCatalog(function()
        ns.ready = true
        ns.Refresh()
        local dj = ns.DungeonJournalSource.available and "on" or "off"
        ns.Print(("ready. %d dungeon and class questlines found (DungeonJournal data: %s). Type /fqln for options.")
            :format(ns.Planner.catalogCount or 0, dj))
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(self, event, arg1, arg2)
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

        -- Questie's public API tells us when its data is ready.
        if Questie and Questie.API and type(Questie.API.RegisterOnReady) == "function" then
            Questie.API.RegisterOnReady(Start)
        else
            C_Timer.After(5, Start)
        end

        for _, e in ipairs({
            "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
            "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
            "QUEST_DATA_LOAD_RESULT",
        }) do
            self:RegisterEvent(e)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Arrow:UpdateVisibility()
        ns.RequestRefresh(1)
    elseif event == "PLAYER_LEVEL_UP" then
        ns.XP:Clear() -- quest XP depends on your level
        ns.RequestRefresh(0.5)
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        ns.XP:OnQuestDataLoaded(arg1, arg2)
    else
        ns.RequestRefresh()
    end
end)
