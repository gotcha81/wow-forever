-- "Show on map": the map button on a step marks where that quest starts (S) and
-- where you hand it in (E), on the world map and the minimap. One quest at a
-- time: another map button takes over, the same button again removes them, and
-- so do right-clicking a pin or /qj clear. Positions come from Questie.
-- Pins are placed with HereBeDragons-Pins (our own copy in Libs/).

local ADDON_NAME, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local PIN = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Pin"
local REF = ADDON_NAME .. "-pins"

local M = { world = {}, mini = {} }
ns.MapPins = M

local MAX_PINS = 20 -- per kind (S / E)
local COLORS = { S = { 1.00, 0.78, 0.10 }, E = { 0.35, 0.85, 0.35 } } -- gold start, green finish

local function Tooltip(pin)
    local spot = pin.spot
    if not spot or not M.questId then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Chains:QuestName(M.questId), 1, 1, 1)
    local c = COLORS[pin.kind]
    GameTooltip:AddLine((pin.kind == "S" and "Start: " or "Finish: ") .. (spot.label or "?"), c[1], c[2], c[3], true)
    if spot.inside then GameTooltip:AddLine("Inside " .. spot.inside .. " (entrance shown)", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("QuestJournal - right-click to remove", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function MakePin(size, kind)
    local pin = CreateFrame("Button", nil, UIParent)
    pin:SetSize(size, size)
    pin.tex = pin:CreateTexture(nil, "ARTWORK")
    pin.tex:SetAllPoints()
    pin.tex:SetTexture(PIN)
    local c = COLORS[kind]
    pin.tex:SetVertexColor(c[1], c[2], c[3])
    pin.label = pin:CreateFontString(nil, "OVERLAY")
    pin.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size >= 18 and 11 or 8, "OUTLINE")
    pin.label:SetPoint("CENTER", 0, 0)
    pin.label:SetText(kind)
    pin.kind = kind
    pin:RegisterForClicks("RightButtonUp")
    pin:SetScript("OnClick", ns.Safe("pin click", function() M:Clear() end))
    pin:SetScript("OnEnter", ns.Safe("pin tooltip", Tooltip))
    pin:SetScript("OnLeave", GameTooltip_Hide)
    return pin
end

local function Get(pool, kind, i, size)
    pool[kind] = pool[kind] or {}
    local pin = pool[kind][i]
    if not pin then
        pin = MakePin(size, kind)
        pool[kind][i] = pin
    end
    return pin
end

local function Spots(list)
    local D = ns.Data
    local out, seen = {}, {}
    for _, who in ipairs(list) do
        if who.kind ~= "item" then
            for _, p in ipairs(D:Points(who.kind, who.id)) do
                local key = ("%d:%.3f:%.3f"):format(p.uiMapId, p.x, p.y)
                if not seen[key] then
                    seen[key] = true
                    p.label = who.name
                    out[#out + 1] = p
                end
            end
        end
    end
    return out
end

function M:Create() end

local function RemoveAll()
    pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, REF)
    pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, REF)
    for _, pool in pairs({ M.world, M.mini }) do
        for _, list in pairs(pool) do for _, pin in ipairs(list) do pin:Hide() end end
    end
end

function M:Draw()
    RemoveAll()
    local questId = self.questId
    if not questId or not ns.Data.questie then return end
    local D = ns.Data
    local minimap = not IsInInstance()
    local showFlag = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
    local found = 0
    for kind, list in pairs({ S = Spots(D:Givers(questId)), E = Spots(D:TurnIns(questId)) }) do
        for i, spot in ipairs(list) do
            if i > MAX_PINS then break end
            found = found + 1
            local pin = Get(self.world, kind, i, 20)
            pin.spot = spot
            pcall(HBDPins.AddWorldMapIconMap, HBDPins, REF, pin, spot.uiMapId, spot.x, spot.y, showFlag)
            if minimap then
                local mini = Get(self.mini, kind, i, 14)
                mini.spot = spot
                pcall(HBDPins.AddMinimapIconMap, HBDPins, REF, mini, spot.uiMapId, spot.x, spot.y, true, true)
            end
        end
    end
    return found
end

function M:Toggle(questId)
    if self.questId == questId then
        self:Clear()
        return
    end
    self.questId = questId
    local found = self:Draw()
    if found == 0 then
        ns.Print("no map position known for " .. ns.Chains:QuestName(questId) .. ".")
    end
end

function M:Clear()
    self.questId = nil
    RemoveAll()
    if ns.Window then ns.Window:Update() end
end
