-- CleanFrame: import and export of all settings as one line of text.
--
-- Export: every setting (frames, texts, sizes, positions, borders, debuffs,
-- minimap button) as "CleanFrame:1:{...}". Import: the text is read by a small
-- parser here (never run as code), and only known settings of the right type are
-- taken over; anything else in the text is ignored.

local _, ns = ...
local P = {}
ns.Profiles = P

local HEADER = "CleanFrame:1:"
local SKIP = { errorLog = true, locked = true, perFrameDebuffs = true } -- never exported

local ANCHORS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
                  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

-- Allowed range for numbers (anything else is clamped into it).
local LIMITS = {
    width = { 100, 400 }, nameHeight = { 8, 24 }, healthHeight = { 8, 60 }, powerHeight = { 3, 40 },
    borderSize = { 1, 6 }, scale = { 0.5, 2 }, max = { 1, 40 }, size = { 12, 40 }, perRow = { 2, 20 },
    angle = { 0, 360 }, healTransparency = { 0, 100 }, costTransparency = { 0, 100 }, r = { 0, 1 }, g = { 0, 1 }, b = { 0, 1 },
}

---------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------

local function Serialize(v, top)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do
            if not (top and SKIP[k]) and (type(k) == "string" or type(k) == "number") then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local out = {}
        for _, k in ipairs(keys) do
            local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. ("%q"):format(k) .. "]")
            out[#out + 1] = key .. "=" .. Serialize(v[k])
        end
        return "{" .. table.concat(out, ",") .. "}"
    elseif t == "string" then
        return (("%q"):format(v):gsub("\n", "n")) -- one line: %q's line break becomes \n
    elseif t == "number" then
        return ("%.10g"):format(v)
    elseif t == "boolean" then
        return tostring(v)
    end
    return "false"
end

function P:Export()
    return HEADER .. Serialize(ns.db, true)
end

---------------------------------------------------------------------------------------
-- Reading (a small parser for exactly what Serialize writes)
---------------------------------------------------------------------------------------

local function Parse(s)
    local i, depth = 1, 0
    local function ws() i = s:find("[^%s]", i) or #s + 1 end
    local value
    local function str()
        i = i + 1
        local out = {}
        while true do
            local c = s:sub(i, i)
            if c == "" then error("unfinished text") end
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                local n = s:sub(i + 1, i + 1)
                local digits = s:match("^%d%d?%d?", i + 1)
                if digits then
                    out[#out + 1] = string.char(math.min(255, tonumber(digits)))
                    i = i + 1 + #digits
                else
                    out[#out + 1] = (n == "n" and "\n") or (n == "t" and "\t") or n
                    i = i + 2
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    local function tbl()
        depth = depth + 1
        if depth > 10 then error("too deep") end
        i = i + 1
        local t = {}
        while true do
            ws()
            local c = s:sub(i, i)
            if c == "}" then i = i + 1; depth = depth - 1; return t end
            if c ~= "[" then error("expected [ at " .. i) end
            i = i + 1
            ws()
            local k = value()
            ws()
            if s:sub(i, i) ~= "]" then error("expected ] at " .. i) end
            i = i + 1
            ws()
            if s:sub(i, i) ~= "=" then error("expected = at " .. i) end
            i = i + 1
            t[k] = value()
            ws()
            if s:sub(i, i) == "," then i = i + 1 end
        end
    end
    value = function()
        ws()
        local c = s:sub(i, i)
        if c == "{" then return tbl() end
        if c == '"' then return str() end
        if s:sub(i, i + 3) == "true" then i = i + 4; return true end
        if s:sub(i, i + 4) == "false" then i = i + 5; return false end
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if num and num ~= "" and tonumber(num) then i = i + #num; return tonumber(num) end
        error("unexpected text at " .. i)
    end
    local result = value()
    return result
end

-- Copies only settings that exist in `defaults`, with the same type.
local function Merge(target, defaults, incoming, key)
    for k, d in pairs(defaults) do
        local v = incoming[k]
        if not SKIP[k] and v ~= nil and type(v) == type(d) then
            if type(d) == "table" then
                if type(target[k]) ~= "table" then target[k] = {} end
                Merge(target[k], d, v, k)
            elseif type(d) == "number" then
                if v == v and v ~= math.huge and v ~= -math.huge then -- not NaN / infinite
                    local lim = LIMITS[k]
                    if lim then v = math.max(lim[1], math.min(lim[2], v)) end
                    target[k] = v
                end
            elseif type(d) == "string" then
                if key ~= "point" or ANCHORS[v] then target[k] = v end
            else
                target[k] = v
            end
        end
    end
end

function P:Import(text)
    if InCombatLockdown() then
        return false, "can't import in combat."
    end
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #HEADER) ~= HEADER then
        return false, "this is not a CleanFrame export (it should start with " .. HEADER .. ")."
    end
    if #text > 50000 then return false, "the text is too long." end
    local ok, data = pcall(Parse, text:sub(#HEADER + 1))
    if not ok or type(data) ~= "table" then
        return false, "the text could not be read (" .. tostring(data):gsub("^.-:%d+: ", "") .. ")."
    end
    local hideBefore = ns.db.hideBlizzard
    Merge(ns.db, ns.defaults, data)
    ns.Frames:Refresh()
    ns.MinimapButton:Apply()
    ns.Options:Reload()
    local note = (ns.db.hideBlizzard ~= hideBefore) and " Type /reload for the game's own frames setting." or ""
    return true, "settings imported." .. note
end

---------------------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------------------

function P:ShowExport()
    ns.ShowCopy("CleanFrame settings: Ctrl+A, Ctrl+C to copy", self:Export())
end

function P:ShowImport()
    local f = self.importFrame
    if not f then
        f = CreateFrame("Frame", "CleanFrameImportFrame", UIParent, "BackdropTemplate")
        f:SetSize(560, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("CleanFrame: paste settings (Ctrl+V), then Import")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -30, 44)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal)
        box:SetWidth(510)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(box)
        f.box = box
        local import = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        import:SetSize(110, 24)
        import:SetPoint("BOTTOMRIGHT", -12, 12)
        import:SetText("Import")
        import:SetScript("OnClick", ns.Safe("import", function()
            local ok, msg = P:Import(box:GetText())
            ns.Print(msg)
            if ok then f:Hide() end
        end))
        local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancel:SetSize(110, 24)
        cancel:SetPoint("RIGHT", import, "LEFT", -8, 0)
        cancel:SetText("Cancel")
        cancel:SetScript("OnClick", function() f:Hide() end)
        tinsert(UISpecialFrames, "CleanFrameImportFrame")
        self.importFrame = f
    end
    f.box:SetText("")
    f:Show()
    f.box:SetFocus()
end
