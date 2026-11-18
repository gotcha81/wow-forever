-- Slash command: /fqln

local _, ns = ...

local TOGGLES = {
    arrow   = { key = "arrow",        label = "Arrow" },
    pins    = { key = "pins",         label = "Map pins" },
    dungeon = { key = "dungeonFocus", label = "Dungeon focus" },
    class   = { key = "classQuests",  label = "Class quests" },
    travel  = { key = "travelTime",   label = "Travel time routing" },
    waypoint = { key = "gameWaypoint", label = "Game waypoint (experimental)" },
}

local function Debug()
    local Pos = ns.Pos
    ns.Print("debug:")
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
end

local function OnOff(value) return value and "|cff40ff40on|r" or "|cffff5555off|r" end

local function Help()
    ns.Print("commands:")
    print("  /fqln  - show or hide the quest list")
    print("  /fqln arrow|pins|dungeon|class|travel|waypoint on|off")
    print("  /fqln minimap on|off  - the QN minimap button")
    print("  /fqln debug   - position / facing values (if the arrow does not turn)")
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
    for _, name in ipairs({ "dungeon", "class", "travel", "arrow", "pins" }) do
        local t = TOGGLES[name]
        print(("  %s: %s"):format(t.label, OnOff(db[t.key])))
    end
    local p = ns.Planner
    print(("  Route: %d stops, %d without map position, %d unlocking soon, %d not worth it, %d trivial lines"):format(
        #p.route, #p.unlocated, #p.upcoming, #p.notWorth, #p.trivial))
end

SLASH_FOREVERQUESTLINENAVIGATOR1 = "/fqln"
SlashCmdList.FOREVERQUESTLINENAVIGATOR = function(input)
    if not ns.db then return end
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
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
    elseif cmd == "status" then
        Status()
    elseif cmd == "debug" then
        Debug()
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
