-- Slash command: /fqln

local _, ns = ...

local TOGGLES = {
    arrow   = { key = "arrow",        label = "Arrow" },
    pins    = { key = "pins",         label = "Map pins" },
    line    = { key = "routeLine",    label = "Route line on the world map" },
    dungeon = { key = "dungeonFocus", label = "Dungeon focus" },
    class   = { key = "classQuests",  label = "Class quests" },
    travel  = { key = "travelTime",   label = "Travel time routing" },
}

-- A small window with selectable text, so output can be copied (Ctrl+C).
local copyFrame
function ns.ShowCopy(title, text)
    if not copyFrame then
        local f = CreateFrame("Frame", "ForeverQuestLineNavigatorCopy", UIParent, "BackdropTemplate")
        f:SetSize(580, 340)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
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
        f:SetBackdropColor(0.04, 0.07, 0.13, 0.95)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 12, -10)
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPRIGHT", -34, -12)
        hint:SetText("Ctrl+A to select all, Ctrl+C to copy, Esc to close")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(530)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        tinsert(UISpecialFrames, f:GetName())
        copyFrame = f
    end
    copyFrame.title:SetText(title)
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

local function Debug()
    local lines = {}
    local function print(text) lines[#lines + 1] = text end
    lines[1] = ("QuestLine Navigator %s debug"):format(C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(ns.ADDON_NAME, "Version") or "")
    local Pos = ns.Pos
    local px, py, continent = Pos.Player()
    print(("  Player world: %s, %s  continent: %s"):format(tostring(px), tostring(py), tostring(continent)))
    print("  Facing: " .. tostring(Pos.Facing()))
    local map = Pos.PlayerMap()
    print(("  Map: %s  zone: %s (%s)"):format(tostring(map), tostring(Pos.PlayerZone()),
        tostring(Pos.MapName(Pos.PlayerZone()))))
    print("  In instance: " .. tostring(IsInInstance()))
    local target = ns.Arrow.target
    if target and target.point then
        local p = target.point
        print(("  Target: %s  map %s (%.3f, %.3f)  world %s, %s  continent %s"):format(target.name,
            tostring(p.uiMapId), p.x, p.y, tostring(p.wx), tostring(p.wy), tostring(p.instance)))
        local turn, distance, problem = Pos.Heading(p.wx, p.wy, p.instance)
        print(("  Turn: %s  distance: %s  problem: %s"):format(tostring(turn), tostring(distance), tostring(problem)))
    else
        print("  Target: none")
    end

    -- Game waypoint (parked feature, see README): does the game support it yet?
    local has = function(t, k) return t and type(t[k]) == "function" and "yes" or "no" end
    print(("  Game waypoint APIs: SetUserWaypoint %s, UiMapPoint %s, SuperTrack %s"):format(
        has(C_Map, "SetUserWaypoint"),
        (UiMapPoint and UiMapPoint.CreateFromCoordinates) and "yes" or "no",
        has(C_SuperTrack, "SetSuperTrackedUserWaypoint")))
    if target and target.point and C_Map and C_Map.CanSetUserWaypointOnMap then
        local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, target.point.uiMapId)
        print("  Can set waypoint on target map: " .. tostring(ok and can))
    end
    if C_Map and C_Map.HasUserWaypoint then
        local ok, hasPoint = pcall(C_Map.HasUserWaypoint)
        print("  Game has a waypoint now: " .. tostring(ok and hasPoint))
    end
    if C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint then
        local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
        print("  Game is tracking it: " .. tostring(ok and tracking))
    end
    ns.ShowCopy("QuestLine Navigator: debug", table.concat(lines, "\n"))
end

local function OnOff(value) return value and "|cff40ff40on|r" or "|cffff5555off|r" end

