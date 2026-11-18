-- NPC finder (the "NPCs" tab): search friendly and neutral NPCs (vendors,
-- trainers, flight masters, quest givers ...) and mark one on the world map and
-- minimap, with the blue arrow pointing at the nearest place it stands.
--
-- Positions come from Sources/NpcSources.lua: spots you learned by playing, the
-- game's flight data, QuestieDB (spawns and walking paths) and coordinates you
-- type (/fqln pin). Wowhead is not read: addons cannot go online, and Wowhead
-- does not allow automated collecting of its pages. Each NPC has its Wowhead
-- (Forever) address so you can look it up yourself (shift-click).
--
-- The marker goes away when you mark another NPC, press Esc, remove it (the x,
-- right-click), or talk to that NPC. "Keep pinned" keeps it through Esc and
-- /reload, until you talk to the NPC or remove it.

local ADDON_NAME, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local PIN_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Pin"
local PIN_REF = ADDON_NAME .. "-npc" -- own pin set, so the route pins never remove these

local F = { ready = false, building = false, texts = {}, ids = {}, waiting = {}, world = {}, minimap = {},
            dotsWorld = {}, dotsMini = {} }
ns.NpcFinder = F

local MAX_RESULTS = 60
local MAX_PINS = 40
local MAX_PATH_DOTS = 120
local WOWHEAD = "https://www.wowhead.com/forever/npc=%d"

---------------------------------------------------------------------------------------
-- NPC info
---------------------------------------------------------------------------------------

-- { id, name, sub, minLevel, maxLevel } from Questie, else what you learned, else
-- a flight point (negative id).
function F:Info(id)
    local Src = ns.NpcSources
    if id < 0 then
        for _, node in ipairs(Src:FlightNodes()) do
            if node.id == -id then return { id = id, name = node.name, sub = "Flight point", flightPoint = true } end
        end
        return nil
    end
    local Q = ns.QuestieSource
    local name = Q:Npc(id, "name")
    local learned = Src:Learned(id)
    if type(name) ~= "string" then name = learned and learned.n end
    if type(name) ~= "string" then return nil end
    local sub = Q:Npc(id, "subName")
    local minLevel, maxLevel = Q:Npc(id, "minLevel"), Q:Npc(id, "maxLevel")
    return { id = id, name = name, sub = type(sub) == "string" and sub ~= "" and sub or nil,
             minLevel = type(minLevel) == "number" and minLevel or nil,
             maxLevel = type(maxLevel) == "number" and maxLevel or nil }
end

---------------------------------------------------------------------------------------
-- Search index
---------------------------------------------------------------------------------------

local zoneNames = {}
local function ZoneName(area)
    if zoneNames[area] == nil then
        local map = ns.QuestieSource:UiMapForArea(area)
        local info = map and C_Map.GetMapInfo(map)
        zoneNames[area] = info and info.name or false
    end
    return zoneNames[area] or nil
end

