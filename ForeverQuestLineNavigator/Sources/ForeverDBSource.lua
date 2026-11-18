-- Data recorded on WoW Forever, from forever-db (optional addon "ForeverDB",
-- GPL-3.0, github.com/foreverfraddons/forever-db). It is read at runtime from its
-- global ForeverDB table; nothing of it is copied into this addon.
--
-- What we use:
--   qrw[questId]  = { money, full XP, ... }     -> quest XP at your level
--   quest[questId]= { title, level, minLevel }
--   qwk[questId]  = { seconds, runs }           -> how long players take (empty so far)
--   spm["c<npc>"] = { [uiMapId] = { x, y } }    -> recorded NPC spot, 0-1000
--
-- ForeverDB loads on demand and is large; Settings can turn it off.

local _, ns = ...

local F = { available = false }
ns.ForeverDBSource = F

local MIN_RUNS = 3 -- a recorded quest time counts once this many players did it

function F:Init()
    self.available = false
    if not ns.db.useForeverDB then return end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if type(_G.ForeverDB) ~= "table" and loader then pcall(loader, "ForeverDB") end
    local db = _G.ForeverDB
    if type(db) ~= "table" or type(db.meta) ~= "table" then return end
    self.db = db
    self.available = true
    self.build = db.meta.build
end

-- Quest XP at a player level, from the full XP: the usual reduction when the
-- quest is 6+ levels below you (80%, 60%, 40%, 20%, then 10%).
local REDUCTION = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

function F:QuestXP(questId, playerLevel)
    if not self.available then return nil end
    local reward = self.db.qrw and self.db.qrw[questId]
    local full = type(reward) == "table" and reward[2]
    if type(full) ~= "number" or full <= 0 then return nil end
    local quest = self.db.quest and self.db.quest[questId]
    local questLevel = type(quest) == "table" and quest[2]
    if type(questLevel) ~= "number" or questLevel <= 0 then return full end
    local diff = playerLevel - questLevel
    local factor = diff <= 5 and 1 or REDUCTION[diff] or 0.1
    return math.floor(full * factor / 5 + 0.5) * 5
end

-- Seconds players spend on a quest (pickup to turn-in, walking excluded), if recorded.
function F:QuestSeconds(questId)
    if not self.available then return nil end
    local row = self.db.qwk and self.db.qwk[questId]
    if type(row) == "table" and type(row[1]) == "number" and (row[2] or 0) >= MIN_RUNS then return row[1] end
end

-- Recorded spots of an NPC: { { uiMapId, x(0-1), y(0-1) }, ... }
function F:NpcSpots(npcId)
    if not self.available then return nil end
    local row = self.db.spm and self.db.spm["c" .. npcId]
    if type(row) ~= "table" then return nil end
    local out = {}
    for uiMapId, xy in pairs(row) do
        if type(uiMapId) == "number" and type(xy) == "table" and type(xy[1]) == "number" and type(xy[2]) == "number" then
            out[#out + 1] = { uiMapId, xy[1] / 1000, xy[2] / 1000 }
        end
    end
    return out
end
