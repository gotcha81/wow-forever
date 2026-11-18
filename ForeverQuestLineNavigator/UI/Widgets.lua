-- Small shared interface pieces: padlock button, small text button, quest state tags.

local ADDON_NAME, ns = ...

local W = {}
ns.Widgets = W

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-- Padlock: closed = position pinned, open = can be dragged.
-- isLocked() returns the current state, setLocked(bool) stores it.
function W.LockButton(parent, size, isLocked, setLocked, what)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    function b:Refresh()
        self.tex:SetTexture(MEDIA .. (isLocked() and "Locked" or "Unlocked"))
    end
    b:SetScript("OnClick", function(self)
        setLocked(not isLocked())
        self:Refresh()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if isLocked() then
            GameTooltip:SetText(what .. " is pinned", 1, 1, 1)
            GameTooltip:AddLine("Click to unlock and move it", 0.8, 0.8, 0.8)
        else
            GameTooltip:SetText(what .. " can be moved", 1, 1, 1)
            GameTooltip:AddLine("Drag to move. Click to pin it in place", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Refresh()
    return b
end

-- Button showing one of our textures (cogwheel, ...), brighter on hover.
function W.IconButton(parent, size, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(MEDIA .. texture)
    b.tex:SetVertexColor(0.85, 0.85, 0.85)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(0.85, 0.85, 0.85)
        GameTooltip:Hide()
    end)
    return b
end

-- Small square button with a text label ("-", "+", "A-", ...).
function W.TextButton(parent, width, height, label, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.08, 0.12, 0.22, 0.95)
    b:SetBackdropBorderColor(0.3, 0.55, 0.9, 1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- Whether you are already on a quest, as a short coloured tag.
function W.StateTag(state, planned)
    if planned then return "|cffb0a0ff[Later]|r " end -- a step the route plans after an earlier one
    if state == "progress" then return "|cff4dc3ff[On quest]|r " end
    if state == "turnin" then return "|cff40ff40[Ready to turn in]|r " end
    return "|cffffd100[New]|r "
end

-- Addons cannot open a web browser. This puts an address in the chat box, selected,
-- so Ctrl+C copies it (and Esc closes the box again).
function W.ShareUrl(url)
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    local ok = open and pcall(open, url)
    if not ok then ns.Print(url); return end
    local box = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or LAST_ACTIVE_CHAT_EDIT_BOX
    if box and box.HighlightText then pcall(box.HighlightText, box) end
end

function W.QuestUrl(questId) return ("https://www.wowhead.com/forever/quest=%d"):format(questId) end
