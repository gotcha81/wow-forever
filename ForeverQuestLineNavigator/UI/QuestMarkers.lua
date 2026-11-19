-- Quest markers: click a quest in the list and it is shown on the world map
-- (OpenMap too) and the minimap with our own markers, so they never get mixed up
-- with Questie's yellow ! and ? icons:
--   S    blue pin: who or what gives the quest
--   E    blue pin: who or what takes it back (turn-in)
--   dots small blue dots: where the objectives are (mobs, objects, item drops,
--        places to explore). Objectives you finished are left out.
-- One quest at a time. The markers go away when you click another quest (it
-- takes over), click the same quest again, press Esc, or turn the quest in.
-- Esc that closes the world map leaves them; the next Esc removes them.
--
-- A click also opens the game's quest log on that quest when it is in your log
-- (as Questie's tracker does), so whichever addon you clicked last is the one
-- the quest log shows. Settings: db.questMarkers, db.openQuestLog.

local ADDON_NAME, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local REF = ADDON_NAME .. "-quest" -- own pin set, separate from the route and NPC pins

local M = { pins = {}, miniPins = {}, dots = {}, miniDots = {} }
ns.QuestMarkers = M

local BLUE = { 0.30, 0.65, 1.00 }
local MAX_PINS = 20          -- S and E pins each
local MAX_DOTS = 300         -- objective dots on the world map
local MAX_MINI_DOTS = 60     -- the nearest ones on the minimap
local MAX_DROP_SOURCES = 6   -- mobs / objects per quest item

---------------------------------------------------------------------------------------
-- Where things are
---------------------------------------------------------------------------------------

local function AddSpots(list, seen, kind, id, label)
    local Q = ns.QuestieSource
    for _, p in ipairs(Q:Points(kind, id)) do
        local key = ("%d:%.3f:%.3f"):format(p[1], p[2], p[3])
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { uiMapId = p[1], x = p[2], y = p[3], inside = p.inside, label = label }
        end
    end
end

local function NpcName(id) return ns.QuestieSource:Npc(id, "name") end
local function ObjectName(id) return ns.QuestieSource:Object(id, "name") end
local function ItemName(id) return ns.QuestieSource:Item(id, "name") or ("item #" .. id) end

local function AddItemSources(list, seen, itemId, what)
    local Q = ns.QuestieSource
    local item = ItemName(itemId)
    local drops = Q:Item(itemId, "npcDrops")
    if type(drops) == "table" then
        for i = 1, math.min(#drops, MAX_DROP_SOURCES) do
            AddSpots(list, seen, "npc", drops[i], ("%s drops %s%s"):format(NpcName(drops[i]) or "a mob", item, what))
        end
    end
    local objects = Q:Item(itemId, "objectDrops")
    if type(objects) == "table" then
        for i = 1, math.min(#objects, MAX_DROP_SOURCES) do
            AddSpots(list, seen, "object", objects[i], ("%s: %s%s"):format(ObjectName(objects[i]) or "an object", item, what))
        end
    end
end

-- Objectives already done (index in Questie's order: mobs, objects, items).
local function FinishedObjectives(questId)
    local finished = {}
    if not ns.Planner.InLog(questId) then return finished end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questId)
    if ok and type(objectives) == "table" then
        for i, o in ipairs(objectives) do
            if type(o) == "table" and o.finished then finished[i] = true end
        end
    end
    return finished
end

function M:Gather(questId)
    local Q = ns.QuestieSource
    local starts, finishes, dots = {}, {}, {}
    local seenS, seenE, seenD = {}, {}, {}

    local starters = Q:Quest(questId, "startedBy")
    if type(starters) == "table" then
        for _, id in ipairs(starters[1] or {}) do AddSpots(starts, seenS, "npc", id, NpcName(id)) end
        for _, id in ipairs(starters[2] or {}) do AddSpots(starts, seenS, "object", id, ObjectName(id)) end
        -- a quest that starts from an item: where the item drops (as dots)
        for _, id in ipairs(starters[3] or {}) do AddItemSources(dots, seenD, id, ", which starts the quest") end
    end

    local finishers = Q:Quest(questId, "finishedBy")
    if type(finishers) == "table" then
        for _, id in ipairs(finishers[1] or {}) do AddSpots(finishes, seenE, "npc", id, NpcName(id)) end
        for _, id in ipairs(finishers[2] or {}) do AddSpots(finishes, seenE, "object", id, ObjectName(id)) end
    end

    local objectives = Q:Quest(questId, "objectives")
    if type(objectives) == "table" then
        local finished, index = FinishedObjectives(questId), 0
        for _, o in ipairs(objectives[1] or {}) do
            index = index + 1
            if type(o) == "table" and o[1] and not finished[index] then
                AddSpots(dots, seenD, "npc", o[1], NpcName(o[1]))
            end
        end
        for _, o in ipairs(objectives[2] or {}) do
            index = index + 1
            if type(o) == "table" and o[1] and not finished[index] then
                AddSpots(dots, seenD, "object", o[1], ObjectName(o[1]))
            end
        end
        for _, o in ipairs(objectives[3] or {}) do
            index = index + 1
            if type(o) == "table" and o[1] and not finished[index] then AddItemSources(dots, seenD, o[1], "") end
        end
    end

    -- "explore this place" objectives: { text, { [areaId] = { {x, y}, ... } } }
    local trigger = Q:Quest(questId, "triggerEnd")
    if type(trigger) == "table" and type(trigger[2]) == "table" and not ns.Planner.IsReadyToTurnIn(questId) then
        local text = type(trigger[1]) == "string" and trigger[1] or "Explore"
        for areaId, coords in pairs(trigger[2]) do
            local uiMapId = Q:UiMapForArea(areaId)
            if uiMapId and type(coords) == "table" then
                for _, c in ipairs(coords) do
                    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" then
                        dots[#dots + 1] = { uiMapId = uiMapId, x = c[1] / 100, y = c[2] / 100, label = text }
                    end
                end
            end
        end
    end
    return starts, finishes, dots
end

---------------------------------------------------------------------------------------
-- Pins and dots
---------------------------------------------------------------------------------------

local function Tooltip(frame)
    local spot, questId = frame.spot, M.questId
    if not spot or not questId then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Planner:QuestName(questId), 1, 1, 1)
    local what = frame.kind == "S" and "Quest giver" or frame.kind == "E" and "Turn in here" or "Objective"
    GameTooltip:AddLine(what .. (spot.label and (": " .. spot.label) or ""), BLUE[1], BLUE[2], BLUE[3], true)
    if spot.inside then GameTooltip:AddLine("Inside " .. spot.inside .. " (entrance shown)", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Click the quest again or press Esc to remove", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function MakePin(size, letter)
    local pin = CreateFrame("Frame", nil, UIParent)
    pin:SetSize(size, size)
    pin.tex = pin:CreateTexture(nil, "ARTWORK")
    pin.tex:SetAllPoints()
    pin.tex:SetTexture(MEDIA .. "Pin")
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font, _, flags = pin.label:GetFont()
    if font then pin.label:SetFont(font, size >= 18 and 11 or 8, flags) end
    pin.label:SetPoint("CENTER", 0, 0)
    pin.label:SetText(letter)
    pin.kind = letter
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", ns.Safe("quest marker tooltip", Tooltip))
    pin:SetScript("OnLeave", GameTooltip_Hide)
    return pin
end

local function MakeDot(size, mouse)
    local dot = CreateFrame("Frame", nil, UIParent)
    dot:SetSize(size, size)
    dot.tex = dot:CreateTexture(nil, "ARTWORK")
    dot.tex:SetAllPoints()
    dot.tex:SetTexture(MEDIA .. "Dot")
    dot.kind = "dot"
    dot:EnableMouse(mouse)
    if mouse then
        dot:SetScript("OnEnter", ns.Safe("quest marker tooltip", Tooltip))
        dot:SetScript("OnLeave", GameTooltip_Hide)
    end
    return dot
end

-- pool[key][i], made on first use
local function Get(pool, key, i, make)
    pool[key] = pool[key] or {}
    local frame = pool[key][i]
    if not frame then
        frame = make()
        pool[key][i] = frame
    end
    return frame
end

function M:Clear(quiet)
    pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, REF)
    pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, REF)
    for _, list in pairs(self.miniPins) do for _, f in ipairs(list) do f:Hide() end end
    for _, list in pairs(self.miniDots) do for _, f in ipairs(list) do f:Hide() end end
    local had = self.questId
    self.questId = nil
    if self.escFrame then self.escFrame:Hide() end
    if had and not quiet then ns.List:Update() end
end

-- (Re)places the markers of the marked quest.
function M:Draw()
    local questId = self.questId
    pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, REF)
    pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, REF)
    for _, list in pairs(self.miniPins) do for _, f in ipairs(list) do f:Hide() end end
    for _, list in pairs(self.miniDots) do for _, f in ipairs(list) do f:Hide() end end
    if not questId then return end

    local starts, finishes, dots = self:Gather(questId)
    local minimap = not IsInInstance() -- the game may not tell positions in there
    local showFlag = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2

    local function Place(frame, spot, isMinimap)
        frame.spot = spot
        if isMinimap then
            pcall(HBDPins.AddMinimapIconMap, HBDPins, REF, frame, spot.uiMapId, spot.x, spot.y, true, frame.kind ~= "dot")
        else
            pcall(HBDPins.AddWorldMapIconMap, HBDPins, REF, frame, spot.uiMapId, spot.x, spot.y, showFlag)
        end
    end

    for i, spot in ipairs(dots) do
        if i > MAX_DOTS then break end
        Place(Get(self.dots, "world", i, function() return MakeDot(8, true) end), spot, false)
    end
    if minimap and #dots > 0 then
        -- only the nearest dots on the minimap (HereBeDragons moves each one every frame)
        local px, py, pc = ns.Pos.Player()
        if px then
            local near = {}
            for _, spot in ipairs(dots) do
                local wx, wy, wc = ns.Pos.World(spot.uiMapId, spot.x, spot.y)
                if wx and wc == pc then
                    near[#near + 1] = { spot = spot, d = ns.Pos.Distance(px, py, wx, wy) }
                end
            end
            table.sort(near, function(a, b) return a.d < b.d end)
            for i = 1, math.min(#near, MAX_MINI_DOTS) do
                Place(Get(self.miniDots, "mini", i, function() return MakeDot(6, false) end), near[i].spot, true)
            end
        end
    end

    for kind, list in pairs({ S = starts, E = finishes }) do
        for i, spot in ipairs(list) do
            if i > MAX_PINS then break end
            Place(Get(self.pins, kind, i, function() return MakePin(20, kind) end), spot, false)
            if minimap then
                Place(Get(self.miniPins, kind, i, function() return MakePin(14, kind) end), spot, true)
            end
        end
    end
    self.counts = { #starts, #finishes, #dots }
end

---------------------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------------------

-- A click on a quest in our window. Returns true when the quest is now shown.
function M:Toggle(questId)
    if not questId then return false end
    if self.questId == questId then
        self:Clear()
        return false
    end
    if ns.db.questMarkers then
        self.questId = questId
        self:Draw()
        if self.escFrame then self.escFrame:Show() end
        local c = self.counts
        if c and c[1] + c[2] + c[3] == 0 then
            ns.Print(("no map positions known for %s."):format(ns.Planner:QuestName(questId)))
        end
    end
    self:OpenQuestLog(questId)
    ns.List:Update()
    return true
end

-- Opens the game's quest log on a quest in your log (the same way Questie does).
function M:OpenQuestLog(questId)
    if not ns.db.openQuestLog or not ns.Planner.InLog(questId) then return end
    -- opening it from addon code in controller mode taints Forever's gamepad bindings
    if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
        ns.Print("the quest log can't be opened by an addon in controller mode.")
        return
    end
    if InCombatLockdown() then
        ns.Print("the quest log can't be opened by an addon in combat.")
        return
    end
    if QuestMapFrame_OpenToQuestDetails then
        local ok = pcall(QuestMapFrame_OpenToQuestDetails, questId)
        if ok then return end
    end
    -- older quest log
    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questId)
    if index and QuestLogFrame and SelectQuestLogEntry then
        pcall(SelectQuestLogEntry, index)
        if not QuestLogFrame:IsShown() then pcall(ShowUIPanel, QuestLogFrame) end
    end
end

---------------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------------

function M:Create()
    -- Esc hides every frame in UISpecialFrames: this invisible one stands for the markers.
    local esc = CreateFrame("Frame", "ForeverQuestLineNavigatorQuestMarker", UIParent)
    esc:SetSize(1, 1)
    esc:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    esc:Hide()
    esc:SetScript("OnHide", ns.Safe("quest marker esc", function(self)
        if self:IsShown() then return end -- the whole UI was hidden (Alt+Z)
        if not M.questId then return end
        local pressed = GetTime()
        -- one Esc closes every window at once: if it closed the world map, keep the markers
        C_Timer.After(0, ns.Safe("quest marker esc", function()
            if not M.questId then return end
            if ns.mapHiddenAt == pressed or (WorldMapFrame and WorldMapFrame:IsShown()) then
                self:Show()
            else
                M:Clear()
            end
        end))
    end))
    table.insert(UISpecialFrames, esc:GetName())
    self.escFrame = esc

    local events = CreateFrame("Frame")
    pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
    pcall(events.RegisterEvent, events, "ZONE_CHANGED_NEW_AREA")
    events:SetScript("OnEvent", ns.Safe("quest marker events", function(_, event, questId)
        if event == "QUEST_TURNED_IN" then
            if questId and questId == M.questId then M:Clear() end
        elseif M.questId then
            M:Draw() -- minimap markers are left out inside instances
        end
    end))
end

-- After a refresh (quest log changes): finished objectives drop out.
function M:Refresh()
    if not self.questId then return end
    if not ns.db.questMarkers then self:Clear(true); return end
    self:Draw()
end