local function Help()
    ns.Print("commands:")
    print("  /fqln  - show or hide the quest list")
    print("  /fqln arrow|pins|line|dungeon|class|travel on|off")
    print("  /fqln minimap on|off  - the QN minimap button")
    print("  /fqln arrowtext <8-24>  - text size under the arrow (now " .. ns.db.arrowFrame.textSize .. ")")
    print("  /fqln lock|unlock arrow|window  - pin or free a position (or use the padlocks)")
    print("  /fqln d [name]  - the Dungeon tab (optionally pick a dungeon by name)")
    print("  /fqln z [name]  - the Zone tab (optionally pick a zone by name)")
    print("  /fqln npc [name]  - the NPCs tab: find a friendly NPC and mark it on the map")
    print("  /fqln pin [zone] x y [name]  - mark your own coordinates (e.g. from Wowhead)")
    print("  /fqln unmark  - remove the NPC marker")
    print("  /fqln killtime <s>  - seconds you take per quest mob (route timing, now " .. ns.db.killSeconds .. ")")
    print("  /fqln dungeontime <min>  - minutes per dungeon run (now " .. ns.db.dungeonMinutes .. ")")
    print("  /fqln dungeoncheck on|off  - list missing quests when you enter a dungeon")
    print("  /fqln nearby on|off  - the Nearby quest targets window")
    print("  /fqln debug   - position / facing values (if the arrow does not turn)")
    print("  /fqln errors  - the error log (copy window); /fqln errors clear empties it")
    print("  /fqln riding auto|none|60|100  - riding speed (auto detects it)")
    print("  /fqln ahead <levels>  - list chains that unlock within this many levels (now " .. ns.db.levelAhead .. ")")
    print("  /fqln wait <seconds>  - boat/zeppelin 'just missed it' wait (now " .. ns.db.boatWait .. ")")
    print("  /fqln status  - what the addon is using right now")
    print("  /fqln reset   - move the window and arrow back to their default place")
end

