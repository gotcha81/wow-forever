-- NPC finder (the "NPCs" tab): search friendly NPCs (vendors, trainers, flight
-- masters, quest givers ...) and mark one on the world map and minimap, with
-- the blue arrow pointing at the nearest place it stands.
--
-- Data: QuestieDB's NPC data (name, title, level, spawns; Questie keeps a
-- Forever correction file for it). Wowhead is not read: addons cannot go online,
-- and Wowhead does not allow automated collecting of its pages. Each NPC has its
-- Wowhead (Forever) address so you can look it up yourself (shift-click).
--
-- The marker goes away when you mark another NPC, press Esc, remove it (the x,
-- right-click), or talk to that NPC. "Keep pinned" keeps it through Esc and
-- /reload, until you talk to the NPC or remove it.

local ADDON_NAME, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local PIN_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Pin"
local PIN_REF = ADDON_NAME .. "-npc" -- own pin set, so the route pins never remove these

local F = { ready = false, building = false, texts = {}, ids = {}, waiting = {}, world = {}, minimap = {} }
ns.NpcFinder = F

local MAX_RESULTS = 60
local MAX_PINS = 40
local WOWHEAD = "https://www.wowhead.com/forever/npc=%d"

---------------------------------------------------------------------------------------
-- Which NPCs: friendly to your faction (Questie: "A", "H" or "AH")
---------------------------------------------------------------------------------------

local function FactionLetter()
    local faction = UnitFactionGroup("player")
    if faction == "Horde" then return "H" end
    if faction == "Alliance" then return "A" end
end

function F:Info(id)
    local Q = ns.QuestieSource
    local name = Q:Npc(id, "name")
    if type(name) ~= "string" then return nil end
    local sub = Q:Npc(id, "subName")
    local minLevel, maxLevel = Q:Npc(id, "minLevel"), Q:Npc(id, "maxLevel")
    return { id = id, name = name, sub = type(sub) == "string" and sub ~= "" and sub or nil,
             minLevel = type(minLevel) == "number" and minLevel or nil,
             maxLevel = type(maxLevel) == "number" and maxLevel or nil }
end

