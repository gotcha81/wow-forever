-- Numbered pins on the world map and minimap, placed with HereBeDragons-Pins.
-- OpenMap (if installed) picks up HereBeDragons pins by itself, so the same pins
-- show on its seamless map without any OpenMap-specific code here.

local ADDON_NAME, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local PIN_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Pin"

local Pins = { world = {}, minimap = {} }
ns.Pins = Pins

local ACTION = { pickup = "Pick up", turnin = "Turn in", progress = "Objectives" }

local function OnEnter(pin)
    local stop = pin.stop
    if not stop then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%d. %s"):format(pin.index, stop.name), 1, 1, 1)
    GameTooltip:AddLine(ns.Widgets.StateTag(stop.state) .. (ACTION[stop.state] or ""), 1, 0.82, 0)
    if stop.dungeon then GameTooltip:AddLine(stop.dungeon, 0.6, 0.8, 1) end
    GameTooltip:AddLine(ns.Planner:XPText(stop), 1, 0.82, 0)
    if stop.primary then
        local line = stop.primary.line
        GameTooltip:AddLine("Questline: " .. ns.Planner:LineName(line), 0.6, 0.85, 1)
        GameTooltip:AddLine(ns.Planner:StepText(line, stop.primary.index), 0.8, 0.8, 0.8)
    end
    if stop.point and stop.point.inside then
        GameTooltip:AddLine("Inside " .. stop.point.inside .. " (entrance shown)", 0.8, 0.8, 0.8)
    elseif stop.point and stop.point.note then
        GameTooltip:AddLine(stop.point.note, 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click: point the arrow here", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function MakePin(size)
    local pin = CreateFrame("Button", nil, UIParent)
    pin:SetSize(size, size)
    local tex = pin:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(PIN_TEXTURE)
    pin.tex = tex
    pin.label = pin:CreateFontString(nil, "OVERLAY", size >= 18 and "GameFontHighlightSmall" or "GameFontHighlightExtraSmall")
    pin.label:SetPoint("CENTER", 0, 0)
    pin:SetScript("OnEnter", OnEnter)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnClick", function(self) if self.stop then ns.Arrow:Pin(self.stop) end end)
    return pin
end

local function Prepare(pool, index, size, stop)
    local pin = pool[index] or MakePin(size)
    pool[index] = pin
    pin.index, pin.stop = index, stop
    pin.label:SetText(index)
    local isTarget = ns.Arrow.target == stop
    pin.tex:SetVertexColor(1, isTarget and 0.85 or 1, isTarget and 0.2 or 1)
    return pin
end

function Pins:Update()
    HBDPins:RemoveAllWorldMapIcons(ADDON_NAME)
    HBDPins:RemoveAllMinimapIcons(ADDON_NAME)
    if not ns.db.pins then return end
    local showFlag = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
    for i, stop in ipairs(ns.Planner.route) do
        local p = stop.point
        if p then
            local worldPin = Prepare(self.world, i, 20, stop)
            HBDPins:AddWorldMapIconMap(ADDON_NAME, worldPin, p.uiMapId, p.x, p.y, showFlag)
            local miniPin = Prepare(self.minimap, i, 14, stop)
            HBDPins:AddMinimapIconMap(ADDON_NAME, miniPin, p.uiMapId, p.x, p.y, true, ns.Arrow.target == stop)
        end
    end
end
