-- DisenchantInfo: the starting disenchant tables.
--
-- These are the standard Classic (1.12) disenchant results: item class (armor or
-- weapon), quality and item level decide the materials. The game client doesn't
-- contain the chances (the server rolls them), so these are NOT verified for WoW
-- Forever. They are only the starting point: once you have logged enough disenchants
-- of a kind (Settings: "logged disenchants needed"), your own numbers replace them.

local _, ns = ...
local D = {}
ns.Data = D

D.DISENCHANT_SPELL = 13262
D.ENCHANTING_SKILL_LINE = 333

local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local L_MAGIC, G_MAGIC = 10938, 10939
local L_ASTRAL, G_ASTRAL = 10998, 11082
local L_MYSTIC, G_MYSTIC = 11134, 11135
local L_NETHER, G_NETHER = 11174, 11175
local L_ETERNAL, G_ETERNAL = 16202, 16203
local S_GLIMMER, L_GLIMMER = 10978, 11084
local S_GLOW, L_GLOW = 11138, 11139
local S_RADIANT, L_RADIANT = 11177, 11178
local S_BRILLIANT, L_BRILLIANT = 14343, 14344
local NEXUS = 20725

-- Shown only until the game has loaded the item's (translated) name.
D.names = {
    [STRANGE] = "Strange Dust", [SOUL] = "Soul Dust", [VISION] = "Vision Dust",
    [DREAM] = "Dream Dust", [ILLUSION] = "Illusion Dust",
    [L_MAGIC] = "Lesser Magic Essence", [G_MAGIC] = "Greater Magic Essence",
    [L_ASTRAL] = "Lesser Astral Essence", [G_ASTRAL] = "Greater Astral Essence",
    [L_MYSTIC] = "Lesser Mystic Essence", [G_MYSTIC] = "Greater Mystic Essence",
    [L_NETHER] = "Lesser Nether Essence", [G_NETHER] = "Greater Nether Essence",
    [L_ETERNAL] = "Lesser Eternal Essence", [G_ETERNAL] = "Greater Eternal Essence",
    [S_GLIMMER] = "Small Glimmering Shard", [L_GLIMMER] = "Large Glimmering Shard",
    [S_GLOW] = "Small Glowing Shard", [L_GLOW] = "Large Glowing Shard",
    [S_RADIANT] = "Small Radiant Shard", [L_RADIANT] = "Large Radiant Shard",
    [S_BRILLIANT] = "Small Brilliant Shard", [L_BRILLIANT] = "Large Brilliant Shard",
    [NEXUS] = "Nexus Crystal",
}

-- Material kind, for the Salvager comparison in /dei stats.
D.kinds = {}
for _, id in ipairs({ STRANGE, SOUL, VISION, DREAM, ILLUSION }) do D.kinds[id] = "dust" end
for _, id in ipairs({ L_MAGIC, G_MAGIC, L_ASTRAL, G_ASTRAL, L_MYSTIC, G_MYSTIC,
                      L_NETHER, G_NETHER, L_ETERNAL, G_ETERNAL }) do D.kinds[id] = "essence" end
for _, id in ipairs({ S_GLIMMER, L_GLIMMER, S_GLOW, L_GLOW, S_RADIANT, L_RADIANT,
                      S_BRILLIANT, L_BRILLIANT }) do D.kinds[id] = "shard" end
D.kinds[NEXUS] = "crystal"

-- Each band: { lowest item level, highest item level, { material, chance %, min, max }, ... }
local ARMOR_UNCOMMON = {
    { 1, 15,  { STRANGE, 80, 1, 2 },  { L_MAGIC, 20, 1, 2 } },
    { 16, 20, { STRANGE, 75, 2, 3 },  { G_MAGIC, 20, 1, 2 },   { S_GLIMMER, 5, 1, 1 } },
    { 21, 25, { STRANGE, 75, 4, 6 },  { L_ASTRAL, 15, 1, 2 },  { S_GLIMMER, 10, 1, 1 } },
    { 26, 30, { SOUL, 75, 1, 2 },     { G_ASTRAL, 20, 1, 2 },  { L_GLIMMER, 5, 1, 1 } },
    { 31, 35, { SOUL, 75, 2, 5 },     { L_MYSTIC, 20, 1, 2 },  { S_GLOW, 5, 1, 1 } },
    { 36, 40, { VISION, 75, 1, 2 },   { G_MYSTIC, 20, 1, 2 },  { L_GLOW, 5, 1, 1 } },
    { 41, 45, { VISION, 75, 2, 5 },   { L_NETHER, 20, 1, 2 },  { S_RADIANT, 5, 1, 1 } },
    { 46, 50, { DREAM, 75, 1, 2 },    { G_NETHER, 20, 1, 2 },  { L_RADIANT, 5, 1, 1 } },
    { 51, 55, { DREAM, 75, 2, 5 },    { L_ETERNAL, 20, 1, 2 }, { S_BRILLIANT, 5, 1, 1 } },
    { 56, 60, { ILLUSION, 75, 1, 2 }, { G_ETERNAL, 20, 1, 2 }, { L_BRILLIANT, 5, 1, 1 } },
    { 61, 99, { ILLUSION, 75, 2, 5 }, { G_ETERNAL, 20, 2, 3 }, { L_BRILLIANT, 5, 1, 1 } },
}

