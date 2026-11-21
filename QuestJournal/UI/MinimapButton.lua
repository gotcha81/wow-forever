-- Minimap button: a book icon. Left-click opens or closes the journal,
-- right-click removes the map pins, drag moves it around the minimap.

local _, ns = ...

local B = {}
ns.MinimapButton = B

local function Place(button, angle)
    local radius = (Minimap:GetWidth() / 2) + 5
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

function B:Create()
    local db = ns.db.minimap
    local b = CreateFrame("Button", "QuestJournalMinimapButton", Minimap)
    self.button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER", 0, 1)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", ns.Safe("minimap click", function(_, button)
        if button == "RightButton" then
            ns.MapPins:Clear()
        else
            ns.Window:Toggle()
        end
    end))
    b:SetScript("OnEnter", ns.Safe("minimap tooltip", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("QuestJournal", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: open or close the journal", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: remove the map pins", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end))
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", ns.Safe("minimap drag", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            db.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            Place(self, db.angle)
        end))
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    Place(b, db.angle)
    b:SetShown(db.shown)
end

function B:SetShown(shown)
    ns.db.minimap.shown = shown
    if self.button then self.button:SetShown(shown) end
end
