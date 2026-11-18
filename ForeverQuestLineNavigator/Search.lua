-- Quest search (the box under the tabs).
-- Searches every quest your race and class can do, by quest name, questline,
-- dungeon, zone and the NPC or object that starts it. The index is built the
-- first time you search (spread over a few frames), not at login.

local _, ns = ...

local S = { ready = false, building = false, texts = {}, ids = {}, waiting = {} }
ns.Search = S

local MAX_MATCHES = 150 -- matches looked at in detail (status, XP, start)

function S:Build(onDone)
    if self.ready then onDone(); return end
    self.waiting[#self.waiting + 1] = onDone
    if self.building then return end
    self.building = true

    local Q, P, O = ns.QuestieSource, ns.Planner, ns.Overrides
    local texts, ids, zoneNames = {}, {}, {}

    local function ZoneName(area)
        if zoneNames[area] == nil then
            local map = Q:UiMapForArea(area)
            local info = map and C_Map.GetMapInfo(map)
            zoneNames[area] = info and info.name or false
        end
        return zoneNames[area] or nil
    end

    local function Add(id)
        if texts[id] then return end
        local parts = { P:QuestName(id) }
        local target = P.targets[id]
        if target and target.dungeon then parts[#parts + 1] = target.dungeon end
        local zone = Q:Quest(id, "zoneOrSort")
        if type(zone) == "number" and zone > 0 then parts[#parts + 1] = ZoneName(zone) end
        local starters = Q:Quest(id, "startedBy")
        if type(starters) == "table" then
            for i, npc in ipairs(starters[1] or {}) do
                if i > 3 then break end
                parts[#parts + 1] = Q:Npc(npc, "name")
            end
            for i, obj in ipairs(starters[2] or {}) do
                if i > 2 then break end
                parts[#parts + 1] = Q:Object(obj, "name")
            end
        end
        local clean = {}
        for _, p in ipairs(parts) do if type(p) == "string" then clean[#clean + 1] = p end end
        texts[id] = table.concat(clean, "\n"):lower()
        ids[#ids + 1] = id
    end

    local function Scan()
        local all = Q:AllQuestIds()
        for index = 1, #all do
            local id = all[index]
            if not O.hiddenQuests[id] and P.RaceOk(id) and P.ClassOk(id) then Add(id) end
            if index % 300 == 0 then coroutine.yield() end
        end
        for id in pairs(P.targets) do Add(id) end -- DungeonJournal-only quests too
        coroutine.yield()
        for i, line in ipairs(P.lines) do
            local name = P:LineName(line):lower()
            for _, id in ipairs(line.steps) do
                if texts[id] and not texts[id]:find(name, 1, true) then texts[id] = texts[id] .. "\n" .. name end
            end
            if i % 100 == 0 then coroutine.yield() end
        end
    end

    local co = coroutine.create(Scan)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(f)
        local ok, err = coroutine.resume(co)
        if not ok then
            f:SetScript("OnUpdate", nil)
            S.building = false
            ns.LogError("search index", err, debugstack and debugstack(co) or "")
            return
        end
        if coroutine.status(co) == "dead" then
            f:SetScript("OnUpdate", nil)
            S.texts, S.ids, S.ready, S.building = texts, ids, true, false
            local waiting = S.waiting
            S.waiting = {}
            for _, fn in ipairs(waiting) do ns.Safe("search", fn)() end
        end
    end)
end

-- Results for a query: { open = {entries}, grey = {entries}, total = n, capped = bool }.
-- Every word must match (in any of the searched fields).
function S:Find(query)
    local result = { open = {}, grey = {}, total = 0, capped = false }
    local words = {}
    for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 or not self.ready then return result end

    local level = UnitLevel("player")
    local levelXP = UnitXPMax("player") or 0
    local D = ns.DungeonView
    for _, id in ipairs(self.ids) do
        local text, ok = self.texts[id], true
        for _, w in ipairs(words) do
            if not text:find(w, 1, true) then ok = false; break end
        end
        if ok then
            result.total = result.total + 1
            if result.total > MAX_MATCHES then
                result.capped = true
            else
                local e = D:Entry(id, level, levelXP)
                if e.trivialHidden and e.state ~= "done" then
                    result.grey[#result.grey + 1] = e
                else
                    result.open[#result.open + 1] = e
                end
            end
        end
    end
    table.sort(result.open, D.SortEntries)
    table.sort(result.grey, D.SortEntries)
    return result
end