-- Search index: lowercased "name / title / zone" per NPC, built the first time you search.
function F:Build(onDone)
    if self.ready then onDone(); return end
    self.waiting[#self.waiting + 1] = onDone
    if self.building then return end
    self.building = true

    local Q = ns.QuestieSource
    local letter = FactionLetter()
    local texts, ids, zoneNames = {}, {}, {}

    local function ZoneName(area)
        if zoneNames[area] == nil then
            local map = Q:UiMapForArea(area)
            local info = map and C_Map.GetMapInfo(map)
            zoneNames[area] = info and info.name or false
        end
        return zoneNames[area] or nil
    end

    local function Scan()
        local ok, all = pcall(Q.lib.Npc.GetAllIds)
        if not ok or type(all) ~= "table" then all = {} end
        for index = 1, #all do
            local id = all[index]
            local friendly = Q:Npc(id, "friendlyToFaction")
            if letter and type(friendly) == "string" and friendly:find(letter, 1, true) then
                local spawns = Q:Npc(id, "spawns")
                local name = Q:Npc(id, "name")
                if type(name) == "string" and type(spawns) == "table" and next(spawns) then
                    local parts = { name }
                    local sub = Q:Npc(id, "subName")
                    if type(sub) == "string" then parts[#parts + 1] = sub end
                    for area in pairs(spawns) do
                        local zone = ZoneName(area)
                        if zone then parts[#parts + 1] = zone end
                    end
                    texts[id] = table.concat(parts, "\n"):lower()
                    ids[#ids + 1] = id
                end
            end
            if index % 250 == 0 then coroutine.yield() end
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

-- Nearest spawn point to you (and its distance in yards, if the game tells us).
local function Nearest(points)
    local px, py, instance = ns.Pos.Player()
    local best, bestDistance
    for _, point in ipairs(points) do
        local d = px and (not instance or not point.instance or point.instance == instance)
            and ns.Pos.Distance(px, py, point.wx, point.wy)
        if d and (not bestDistance or d < bestDistance) then best, bestDistance = point, d end
    end
    return best or points[1], bestDistance
end
F.Nearest = Nearest

-- Results: { list = { npc info + points, nearest, distance, zone }, total = n }
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
            info.points = ns.Planner:NpcPoints(id)
            info.nearest, info.distance = Nearest(info.points)
            local p = info.nearest
            info.zone = p and ns.Pos.MapName(p.zone or p.uiMapId)
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

function F.WowheadUrl(id) return WOWHEAD:format(id) end

-- Put the Wowhead address in the chat box, where you can select and copy it (Ctrl+C).
function F:ShareUrl(id)
    local url = self.WowheadUrl(id)
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    local ok = open and pcall(open, url)
    if not ok then ns.Print(url) end
end

---------------------------------------------------------------------------------------
-- The marker
---------------------------------------------------------------------------------------

-- The arrow treats the marked NPC like a stop: { npc = info, name, state = "npc", point }
function F:Stop() return self.stop end

function F:Mark(id, keep)
    local info = self:Info(id)
    if not info then return end
    info.points = ns.Planner:NpcPoints(id)
    if #info.points == 0 then
        ns.Print(("no map position known for %s."):format(info.name))
        return
    end
    info.nearest = Nearest(info.points)
    self.stop = { npc = info, npcId = id, name = info.name, state = "npc", point = info.nearest, external = true }
    self.arrowOff = false
    self.keep = keep and true or false
    ns.charDB.npcMark = self.keep and { id = id } or nil
    self:Apply()
end

function F:Unmark(quiet)
    if not self.stop then return end
    local name = self.stop.name
    self.stop, self.keep = nil, false
    ns.charDB.npcMark = nil
    self:Apply()
    if not quiet then ns.Print(("marker for %s removed."):format(name)) end
end

function F:SetKeep(keep)
    if not self.stop then return end
    self.keep = keep and true or false
    ns.charDB.npcMark = self.keep and { id = self.stop.npcId } or nil
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
    if pin.point and pin.point.inside then GameTooltip:AddLine("Inside " .. pin.point.inside, 0.8, 0.8, 0.8) end
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
    tex:SetVertexColor(0.35, 1, 0.35)
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
            F.stop.chosen = true -- you picked this spawn: keep pointing at it
            ns.Arrow:SetTarget(ns.Planner.route[1])
        end
    end))
    return pin
end

function F:UpdatePins()
    pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, PIN_REF)
    pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, PIN_REF)
    for _, pin in ipairs(self.minimap) do pin:Hide() end
    local stop = self.stop
    if not stop then return end
    local minimapPins = not IsInInstance()
    local showFlag = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
    for i, p in ipairs(stop.npc.points) do
        if i > MAX_PINS then break end
        if type(p.uiMapId) == "number" and type(p.x) == "number" and type(p.y) == "number" then
            local world = self.world[i] or MakePin(22)
            self.world[i], world.point = world, p
            pcall(HBDPins.AddWorldMapIconMap, HBDPins, PIN_REF, world, p.uiMapId, p.x, p.y, showFlag)
            if minimapPins then
                local mini = self.minimap[i] or MakePin(16)
                self.minimap[i], mini.point = mini, p
                pcall(HBDPins.AddMinimapIconMap, HBDPins, PIN_REF, mini, p.uiMapId, p.x, p.y, true, true)
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- Setup: Esc, talking to the NPC, the kept marker after /reload
---------------------------------------------------------------------------------------

-- Events that mean you are talking to an NPC (not all exist on every client).
local TALK_EVENTS = { "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
                      "QUEST_COMPLETE", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED",
                      "PET_STABLE_SHOW", "AUCTION_HOUSE_SHOW", "CONFIRM_BINDER", "GUILDBANKFRAME_OPENED" }

local function NpcIdOf(unit)
    local guid = UnitGUID(unit)
    if guid == nil or (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" then return tonumber(id) end
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
    pcall(events.RegisterEvent, events, "ZONE_CHANGED_NEW_AREA")
    events:SetScript("OnEvent", ns.Safe("npc marker events", function(_, event)
        if not F.stop then return end
        if event == "ZONE_CHANGED_NEW_AREA" then
            F:UpdatePins() -- minimap pins are left out inside instances
            return
        end
        if NpcIdOf("npc") == F.stop.npcId then
            ns.Print(("found %s, marker removed."):format(F.stop.name))
            F:Unmark(true)
        end
    end))

    -- the arrow follows the nearest spawn as you move (unless you clicked a pin)
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
    if type(saved) == "table" and type(saved.id) == "number" and not self.stop then
        self:Mark(saved.id, true)
    end
end
