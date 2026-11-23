-- DisenchantInfo: the lines added to an item's tooltip.
--
--   Disenchant: chance (with Salvager) - vendor - AH
--   Strange Dust x1-2 - 80% (85%) - 3c - 1s 20c
--   Lesser Magic Essence x1-2 - 20% (?) - 16c - 4s
--   Average worth - 7c (8c) - 1s 76c
--   table (unverified) - logged 4 / 0 with Salvager (20 needed)
--
-- "(?)": not enough disenchants with the Salvager logged yet for this kind of item.
-- The AH price comes from TSM (DBMarket). Without TSM a line ends after the vendor price.

local _, ns = ...
local T = {}
ns.Tooltip = T

local GOLD, GREY, WHITE = "|cffffd100", "|cff999999", "|cffffffff"

local function Money(copper)
    if type(copper) ~= "number" then return "?" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|cffffd700g|r" end
    if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|cffeda55fc|r" end
    return table.concat(parts, " ")
end

local function VendorPrice(itemID)
    local sell = select(11, C_Item.GetItemInfo(itemID))
    return sell
end

local function HasTSM()
    return type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function"
end

local function AuctionPrice(itemID)
    local ok, value = pcall(TSM_API.GetCustomPriceValue, "DBMarket", "i:" .. itemID)
    if ok and type(value) == "number" and value > 0 then return value end
    return nil
end

local function KnowsDisenchant()
    local id = ns.Data.DISENCHANT_SPELL
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    if GetProfessions and GetProfessionInfo then
        local p1, p2 = GetProfessions()
        for _, index in ipairs({ p1 or 0, p2 or 0 }) do
            if index > 0 and select(7, GetProfessionInfo(index)) == ns.Data.ENCHANTING_SKILL_LINE then
                return true
            end
        end
    end
    return false
end

-- The rows to show: { id, chance, min, max, avg, salv (chance with Salvager or nil) }.
local function Rows(info)
    local learned = ns.Logger:Learned(info.key, "base")
    local base = learned
    if not base then
        base = {}
        if info.band then
            for i = 3, #info.band do
                local id, chance, min, max = unpack(info.band[i])
                base[#base + 1] = { id = id, chance = chance, min = min, max = max, avg = (min + max) / 2 }
            end
        end
    end
    local salv = ns.Logger:Learned(info.key, "salv")
    local rows, byID = {}, {}
    for _, r in ipairs(base) do
        local row = { id = r.id, chance = r.chance, min = r.min, max = r.max, avg = r.avg }
        rows[#rows + 1] = row
        byID[r.id] = row
    end
    if salv then
        for _, row in ipairs(rows) do row.salv = 0 end
        for _, r in ipairs(salv) do
            local row = byID[r.id]
            if not row then -- something only seen with the Salvager
                row = { id = r.id, chance = 0, min = r.min, max = r.max, avg = r.avg }
                rows[#rows + 1] = row
            end
            row.salv, row.salvAvg = r.chance, r.avg
            row.min, row.max = math.min(row.min, r.min), math.max(row.max, r.max)
        end
    end
    return rows, learned ~= nil, salv ~= nil
end

local function Percent(p)
    if p == nil then return "?" end
    if p > 0 and p < 1 then return ("%.1f%%"):format(p) end
    return ("%d%%"):format(math.floor(p + 0.5))
end

function T:Add(tooltip, link)
    if ns.db.showFor ~= "all" and not KnowsDisenchant() then return end
    local info = ns.Data.Describe(link)
    if not info then return end
    local rows, fromLog, salvKnown = Rows(info)
    local tsm = HasTSM()

    tooltip:AddLine(" ")
    tooltip:AddLine(GOLD .. "Disenchant:|r chance (with Salvager) - vendor" .. (tsm and " - AH" or ""))
    if #rows == 0 then
        tooltip:AddLine(GREY .. "No disenchant data yet for this item level. Disenchant one to learn it.|r")
    end

    local worth = { vendor = 0, ah = 0, vendorS = 0, ahS = 0, vendorOk = true, ahOk = tsm }
    for _, r in ipairs(rows) do
        local qty = ""
        if ns.db.showQty then
            qty = r.min == r.max and (" x" .. r.min) or (" x" .. r.min .. "-" .. r.max)
        end
        local vendor, ah = VendorPrice(r.id), tsm and AuctionPrice(r.id) or nil
        local line = ("%s%s%s|r - %s%s|r (%s) - %s"):format(WHITE, ns.Data.Name(r.id), qty,
            GOLD, Percent(r.chance), Percent(r.salv), Money(vendor))
        if tsm then line = line .. " - " .. (ah and Money(ah) or "no AH data") end
        tooltip:AddLine(line)

        local avgS = r.salvAvg or r.avg
        if vendor then
            worth.vendor = worth.vendor + r.chance / 100 * r.avg * vendor
            if r.salv then worth.vendorS = worth.vendorS + r.salv / 100 * avgS * vendor end
        else
            worth.vendorOk = false
        end
        if ah then
            worth.ah = worth.ah + r.chance / 100 * r.avg * ah
            if r.salv then worth.ahS = worth.ahS + r.salv / 100 * avgS * ah end
        else
            worth.ahOk = false
        end
    end

    if ns.db.showTotal and #rows > 0 then
        local function Pair(value, valueS, ok)
            if not ok then return "?" end
            return Money(value) .. (salvKnown and (" (" .. Money(valueS) .. ")") or "")
        end
        local line = "Average worth - " .. Pair(worth.vendor, worth.vendorS, worth.vendorOk)
        if tsm then line = line .. " - " .. Pair(worth.ah, worth.ahS, worth.ahOk) end
        tooltip:AddLine(GOLD .. line .. "|r")
    end

    local needed = ns.db.minSamples
    tooltip:AddLine(("%s%s - logged %d / %d with Salvager (%d needed)|r"):format(GREY,
        fromLog and "your log" or "table (unverified)",
        ns.Logger:Count(info.key, "base"), ns.Logger:Count(info.key, "salv"), needed))
    if ns.db.salvager == "on" then
        tooltip:AddLine("|cff40ff40Arcane Salvager is set ON by hand (/dei salvager)|r")
    end
end

local function OnItem(tooltip)
    if not tooltip or not tooltip.GetItem or not tooltip.AddLine then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local _, link = tooltip:GetItem()
    if not link then return end
    T:Add(tooltip, link)
    tooltip:Show() -- resize for the new lines
end

function T:Hook()
    local safe = ns.Safe("tooltip", OnItem)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, safe)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", safe) end
        end
    end
end