-- Weapons give mostly essence.
local WEAPON_UNCOMMON = {
    { 1, 15,  { L_MAGIC, 80, 1, 2 },   { STRANGE, 20, 1, 2 } },
    { 16, 20, { G_MAGIC, 75, 1, 2 },   { STRANGE, 20, 2, 3 },  { S_GLIMMER, 5, 1, 1 } },
    { 21, 25, { L_ASTRAL, 75, 1, 2 },  { STRANGE, 15, 4, 6 },  { S_GLIMMER, 10, 1, 1 } },
    { 26, 30, { G_ASTRAL, 75, 1, 2 },  { SOUL, 20, 1, 2 },     { L_GLIMMER, 5, 1, 1 } },
    { 31, 35, { L_MYSTIC, 75, 1, 2 },  { SOUL, 20, 2, 5 },     { S_GLOW, 5, 1, 1 } },
    { 36, 40, { G_MYSTIC, 75, 1, 2 },  { VISION, 20, 1, 2 },   { L_GLOW, 5, 1, 1 } },
    { 41, 45, { L_NETHER, 75, 1, 2 },  { VISION, 20, 2, 5 },   { S_RADIANT, 5, 1, 1 } },
    { 46, 50, { G_NETHER, 75, 1, 2 },  { DREAM, 20, 1, 2 },    { L_RADIANT, 5, 1, 1 } },
    { 51, 55, { L_ETERNAL, 75, 1, 2 }, { DREAM, 22, 2, 5 },    { S_BRILLIANT, 3, 1, 1 } },
    { 56, 60, { G_ETERNAL, 75, 1, 2 }, { ILLUSION, 22, 1, 2 }, { L_BRILLIANT, 3, 1, 1 } },
    { 61, 99, { G_ETERNAL, 75, 2, 3 }, { ILLUSION, 22, 2, 5 }, { L_BRILLIANT, 3, 1, 1 } },
}

-- Rare (blue) items: the same for armor and weapons.
local RARE = {
    { 1, 25,  { S_GLIMMER, 100, 1, 1 } },
    { 26, 30, { L_GLIMMER, 100, 1, 1 } },
    { 31, 35, { S_GLOW, 100, 1, 1 } },
    { 36, 40, { L_GLOW, 100, 1, 1 } },
    { 41, 45, { S_RADIANT, 100, 1, 1 } },
    { 46, 50, { L_RADIANT, 100, 1, 1 } },
    { 51, 55, { S_BRILLIANT, 100, 1, 1 } },
    { 56, 60, { L_BRILLIANT, 99.5, 1, 1 }, { NEXUS, 0.5, 1, 1 } },
    { 61, 99, { L_BRILLIANT, 99.5, 1, 1 }, { NEXUS, 0.5, 1, 1 } },
}

local EPIC = {
    { 1, 45,  { S_RADIANT, 100, 2, 4 } },
    { 46, 50, { L_RADIANT, 100, 2, 4 } },
    { 51, 55, { S_BRILLIANT, 100, 2, 4 } },
    { 56, 60, { NEXUS, 100, 1, 1 } },
    { 61, 99, { NEXUS, 100, 1, 2 } },
}

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
D.CLASS_WEAPON, D.CLASS_ARMOR = CLASS_WEAPON, CLASS_ARMOR

local TABLES = {
    [CLASS_ARMOR]  = { [2] = ARMOR_UNCOMMON, [3] = RARE, [4] = EPIC },
    [CLASS_WEAPON] = { [2] = WEAPON_UNCOMMON, [3] = RARE, [4] = EPIC },
}

-- Equipment that can never be disenchanted.
local NEVER = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true, [""] = true }

-- What the game tells us about an item, or nil when it can't be disenchanted.
-- Returns { class, quality, level, band, key } where band is the table row (or nil
-- for a level the table doesn't cover) and key names the group the logger learns into.
function D.Describe(item)
    if not item then return nil end
    local name, _, quality, level, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(item)
    if not name then return nil, "loading" end
    if classID ~= CLASS_ARMOR and classID ~= CLASS_WEAPON then return nil end
    if type(quality) ~= "number" or quality < 2 or quality > 4 then return nil end
    if NEVER[equipLoc or ""] then return nil end
    level = tonumber(level) or 0
    local band
    for _, row in ipairs(TABLES[classID][quality]) do
        if level >= row[1] and level <= row[2] then band = row break end
    end
    -- Blue and purple items share one table for armor and weapons, so they learn together.
    local classKey = quality == 2 and (classID == CLASS_WEAPON and "weapon" or "armor") or "any"
    local range = band and (band[1] .. "-" .. band[2]) or ("L" .. level)
    local key = classKey .. ":" .. quality .. ":" .. range
    return { class = classID, quality = quality, level = level, band = band, key = key }
end

function D.Name(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if not name then
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
        return D.names[itemID] or ("item " .. itemID)
    end
    return name
end