local function Status()
    local db = ns.db
    ns.Print("status:")
    local lib = ns.QuestieSource.lib
    print(("  QuestieDB contract %s, %d dungeon/class quests known"):format(
        lib and tostring(lib.contractVersion) or "?", ns.Planner.catalogCount or 0))
    print("  DungeonJournal data: " .. OnOff(ns.DungeonJournalSource.available))
    local openMap = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("OpenMap")
    print("  OpenMap: " .. (openMap and "|cff40ff40loaded|r (pins show on it)" or "not loaded (pins on Blizzard's map)"))
    local speed, how = ns.Planner:Riding()
    print(("  Riding: %s (%s)"):format(speed > 0 and (speed .. "%") or "none", how or ""))
    for _, name in ipairs({ "dungeon", "class", "travel", "arrow", "pins", "line" }) do
        local t = TOGGLES[name]
        print(("  %s: %s"):format(t.label, OnOff(db[t.key])))
    end
    local R = ns.Router
    print(("  Route planning: travel times %s, ForeverDB %s, plan ~%d min at ~%s XP/h"):format(
        ns.Travel:Available() and "|cff40ff40from Shortest Path Forever|r" or "straight line (Shortest Path Forever not found)",
        ns.ForeverDBSource.available and ("|cff40ff40" .. tostring(ns.ForeverDBSource.build) .. "|r")
            or (db.useForeverDB and "not found" or "off"),
        R.minutes or 0, ns.XP.Format(R.xpPerHour or 0)))
    print(("  NPC positions: %d NPCs learned by playing, %d flight points from the game"):format(
        ns.NpcSources:LearnedCount(), #ns.NpcSources:FlightNodes()))
    local wantedCount = 0
    for _ in pairs(ns.Nearby.wanted) do wantedCount = wantedCount + 1 end
    print(("  Nearby: %s, looking for %d NPCs, combat log %s"):format(OnOff(db.nearby.shown), wantedCount,
        ns.Nearby.combatLog and "|cff40ff40available|r" or "not available (nameplates, target and mouseover only)"))
    local p = ns.Planner
    print(("  Route: %d stops, %d without map position, %d unlocking soon, %d not worth it, %d trivial lines"):format(
        #p.route, #p.unlocated, #p.upcoming, #p.notWorth, #p.trivial))
end

SLASH_FOREVERQUESTLINENAVIGATOR1 = "/fqln"
local function SlashCommand(input)
    if not ns.db then return end
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local rawArg = (input or ""):match("^%s*%S*%s*(.-)%s*$") or "" -- as typed (names keep their capitals)
    local db = ns.db

    if cmd == "" then
        ns.List:Toggle()
    elseif cmd == "show" then
        ns.List:SetShown(true)
    elseif cmd == "hide" then
        ns.List:SetShown(false)
    elseif TOGGLES[cmd] then
        local t = TOGGLES[cmd]
        if arg == "on" then db[t.key] = true
        elseif arg == "off" then db[t.key] = false
        else db[t.key] = not db[t.key] end
        ns.Print(t.label .. ": " .. OnOff(db[t.key]))
        ns.Arrow:UpdateVisibility()
        ns.RequestRefresh(0)
    elseif cmd == "riding" then
        if arg == "auto" or arg == "none" or arg == "60" or arg == "100" then
            db.riding = arg
            local speed, how = ns.Planner:Riding()
            ns.Print(("riding: %s (%s)"):format(speed > 0 and (speed .. "%") or "none", how))
            ns.RequestRefresh(0)
        else
            ns.Print("use: /fqln riding auto|none|60|100")
        end
    elseif cmd == "ahead" or cmd == "wait" then
        local n = tonumber(arg)
        local key = (cmd == "ahead") and "levelAhead" or "boatWait"
        local max = (cmd == "wait") and 3600 or 60
        if n and n >= 0 and n <= max then
            db[key] = math.floor(n)
            ns.Print(cmd .. ": " .. db[key])
            ns.RequestRefresh(0)
        else
            ns.Print(("use: /fqln %s <0-%d>"):format(cmd, max))
        end
    elseif cmd == "d" then
        db.list.tab = "dungeon"
        if arg ~= "" then
            local d = ns.DungeonView:Find(arg)
            if d then db.list.dungeon = d.name else ns.Print("no dungeon found for \"" .. arg .. "\".") end
        end
        ns.List.picking = false
        ns.List:SetShown(true)
    elseif cmd == "z" or cmd == "zone" then
        db.list.tab = "zone"
        ns.List.picking = false
        ns.List:SetShown(true)
        if arg ~= "" then
            ns.ZoneView:Build(function()
                local z = ns.ZoneView:Find(arg)
                if z then db.list.zone = z.name else ns.Print("no zone found for \"" .. arg .. "\".") end
                ns.List:Update()
            end)
        end
    elseif cmd == "npc" then
        db.list.tab = "npc"
        ns.List.picking = false
        ns.List:SetShown(true)
        if rawArg ~= "" then ns.List.searchBox:SetText(rawArg) end
    elseif cmd == "killtime" or cmd == "dungeontime" then
        local key = cmd == "killtime" and "killSeconds" or "dungeonMinutes"
        local n = tonumber(arg)
        if n and n > 0 and n <= 180 then
            db[key] = math.floor(n)
            ns.Print(("%s: %d %s"):format(cmd, db[key], cmd == "killtime" and "seconds per mob" or "minutes per run"))
            ns.RequestRefresh(0)
        else
            ns.Print(("%s is %d. Use: /fqln %s <number>"):format(cmd, db[key], cmd))
        end
    elseif cmd == "pin" then
        local map, x, y, name = ns.NpcSources:ParsePin(rawArg)
        if not map then
            ns.Print(x)
        else
            ns.NpcFinder:MarkManual(map, x, y, name, db.list.npcKeep)
        end
    elseif cmd == "unmark" then
        if ns.NpcFinder.stop then ns.NpcFinder:Unmark() else ns.Print("no NPC is marked.") end
    elseif cmd == "nearby" then
        local n = db.nearby
        if arg == "on" then n.shown = true elseif arg == "off" then n.shown = false else n.shown = not n.shown end
        ns.Print("Nearby quest targets: " .. OnOff(n.shown))
        if InCombatLockdown() then ns.Print("(the window updates after combat)") end
        ns.Nearby:Redraw()
    elseif cmd == "dungeoncheck" then
        if arg == "on" then db.dungeonCheck = true
        elseif arg == "off" then db.dungeonCheck = false
        else db.dungeonCheck = not db.dungeonCheck end
        ns.Print("check quests when entering a dungeon: " .. OnOff(db.dungeonCheck))
    elseif cmd == "status" then
        Status()
    elseif cmd == "debug" then
        Debug()
    elseif cmd == "errors" then
        if arg == "clear" then
            ns.ClearErrors()
            ns.Print("error log cleared.")
        else
            ns.ShowCopy("QuestLine Navigator: error log", ns.ErrorReport())
        end
    elseif cmd == "arrowtext" then
        local n = tonumber(arg)
        if n then
            ns.Arrow:SetTextSize(n)
            ns.Print("arrow text size: " .. db.arrowFrame.textSize)
        else
            ns.Print("use: /fqln arrowtext <8-24>")
        end
    elseif cmd == "lock" or cmd == "unlock" then
        local locked = cmd == "lock"
        if arg == "arrow" then
            db.arrowFrame.locked = locked
        elseif arg == "window" or arg == "list" then
            db.list.locked = locked
        else
            db.arrowFrame.locked, db.list.locked = locked, locked
        end
        ns.Print((locked and "locked" or "unlocked") .. ". Type /reload to update the padlock icons.")
    elseif cmd == "minimap" then
        local shown = (arg == "on") or (arg ~= "off" and not db.minimap.shown)
        ns.MinimapButton:SetShown(shown)
        ns.Print("minimap button: " .. OnOff(shown))
    elseif cmd == "reset" then
        db.list.point = { unpack(ns.defaults.list.point) }
        db.arrowFrame.point = { unpack(ns.defaults.arrowFrame.point) }
        ns.Print("positions reset. Type /reload to apply.")
    else
        Help()
    end
end

SlashCmdList.FOREVERQUESTLINENAVIGATOR = ns.Safe("command", SlashCommand)
