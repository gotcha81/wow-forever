-- Minimap button: "QN" in the game's own font (Friz Quadrata), gold like the game's titles.
-- Left-click: quest list. Right-click: arrow on/off. Drag: move it around the minimap.

local ADDON_NAME, ns = ...

local B = {}
ns.MinimapButton = B

local DISC = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Pin"

local function Place(button, angle)
    local radius = (Minimap:GetWidth() / 2) + 5
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

function B:Create()
    local db = ns.db.minimap
    local b = CreateFrame("Button", "ForeverQuestLineNavigatorMinimapButton", Minimap)
    self.button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local disc = b:CreateTexture(nil, "BACKGROUND")
    disc:SetSize(21, 21)
    disc:SetPoint("CENTER", 0, 0)
    disc:SetTexture(DISC)
    disc:SetVertexColor(0.12, 0.22, 0.45)

    local label = b:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    label:SetPoint("CENTER", 1, 0)
    label:SetTextColor(1, 0.82, 0)
    label:SetText("QN")

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.db.arrow = not ns.db.arrow
            ns.Arrow:UpdateVisibility()
            ns.Print("arrow " .. (ns.db.arrow and "on" or "off"))
            ns.List:Update()
        else
            ns.List:Toggle()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("QuestLine Navigator", 0.3, 0.65, 1)
        local next = ns.Planner.route[1]
        if next then GameTooltip:AddLine("Next: " .. next.name, 1, 1, 1) end
        GameTooltip:AddLine("Left-click: quest list", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: arrow on / off", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            db.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            Place(self, db.angle)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    Place(b, db.angle)
    b:SetShown(db.shown)
end

function B:SetShown(shown)
    ns.db.minimap.shown = shown
    if self.button then self.button:SetShown(shown) end
end
