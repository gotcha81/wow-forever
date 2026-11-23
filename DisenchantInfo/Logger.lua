-- DisenchantInfo: logs every disenchant and learns the chances from it, separately
-- without and with the Arcane Salvager.
--
-- How a disenchant is caught:
--   UNIT_SPELLCAST_SENT (Disenchant, target = the item's name) -> remember the item
--   UNIT_SPELLCAST_SUCCEEDED                                   -> it worked
--   LOOT_READY                                                 -> read what came out
-- The item comes from the loot source (the disenchanted item's GUID) when the game
-- gives it, else from the bag item with the cast's target name, else from the last
-- bag item clicked while Disenchant was waiting for a target.
--
-- Arcane Salvager: nobody has published its effect, so the addon learns it. "auto"
-- looks for a buff with "Salvager" in its name. Nobody knows yet whether there is
-- one, so every log entry also keeps your buffs and the spell ID. With that, the
-- right signal can be found later. Until then, switch it on by hand
-- (/dei salvager, or right-click the addon menu entry).
--
-- Saved data (DisenchantInfoDB):
--   stats[key][mode] = { n = disenchants, mats = { [itemID] = { hits, qty, min, max } } }
--     key  = "armor:2:16-20" (class, quality, item level band; see Data.lua)
--     mode = "base" (without Salvager) or "salv" (with it)
--   log = the last MAX_LOG disenchants in full

local _, ns = ...
local L = {}
ns.Logger = L

local MAX_LOG = 1000
local LOOT_WINDOW = 6 -- seconds after the cast that the loot must come

local pending -- { castGUID, name, link, spellID, sentAt, doneAt }
local lastClicked -- { link, at }

---------------------------------------------------------------------------------------
-- Arcane Salvager state
---------------------------------------------------------------------------------------

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

-- The player's buffs: a list of { spellId, name }.
local function PlayerBuffs()
    local list = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list end
    for i = 1, 60 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        local id, name = aura.spellId, aura.name
        if IsSecret(id) then id = nil end
        if IsSecret(name) then name = nil end
        list[#list + 1] = { id = id, name = name }
    end
    return list
end

local function SalvagerBuff()
    for _, b in ipairs(PlayerBuffs()) do
        if type(b.name) == "string" and b.name:lower():find("salvag", 1, true) then return b end
    end
    return nil
end

-- active (true/false), how ("aura", "auto", "manual", "off")
function L:SalvagerActive()
    local mode = ns.db.salvager
    if mode == "on" then return true, "manual" end
    if mode == "off" then return false, "off" end
    if SalvagerBuff() then return true, "aura" end
    return false, "auto"
end

function L:SalvagerText()
    local active, how = self:SalvagerActive()
    if how == "manual" then return "|cff40ff40ON|r (set by hand)" end
    if how == "off" then return "|cffff4040OFF|r (set by hand)" end
    if active then return "|cff40ff40ON|r (auto: buff found)" end
    return "off (auto: no Salvager buff found)"
end

local CYCLE = { auto = "on", on = "off", off = "auto" }

function L:CycleSalvager()
    self:SetSalvager(CYCLE[ns.db.salvager] or "auto")
end

function L:SetSalvager(mode)
    ns.db.salvager = mode
    ns.Print("Arcane Salvager: " .. self:SalvagerText())
    if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
end

---------------------------------------------------------------------------------------
-- Finding the item
---------------------------------------------------------------------------------------

local function IsDisenchant(spellID)
    if spellID == ns.Data.DISENCHANT_SPELL then return true end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    local de = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ns.Data.DISENCHANT_SPELL)
    return name ~= nil and name == de
end

local function FindInBags(itemName)
    if type(itemName) ~= "string" or itemName == "" or IsSecret(itemName) then return nil end
    for bag = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local name = C_Item.GetItemInfo(info.hyperlink)
                if name == itemName then return info.hyperlink end
            end
        end
    end
    return nil
end

local function LinkFromLootSource()
    if not GetLootSourceInfo then return nil end
    for slot = 1, (GetNumLootItems() or 0) do
        local guid = GetLootSourceInfo(slot)
        if type(guid) == "string" and not IsSecret(guid) and guid:find("^Item%-") then
            if C_Item.GetItemLinkByGUID then
                local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
                if ok and link then return link end
            end
            return nil
        end
    end
    return nil
end

---------------------------------------------------------------------------------------
-- Learned numbers
---------------------------------------------------------------------------------------

local function Bucket(key, mode)
    local byKey = ns.db.stats[key]
    if not byKey then
        byKey = {}
        ns.db.stats[key] = byKey
    end
    local b = byKey[mode]
    if not b then
        b = { n = 0, mats = {} }
        byKey[mode] = b
    end
    return b
end

-- Number of logged disenchants for a key and mode ("base" / "salv").
function L:Count(key, mode)
    local byKey = ns.db.stats[key]
    return byKey and byKey[mode] and byKey[mode].n or 0
end

-- Learned results: a list of { id, chance, min, max, avg } sorted by chance, or nil
-- when fewer than the needed disenchants are logged.
function L:Learned(key, mode)
    local byKey = ns.db.stats[key]
    local b = byKey and byKey[mode]
    if not b or b.n < math.max(1, ns.db.minSamples or 20) then return nil end
    local list = {}
    for id, m in pairs(b.mats) do
        list[#list + 1] = { id = id, chance = 100 * m.hits / b.n, min = m.min, max = m.max,
                            avg = m.hits > 0 and m.qty / m.hits or 0 }
    end
    table.sort(list, function(a, c) return a.chance > c.chance end)
    return list
end

local function Record(link, loot, spellID)
    local info = ns.Data.Describe(link)
    if not info then return end
    local salv, how = L:SalvagerActive()
    local mode = salv and "salv" or "base"
    local b = Bucket(info.key, mode)
    b.n = b.n + 1
    local got = {}
    for _, l in ipairs(loot) do
        local m = b.mats[l.id]
        if not m then
            m = { hits = 0, qty = 0, min = l.qty, max = l.qty }
            b.mats[l.id] = m
        end
        m.hits = m.hits + 1
        m.qty = m.qty + l.qty
        if l.qty < m.min then m.min = l.qty end
        if l.qty > m.max then m.max = l.qty end
        got[#got + 1] = l.qty .. "x " .. ns.Data.Name(l.id)
    end

    -- Full entry, with the buffs and spell ID to find the Salvager's signal later.
    local buffs = {}
    for _, bf in ipairs(PlayerBuffs()) do
        buffs[#buffs + 1] = tostring(bf.id or "?") .. "=" .. tostring(bf.name or "?")
    end
    local log = ns.db.log
    log[#log + 1] = {
        at = date("%Y-%m-%d %H:%M:%S"), item = C_Item.GetItemInfoInstant(link), level = info.level,
        quality = info.quality, class = info.class, key = info.key, salvager = salv, how = how,
        spell = spellID, loot = loot, buffs = table.concat(buffs, ";"),
    }
    while #log > MAX_LOG do table.remove(log, 1) end

    if ns.db.chatLog then
        ns.Print(("%s: %s  |cff999999(Salvager %s, %d logged of this kind)|r"):format(
            link, #got > 0 and table.concat(got, ", ") or "nothing", salv and "on" or "off", b.n))
    end
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local function ReadLoot()
    local loot = {}
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local _, _, qty = GetLootSlotInfo(slot)
        local id = link and C_Item.GetItemInfoInstant(link)
        if id then loot[#loot + 1] = { id = id, qty = tonumber(qty) or 1 } end
    end
    return loot
end

local function OnEvent(_, event, unit, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SENT" then
        -- unit, target name, castGUID, spellID
        if unit ~= "player" or not IsDisenchant(a4) then return end
        local link = FindInBags(a2)
        if not link and lastClicked and GetTime() - lastClicked.at < 30 then link = lastClicked.link end
        pending = { castGUID = a3, name = a2, link = link, spellID = a4, sentAt = GetTime() }
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, castGUID, spellID
        if unit == "player" and pending and (a2 == pending.castGUID or IsDisenchant(a3)) then
            pending.doneAt = GetTime()
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if unit == "player" and pending and a2 == pending.castGUID then pending = nil end
    elseif event == "LOOT_READY" then
        if not (pending and pending.doneAt and GetTime() - pending.doneAt < LOOT_WINDOW) then return end
        local p = pending
        pending = nil -- LOOT_READY can fire twice: count once
        local link = LinkFromLootSource() or p.link
        if not link then
            ns.Print("|cffff8040a disenchant could not be logged: the item wasn't found.|r")
            return
        end
        Record(link, ReadLoot(), p.spellID)
    end
end

function L:Start()
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    f:RegisterEvent("LOOT_READY")
    f:SetScript("OnEvent", ns.Safe("logger", OnEvent))

    -- Clicking a bag item while Disenchant waits for a target.
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", ns.Safe("bag click", function(bag, slot)
            if SpellIsTargeting and SpellIsTargeting() then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.hyperlink then lastClicked = { link = info.hyperlink, at = GetTime() } end
            end
        end))
    end
end

---------------------------------------------------------------------------------------
-- Reports
---------------------------------------------------------------------------------------

-- Without vs with Salvager over everything logged: per material kind the share of
-- disenchants that gave it and the average amount. This is where its effect shows.
function L:StatsReport()
    local out = { "DisenchantInfo " .. ns.Version() .. ": what you have logged", "" }
    local totals = { base = { n = 0, kinds = {} }, salv = { n = 0, kinds = {} } }
    local keys = {}
    for key in pairs(ns.db.stats) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        for mode, t in pairs(totals) do
            local b = ns.db.stats[key][mode]
            if b then
                t.n = t.n + b.n
                for id, m in pairs(b.mats) do
                    local kind = ns.Data.kinds[id] or "other"
                    local k = t.kinds[kind] or { hits = 0, qty = 0 }
                    k.hits, k.qty = k.hits + m.hits, k.qty + m.qty
                    t.kinds[kind] = k
                end
            end
        end
    end
    out[#out + 1] = ("Disenchants logged: %d without Salvager, %d with it."):format(totals.base.n, totals.salv.n)
    out[#out + 1] = ""
    out[#out + 1] = "Material kind: share of disenchants / average amount  (without -> with Salvager)"
    for _, kind in ipairs({ "dust", "essence", "shard", "crystal", "other" }) do
        local function Part(t)
            local k = t.kinds[kind]
            if t.n == 0 or not k then return "-" end
            return ("%.1f%% / %.2f"):format(100 * k.hits / t.n, k.qty / k.hits)
        end
        out[#out + 1] = ("  %-8s %s  ->  %s"):format(kind, Part(totals.base), Part(totals.salv))
    end
    out[#out + 1] = ""
    out[#out + 1] = "Per kind of item (class:quality:item levels): without / with Salvager"
    for _, key in ipairs(keys) do
        out[#out + 1] = ("  %-22s %4d / %d"):format(key, self:Count(key, "base"), self:Count(key, "salv"))
    end
    return table.concat(out, "\n")
end

-- The player's buffs now, to spot a Salvager buff (/dei buffs).
function L:BuffReport()
    local out = { "Your buffs now (spell ID = name):" }
    for _, b in ipairs(PlayerBuffs()) do
        out[#out + 1] = ("  %s = %s"):format(tostring(b.id or "?"), tostring(b.name or "?"))
    end
    if #out == 1 then out[#out + 1] = "  (none)" end
    return table.concat(out, "\n")
end

function L:Reset()
    wipe(ns.db.stats)
    wipe(ns.db.log)
end
