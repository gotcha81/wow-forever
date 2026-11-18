-- "Nearby" window: quest NPCs that are close to you right now, with a button
-- per NPC that targets it (a click; the game does not let addons target by themselves).
--
-- Which NPCs: for every quest in your log, the NPCs you have to kill (or that drop
-- a quest item), the NPC you turn a finished quest in to, and the NPC that gives
-- the quest the arrow points at.
--
-- How we know they are close (all normal addon information, like Spy uses):
--  * nameplates appearing (about 40 yards, when nameplates are shown: V key),
--  * your target and mouseover,
--  * the combat log, if this game client still gives it to addons.
-- The game never tells addons where an NPC stands, so there is no distance or arrow
-- to the NPC itself, only "it is near you".
--
-- In combat the game does not allow changing the target buttons, so new NPCs are
-- added when combat ends (their names show as "after combat" until then).

local ADDON_NAME, ns = ...

local N = { wanted = {}, seen = {}, rows = {}, groups = {} }
ns.Nearby = N

local LINGER = 20      -- seconds an NPC seen by target / mouseover / combat log stays listed
local PLATE_LINGER = 5 -- seconds after its nameplate went away
local MAX_ROWS = 8
local WIDTH = 300
local MAX_DROP_SOURCES = 6

local function Readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function NpcIdFromGUID(guid)
    if not Readable(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

---------------------------------------------------------------------------------------
-- Which NPCs we look for
---------------------------------------------------------------------------------------

function N:UpdateWanted()
    local Q, P = ns.QuestieSource, ns.Planner
    local wanted = {}
    local function Want(npcId, questId, label)
        if type(npcId) ~= "number" then return end
        local w = wanted[npcId]
        if not w then
            w = { npcId = npcId, name = Q:Npc(npcId, "name") or ("NPC #" .. npcId), reasons = {} }
            wanted[npcId] = w
        end
        w.reasons[#w.reasons + 1] = { questId = questId, label = label }
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            local id = info and not info.isHeader and info.questID
            if id and id > 0 and not ns.Ignore:Hidden(id) then
                local questName = P:QuestName(id)
                if P.IsReadyToTurnIn(id) then
                    local finishers = Q:Quest(id, "finishedBy")
                    if type(finishers) == "table" then
                        for _, npc in ipairs(finishers[1] or {}) do Want(npc, id, "Turn in: " .. questName) end
                    end
                else
                    local game = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
                    if type(game) ~= "table" then game = {} end
                    -- the game's objective line for a name ("Gnoll Brute slain: 4/10")
                    local function GameLine(name)
                        if type(name) ~= "string" then return nil end
                        for _, o in ipairs(game) do
                            if type(o.text) == "string" and o.text:find(name, 1, true) then return o.text, o.finished end
                        end
                    end
                    local objectives = Q:Quest(id, "objectives")
                    if type(objectives) == "table" then
                        for _, o in ipairs(objectives[1] or {}) do
                            local text, finished = GameLine(Q:Npc(o[1], "name"))
                            if not finished then Want(o[1], id, text or questName) end
                        end
                        for _, o in ipairs(objectives[3] or {}) do
                            local text, finished = GameLine(Q:Item(o[1], "name"))
                            if not finished then
                                local drops = Q:Item(o[1], "npcDrops") or {}
                                for d = 1, math.min(#drops, MAX_DROP_SOURCES) do
                                    Want(drops[d], id, text or questName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- the NPC that gives the quest the arrow points at
    local target = ns.Arrow.target
    if target and target.state == "pickup" then
        local starters = Q:Quest(target.questId, "startedBy")
        if type(starters) == "table" then
            for _, npc in ipairs(starters[1] or {}) do Want(npc, target.questId, "Pick up: " .. target.name) end
        end
    end

    self.wanted = wanted
    for guid, s in pairs(self.seen) do
        if not wanted[s.npcId] then self.seen[guid] = nil end
    end
    self:CheckNameplates()
    self:Redraw()
end

-- Tell once per session when enemy nameplates are off (detection needs them).
function N:CheckNameplates()
    if self.warned or not next(self.wanted) or not ns.db.nearby.shown then return end
    local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("nameplateShowEnemies")
    if value == "0" then
        self.warned = true
        ns.Print("the Nearby window finds quest mobs by their nameplates. Enemy nameplates are off: press V to show them.")
    end
end

---------------------------------------------------------------------------------------
-- Seeing them
---------------------------------------------------------------------------------------

function N:See(guid, unit, fromPlate)
    local npcId = NpcIdFromGUID(guid)
    if not npcId or not self.wanted[npcId] then return end
    local s = self.seen[guid]
    if not s then
        s = { npcId = npcId }
        self.seen[guid] = s
    end
    s.time = GetTime()
    if fromPlate then s.plate = unit end
    if unit then
        local dead = UnitIsDead(unit)
        if Readable(dead) then s.dead = dead and true or false end
    end
    self.changed = true
end

function N:PlateGone(unit)
    for _, s in pairs(self.seen) do
        if s.plate == unit then
            s.plate = nil
            s.time = GetTime() - (LINGER - PLATE_LINGER)
            self.changed = true
        end
    end
end

function N:Died(guid)
    local s = Readable(guid) and self.seen[guid]
    if s then s.dead = true; self.changed = true end
end

-- Groups by NPC: { { w = wanted entry, count = alive ones near } }
function N:Groups()
    local now, counts = GetTime(), {}
    for guid, s in pairs(self.seen) do
        if not s.plate and now - s.time > LINGER then
            self.seen[guid] = nil
        elseif not s.dead then
            counts[s.npcId] = (counts[s.npcId] or 0) + 1
        end
    end
    local groups = {}
    for npcId, count in pairs(counts) do
        groups[#groups + 1] = { w = self.wanted[npcId], count = count }
    end
    table.sort(groups, function(a, b) return a.w.name < b.w.name end)
    return groups
end

---------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------

local function RowText(group)
    local w = group.w
    local count = group.count > 1 and (" |cffffffffx%d|r"):format(group.count) or ""
    local reason = w.reasons[1] and w.reasons[1].label or ""
    local more = #w.reasons > 1 and (" |cff808080+%d|r"):format(#w.reasons - 1) or ""
    return ("|cffff5555%s|r%s  |cffb0b0b0%s|r%s"):format(w.name, count, reason, more)
end

local function RowTooltip(row)
    local w = row.npcId and N.wanted[row.npcId]
    if not w then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(w.name, 1, 1, 1)
    for _, r in ipairs(w.reasons) do
        GameTooltip:AddLine(ns.Planner:QuestName(r.questId) .. ": " .. r.label, 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("Click: target it", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function N:Create()
    local db = ns.db.nearby
    local f = CreateFrame("Frame", "ForeverQuestLineNavigatorNearby", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, 40)
    local p = db.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        db.point = { a, b, x, y }
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.07, 0.13, 0.85)
    f:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -7)
    title:SetText("|cffff7070Nearby quest targets|r")
    local lock = ns.Widgets.LockButton(f, 14, function() return db.locked end,
        function(v) db.locked = v end, "The Nearby window")
    lock:SetPoint("TOPRIGHT", -6, -5)

    self.extra = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.extra:SetJustifyH("LEFT")
    self.extra:SetWordWrap(false)
    f:Hide()

    local events = CreateFrame("Frame")
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
                         "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA" }) do
        pcall(events.RegisterEvent, events, e)
    end
    -- the combat log may be closed to addons on this client; then we simply do without
    self.combatLog = pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED")
        and CombatLogGetCurrentEventInfo ~= nil
    events:SetScript("OnEvent", ns.Safe("nearby events", function(_, event, unit)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, sub, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
            if not next(N.wanted) then return end
            if sub == "UNIT_DIED" then N:Died(destGUID); return end
            if Readable(sourceGUID) and type(sourceGUID) == "string" and sourceGUID:sub(1, 8) == "Creature" then
                N:See(sourceGUID)
            end
            if Readable(destGUID) and type(destGUID) == "string" and destGUID:sub(1, 8) == "Creature" then
                N:See(destGUID)
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            N:See(UnitGUID(unit), unit, true)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            N:PlateGone(unit)
        elseif event == "PLAYER_TARGET_CHANGED" then
            N:See(UnitGUID("target"), "target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            N:See(UnitGUID("mouseover"), "mouseover")
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            wipe(N.seen)
            N.changed = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            N.changed = true
        end
    end))
    -- nameplates already showing when we start, then a light ticker
    C_Timer.NewTicker(0.5, ns.Safe("nearby", function()
        N.ticks = (N.ticks or 0) + 1
        if N.changed or N.ticks % 2 == 0 then
            N.changed = false
            N:Redraw()
        end
    end))
end

function N:GetRow(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, self.frame, "SecureActionButtonTemplate")
    row:SetSize(WIDTH - 12, 18)
    row:SetPoint("TOPLEFT", 6, -20 - (i - 1) * 18)
    row:RegisterForClicks("AnyUp", "AnyDown")
    row:SetAttribute("type", "macro")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", ns.Safe("nearby tooltip", RowTooltip))
    row:SetScript("OnLeave", GameTooltip_Hide)
    self.rows[i] = row
    return row
end

function N:Allowed()
    local db = ns.db.nearby
    if not db.shown then return false end
    return db.inInstances or not IsInInstance()
end

function N:Redraw()
    if not self.frame then return end
    local groups = self:Allowed() and self:Groups() or {}
    self.groups = groups

    if InCombatLockdown() then
        -- only text may change now: update rows that already target the right NPC
        local byId = {}
        for _, g in ipairs(groups) do byId[g.w.npcId] = g end
        local onRows = {}
        for _, row in ipairs(self.rows) do
            if row:IsShown() and row.npcId then
                local g = byId[row.npcId]
                onRows[row.npcId] = true
                row.text:SetText(g and RowText(g) or ("|cff808080" .. (N.wanted[row.npcId] and N.wanted[row.npcId].name or "") .. " (gone)|r"))
            end
        end
        local waiting = {}
        for _, g in ipairs(groups) do
            if not onRows[g.w.npcId] then waiting[#waiting + 1] = g.w.name end
        end
        self.extra:SetText(#waiting > 0 and ("+ %s (after combat)"):format(table.concat(waiting, ", ")) or "")
        return
    end

    local f = self.frame
    local shown = math.min(#groups, MAX_ROWS)
    for i = 1, shown do
        local g, row = groups[i], self:GetRow(i)
        row.npcId = g.w.npcId
        row:SetAttribute("macrotext", "/targetexact " .. g.w.name)
        row.text:SetText(RowText(g))
        row:Show()
    end
    for i = shown + 1, #self.rows do
        self.rows[i].npcId = nil
        self.rows[i]:Hide()
    end
    local extraText = #groups > MAX_ROWS and ("+ %d more"):format(#groups - MAX_ROWS) or ""
    self.extra:SetText(extraText)
    self.extra:ClearAllPoints()
    self.extra:SetPoint("TOPLEFT", 10, -22 - shown * 18)
    f:SetHeight(26 + shown * 18 + (extraText ~= "" and 14 or 0))
    f:SetShown(shown > 0)
end