-- Searchable text of one NPC (name, title, zones; flight point names for flight masters).
local function IndexText(id)
    local info = F:Info(id)
    if not info then return nil end
    local parts = { info.name }
    if info.sub then parts[#parts + 1] = info.sub end
    local spawns = id > 0 and ns.QuestieSource:Npc(id, "spawns")
    if type(spawns) == "table" then
        for area in pairs(spawns) do parts[#parts + 1] = ZoneName(area) end
    end
    local learned = id > 0 and ns.NpcSources:Learned(id)
    if learned then
        for _, spot in ipairs(learned.s) do parts[#parts + 1] = ns.Pos.MapName(ns.Pos.Zone(spot[1])) end
    end
    if id < 0 then
        local p = ns.NpcSources:Points(id)[1]
        parts[#parts + 1] = "flight master flight path"
        if p then parts[#parts + 1] = ns.Pos.MapName(p.zone) end
    end
    local clean = {}
    for _, p in ipairs(parts) do if type(p) == "string" then clean[#clean + 1] = p end end
    return table.concat(clean, "\n"):lower()
end

local function Add(texts, ids, id)
    if texts[id] then return end
    local text = IndexText(id)
    if text then
        texts[id] = text
        ids[#ids + 1] = id
    end
end

function F:Build(onDone)
    if self.ready then onDone(); return end
    self.waiting[#self.waiting + 1] = onDone
    if self.building then return end
    self.building = true

    local Q, Src = ns.QuestieSource, ns.NpcSources
    local letter = Src.FactionLetter()
    local texts, ids = {}, {}

    local function Scan()
        local ok, all = pcall(Q.lib.Npc.GetAllIds)
        if not ok or type(all) ~= "table" then all = {} end
        local flightMasterPoints = {}
        for index = 1, #all do
            local id = all[index]
            local friendly = Q:Npc(id, "friendlyToFaction")
            local learned = Src:Learned(id)
            local ours = letter and ((type(friendly) == "string" and friendly:find(letter, 1, true))
                or (learned and (learned.f or ""):find(letter, 1, true)))
            if ours then
                local spawns = Q:Npc(id, "spawns")
                if (type(spawns) == "table" and next(spawns)) or learned then
                    Add(texts, ids, id)
                    if Src.IsFlightMaster(id) then flightMasterPoints[#flightMasterPoints + 1] = id end
                end
            end
            if index % 250 == 0 then coroutine.yield() end
        end
        -- NPCs you met that Questie does not know
        for id, learned in pairs(ns.db.npcSpots or {}) do
            if type(id) == "number" and letter and (learned.f or ""):find(letter, 1, true) then Add(texts, ids, id) end
        end
        coroutine.yield()
        -- flight points: the flight master's entry gets the point's name; points
        -- without a known flight master get their own entry
        local matched = {}
        for _, id in ipairs(flightMasterPoints) do
            for _, p in ipairs(Src:Points(id)) do
                if p.flight then
                    texts[id] = texts[id] .. "\n" .. p.flight:lower() .. "\nflight path"
                    for _, node in ipairs(Src:FlightNodes()) do
                        if node.name == p.flight then matched[node.id] = true end
                    end
                end
            end
        end
        for _, node in ipairs(Src:UsableFlightNodes()) do
            if not matched[node.id] then Add(texts, ids, -node.id) end
        end
    end

    local co = coroutine.create(Scan)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(f)
        local ok, err = coroutine.resume(co)
        if not ok then
            f:SetScript("OnUpdate", nil)
            F.building = false
            ns.LogError("npc index", err, debugstack and debugstack(co) or "")
            return
        end
        if coroutine.status(co) == "dead" then
            f:SetScript("OnUpdate", nil)
            F.texts, F.ids, F.ready, F.building = texts, ids, true, false
            local waiting = F.waiting
            F.waiting = {}
            for _, fn in ipairs(waiting) do ns.Safe("npc search", fn)() end
        end
    end)
end

-- A newly met NPC becomes searchable at once.
function F:OnLearned(id)
    if self.ready then
        Add(self.texts, self.ids, id)
        self.cache = nil
    end
end

-- Nearest point to you (and its distance in yards, if the game tells us).
local function Nearest(points)
    local px, py, instance = ns.Pos.Player()
    local best, bestDistance
    for _, point in ipairs(points) do
        local d = px and point.wx and (not instance or not point.instance or point.instance == instance)
            and ns.Pos.Distance(px, py, point.wx, point.wy)
        if d and (not bestDistance or d < bestDistance) then best, bestDistance = point, d end
    end
    return best or points[1], bestDistance
end
F.Nearest = Nearest

-- Results: { list = { npc info + points, nearest, distance }, total = n }
-- Every word must match. Nearest NPCs first, then the rest by name.
local MAX_LOOKED_AT = 400 -- matches whose map positions are worked out (for "nearest first")

function F:Find(query)
    local result = { list = {}, total = 0 }
    local words = {}
    for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 or not self.ready then return result end
    -- the list redraws often; the same search gives the same answer for a few seconds
    local key = table.concat(words, " ")
    if self.cache and self.cache.key == key and GetTime() - self.cache.time < 5 then return self.cache.result end
    local matches, here, other = {}, {}, {}
    local zone = ns.Pos.MapName(ns.Pos.PlayerZone())
    zone = type(zone) == "string" and zone:lower() or nil
    for _, id in ipairs(self.ids) do
        local text, ok = self.texts[id], true
        for _, w in ipairs(words) do
            if not text:find(w, 1, true) then ok = false; break end
        end
        if ok then
            result.total = result.total + 1
            if zone and text:find(zone, 1, true) then here[#here + 1] = id else other[#other + 1] = id end
        end
    end
    -- many matches: the ones in your zone first
    for _, id in ipairs(here) do if #matches < MAX_LOOKED_AT then matches[#matches + 1] = id end end
    for _, id in ipairs(other) do if #matches < MAX_LOOKED_AT then matches[#matches + 1] = id end end
    for _, id in ipairs(matches) do
        local info = self:Info(id)
        if info then
            info.points = ns.NpcSources:Points(id)
            info.nearest, info.distance = Nearest(info.points)
            result.list[#result.list + 1] = info
        end
    end
    table.sort(result.list, function(a, b)
        if a.distance and b.distance then return a.distance < b.distance end
        if a.distance or b.distance then return a.distance ~= nil end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    for i = MAX_RESULTS + 1, #result.list do result.list[i] = nil end
    self.cache = { key = key, time = GetTime(), result = result }
    return result
end

function F.WowheadUrl(id) return id and id > 0 and WOWHEAD:format(id) or nil end

-- Put the Wowhead address in the chat box, where you can select and copy it (Ctrl+C).
function F:ShareUrl(id)
    local url = self.WowheadUrl(id)
    if not url then return end
    ns.Widgets.ShareUrl(url)
end

---------------------------------------------------------------------------------------
-- The marker
---------------------------------------------------------------------------------------

-- The arrow treats the marked NPC like a stop: { npc = info, name, state = "npc", point }
local function SaveMark()
    local stop = F.stop
    if not (stop and F.keep) then ns.charDB.npcMark = nil; return end
    if stop.npc.manual then
        local p = stop.npc.points[1]
        ns.charDB.npcMark = { manual = { p.uiMapId, p.x, p.y, stop.name } }
    else
        ns.charDB.npcMark = { id = stop.npcId }
    end
end

function F:MarkInfo(info, keep)
    if #info.points == 0 then
        ns.Print(("no map position known for %s."):format(info.name))
        return
    end
    info.nearest = Nearest(info.points)
    self.stop = { npc = info, npcId = info.id, name = info.name, state = "npc", point = info.nearest, external = true }
    self.arrowOff = false
    self.keep = keep and true or false
    SaveMark()
    self:Apply()
end

function F:Mark(id, keep)
    local info = self:Info(id)
    if not info then return end
    info.points = ns.NpcSources:Points(id)
    self:MarkInfo(info, keep)
end

-- A marker at typed coordinates (uiMapId, x and y 0-1).
function F:MarkManual(uiMapId, x, y, name, keep)
    local point = ns.NpcSources.MakePoint(uiMapId, x, y, "your coordinates")
    if not point then
        ns.Print("that map position cannot be shown.")
        return
    end
    self:MarkInfo({ name = name, manual = true, points = { point } }, keep)
    ns.Print(("marked %s at %.1f, %.1f in %s."):format(name, x * 100, y * 100,
        ns.Pos.MapName(uiMapId) or "that zone"))
end

function F:Unmark(quiet)
    if not self.stop then return end
    local name = self.stop.name
    self.stop, self.keep = nil, false
    SaveMark()
    self:Apply()
    if not quiet then ns.Print(("marker for %s removed."):format(name)) end
end

function F:SetKeep(keep)
    if not self.stop then return end
    self.keep = keep and true or false
    SaveMark()
    self:Apply()
end

-- Map pins, Esc catcher, arrow and list after a change.
function F:Apply()
    self:UpdatePins()
    if self.escFrame then self.escFrame:SetShown(self.stop ~= nil and not self.keep) end
    ns.Arrow:SetTarget(ns.Planner.route[1])
    ns.Pins:Update()
    ns.List:Update()
end

local function PinTooltip(pin)
    local stop = F.stop
    if not stop then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(stop.name, 0.4, 1, 0.4)
    if stop.npc.sub then GameTooltip:AddLine("<" .. stop.npc.sub .. ">", 1, 1, 1) end
    local p = pin.point
    if p and p.flight then GameTooltip:AddLine("Flight point: " .. p.flight, 0.6, 0.85, 1) end
    if p and p.inside then GameTooltip:AddLine("Inside " .. p.inside, 0.8, 0.8, 0.8) end
    if p and p.source then GameTooltip:AddLine("Position: " .. p.source, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(F.keep and "Kept until you talk to this NPC" or "Marked NPC (Esc removes it)", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Click: point the arrow here  ·  Right-click: remove", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function MakePin(size)
    local pin = CreateFrame("Button", nil, UIParent)
    pin:SetSize(size, size)
    local tex = pin:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(PIN_TEXTURE)
    pin.tex = tex
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.label:SetPoint("CENTER", 0, 0)
    pin.label:SetText("!")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnEnter", ns.Safe("npc pin tooltip", PinTooltip))
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnClick", ns.Safe("npc pin click", function(self, button)
        if button == "RightButton" then F:Unmark() return end
        if F.stop and self.point then
            F.arrowOff = false
            F.stop.point = self.point
            F.stop.chosen = true -- you picked this spot: keep pointing at it
            ns.Arrow:SetTarget(ns.Planner.route[1])
        end
    end))
    return pin
end

-- Rough spots are paler, so you can tell them from known ones.
local function TintPin(pin, point)
    local rough = point.source and point.source:find("rough", 1, true)
    pin.tex:SetVertexColor(rough and 0.6 or 0.35, rough and 0.8 or 1, rough and 0.6 or 0.35)
    pin:SetAlpha(rough and 0.7 or 1)
end

local function MakeDot(size)
    local dot = CreateFrame("Frame", nil, UIParent)
    dot:SetSize(size, size)
    local tex = dot:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(0.35, 1, 0.35, 0.75)
    dot:EnableMouse(false)
    return dot
end

function F:UpdatePins()
    pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, PIN_REF)
    pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, PIN_REF)
    for _, pin in ipairs(self.minimap) do pin:Hide() end
    for _, dot in ipairs(self.dotsMini) do dot:Hide() end
    local stop = self.stop
    if not stop then return end
    local minimapPins = not IsInInstance()
    local showFlag = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2

    -- walking path (NPCs that move around): small dots under the pins
    if stop.npcId and stop.npcId > 0 then
        for i, d in ipairs(ns.NpcSources:PathDots(stop.npcId, MAX_PATH_DOTS)) do
            local world = self.dotsWorld[i] or MakeDot(4)
            self.dotsWorld[i] = world
            pcall(HBDPins.AddWorldMapIconMap, HBDPins, PIN_REF, world, d[1], d[2], d[3], showFlag)
            if minimapPins then
                local mini = self.dotsMini[i] or MakeDot(3)
                self.dotsMini[i] = mini
                pcall(HBDPins.AddMinimapIconMap, HBDPins, PIN_REF, mini, d[1], d[2], d[3], true, false)
            end
        end
    end

    for i, p in ipairs(stop.npc.points) do
        if i > MAX_PINS then break end
        if type(p.uiMapId) == "number" and type(p.x) == "number" and type(p.y) == "number" then
            local world = self.world[i] or MakePin(22)
            self.world[i], world.point = world, p
            TintPin(world, p)
            pcall(HBDPins.AddWorldMapIconMap, HBDPins, PIN_REF, world, p.uiMapId, p.x, p.y, showFlag)
            if minimapPins then
                local mini = self.minimap[i] or MakePin(16)
                self.minimap[i], mini.point = mini, p
                TintPin(mini, p)
                pcall(HBDPins.AddMinimapIconMap, HBDPins, PIN_REF, mini, p.uiMapId, p.x, p.y, true, true)
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- Setup: Esc, talking to NPCs (learn + remove the marker), the kept marker
---------------------------------------------------------------------------------------

-- Events that mean you are talking to an NPC (not all exist on every client).
local TALK_EVENTS = { "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
                      "QUEST_COMPLETE", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED",
                      "PET_STABLE_SHOW", "AUCTION_HOUSE_SHOW", "CONFIRM_BINDER", "GUILDBANKFRAME_OPENED" }

local function IsMarked(unit)
    local stop = F.stop
    if not stop then return false end
    if stop.npcId and stop.npcId > 0 then return ns.NpcSources.NpcIdOf(unit) == stop.npcId end
    local name = UnitName(unit)
    if name == nil or (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then return false end
    return name:lower() == stop.name:lower() -- a flight point or typed marker: by name
end

function F:Create()
    -- Esc hides every frame listed in UISpecialFrames: this invisible one stands for
    -- the marker, so Esc removes it (not when "keep pinned" is on).
    local esc = CreateFrame("Frame", "ForeverQuestLineNavigatorNpcMarker", UIParent)
    esc:SetSize(1, 1)
    esc:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    esc:Hide()
    esc:SetScript("OnHide", ns.Safe("npc marker esc", function(self)
        -- also fires when the whole UI is hidden (Alt+Z); then the frame itself is still "shown"
        if self:IsShown() then return end
        if F.stop and not F.keep then F:Unmark() end
    end))
    table.insert(UISpecialFrames, esc:GetName())
    self.escFrame = esc

    local events = CreateFrame("Frame")
    for _, e in ipairs(TALK_EVENTS) do pcall(events.RegisterEvent, events, e) end
    for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", ns.Safe("npc marker events", function(_, event)
        if event == "ZONE_CHANGED_NEW_AREA" then
            if F.stop then F:UpdatePins() end -- minimap pins are left out inside instances
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then ns.NpcSources:Learn("target", "rough"); return end
        if event == "UPDATE_MOUSEOVER_UNIT" then ns.NpcSources:Learn("mouseover", "rough"); return end
        ns.NpcSources:Learn("npc", "exact")
        if IsMarked("npc") then
            ns.Print(("found %s, marker removed."):format(F.stop.name))
            F:Unmark(true)
        end
    end))

    -- the arrow follows the nearest spot as you move (unless you clicked a pin)
    C_Timer.NewTicker(2, ns.Safe("npc marker", function()
        local stop = F.stop
        if stop and not stop.chosen and #stop.npc.points > 1 then
            local nearest = Nearest(stop.npc.points)
            if nearest ~= stop.point then
                stop.point = nearest
                ns.List:UpdateDistances()
            end
        end
    end))
end

-- After the data is ready: bring back a kept marker.
function F:Restore()
    local saved = ns.charDB.npcMark
    if type(saved) ~= "table" or self.stop then return end
    if type(saved.id) == "number" then
        self:Mark(saved.id, true)
    elseif type(saved.manual) == "table" then
        local m = saved.manual
        self:MarkManual(m[1], m[2], m[3], m[4] or "Map marker", true)
    end
end
