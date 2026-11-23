-- DisenchantInfo: the lines added to an item's tooltip.
--
--   Disenchant
--     [icon] Strange Dust - 80% - 3c - 1s 20c
--     [icon] Lesser Magic Essence - 20% - 16c - 4s
--     Average worth - 7c - 1s 76c
--   Disenchant (Arcane Salvager)
--     [icon] Strange Dust - 85% - 3c - 1s 20c
--     ...the same lines, from your own disenchants with the Salvager
--   table (unverified) - logged 4 / 0 with Salvager (20 needed)
--
-- Line: icon, material, chance, vendor price, AH price (TSM DBMarket). Without TSM a
-- line ends after the vendor price. The Arcane Salvager part shows what you got with
-- it, once enough disenchants with it are logged for this kind of item.

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

-- The table's results for an item: a list of { id, chance, min, max, avg }.
local function TableRows(info)
    local rows = {}
    if info.band then
        for i = 3, #info.band do
            local id, chance, min, max = unpack(info.band[i])
            rows[#rows + 1] = { id = id, chance = chance, min = min, max = max, avg = (min + max) / 2 }
        end
    end
    return rows
end

local function Percent(p)
    if p > 0 and p < 1 then return ("%.1f%%"):format(p) end
    return ("%d%%"):format(math.floor(p + 0.5))
end

local function Icon(itemID)
    local icon = select(5, C_Item.GetItemInfoInstant(itemID))
    return icon and ("|T" .. icon .. ":0|t ") or ""
end

-- One section: a line per material, then the average worth.
local function AddRows(tooltip, rows, tsm)
    local worth = { vendor = 0, ah = 0, vendorOk = true, ahOk = tsm }
    for _, r in ipairs(rows) do
        local qty = ""
        if ns.db.showQty then
            qty = r.min == r.max and (" x" .. r.min) or (" x" .. r.min .. "-" .. r.max)
        end
        local vendor, ah = VendorPrice(r.id), tsm and AuctionPrice(r.id) or nil
        local line = ("  %s%s%s%s|r - %s%s|r - %s"):format(Icon(r.id), WHITE, ns.Data.Name(r.id), qty,
            GOLD, Percent(r.chance), Money(vendor))
        if tsm then line = line .. " - " .. (ah and Money(ah) or "no AH data") end
        tooltip:AddLine(line)
        if vendor then worth.vendor = worth.vendor + r.chance / 100 * r.avg * vendor else worth.vendorOk = false end
        if ah then worth.ah = worth.ah + r.chance / 100 * r.avg * ah else worth.ahOk = false end
    end
    if ns.db.showTotal and #rows > 0 then
        local line = "  Average worth - " .. (worth.vendorOk and Money(worth.vendor) or "?")
        if tsm then line = line .. " - " .. (worth.ahOk and Money(worth.ah) or "?") end
        tooltip:AddLine(GOLD .. line .. "|r")
    end
end

function T:Add(tooltip, link)
    if ns.db.showFor ~= "all" and not KnowsDisenchant() then return end
    local info = ns.Data.Describe(link)
    if not info then return end
    local tsm = HasTSM()
    local needed = ns.db.minSamples
    local base = ns.Logger:Learned(info.key, "base")
    local fromLog = base ~= nil
    base = base or TableRows(info)
    local salv = ns.Logger:Learned(info.key, "salv")
    local nBase, nSalv = ns.Logger:Count(info.key, "base"), ns.Logger:Count(info.key, "salv")

    tooltip:AddLine(" ")
    tooltip:AddLine("Disenchant", 1, 0.82, 0)
    if #base == 0 then
        tooltip:AddLine(GREY .. "  No data yet for this item level. Disenchant one to learn it.|r")
    else
        AddRows(tooltip, base, tsm)
    end

    tooltip:AddLine("Disenchant (Arcane Salvager)", 1, 0.82, 0)
    if salv then
        AddRows(tooltip, salv, tsm)
    else
        tooltip:AddLine(("%s  Not known yet: %d of %d disenchants with the Salvager logged.|r"):format(GREY, nSalv, needed))
    end

    tooltip:AddLine(("%s%s - logged %d / %d with Salvager (%d needed)|r"):format(GREY,
        fromLog and "your log" or "table (unverified)", nBase, nSalv, needed))
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
