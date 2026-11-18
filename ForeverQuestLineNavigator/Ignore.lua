-- Ignored quests and questlines, saved per character
-- (ForeverQuestLineNavigatorCharDB.ignored).
--
-- Ignoring a quest that is part of a questline ignores the whole line(s) it is
-- in. A quest without a line (a plain world quest) is ignored on its own.
-- Ignored things never show on the route, in the dungeon view or in the
-- "entering a dungeon" check. They come back from the "Ignored" section at the
-- bottom of the Route tab (right-click).

local _, ns = ...

local I = {}
ns.Ignore = I

local function Store()
    local c = ns.charDB
    return c and c.ignored or { lines = {}, quests = {} }
end

function I:Line(line)
    return Store().lines[line.id] ~= nil
end

-- True when the quest should be hidden: ignored itself, or every questline
-- it is part of is ignored.
function I:Hidden(questId)
    local s = Store()
    if s.quests[questId] then return true end
    local lines = ns.Planner.linesByQuest[questId]
    if not lines or #lines == 0 then return false end
    for _, line in ipairs(lines) do
        if not s.lines[line.id] then return false end
    end
    return true
end

-- Ignore a quest: its questlines if it has any, otherwise the quest itself.
function I:IgnoreQuest(questId, lines)
    local s, P = Store(), ns.Planner
    lines = lines and #lines > 0 and lines or P.linesByQuest[questId]
    if lines and #lines > 0 then
        for _, line in ipairs(lines) do s.lines[line.id] = P:LineName(line) end
    else
        s.quests[questId] = P:QuestName(questId)
    end
end

-- Ignore a route stop (all the questlines it belongs to).
function I:IgnoreStop(stop)
    local lines = {}
    for _, entry in ipairs(stop.lines or {}) do lines[#lines + 1] = entry.line end
    self:IgnoreQuest(stop.questId, lines)
end

function I:Restore(kind, id)
    local s = Store()
    if kind == "line" then s.lines[id] = nil else s.quests[id] = nil end
end

-- Brings a quest back: the quest itself and every ignored line it is part of.
function I:RestoreQuest(questId)
    local s = Store()
    s.quests[questId] = nil
    for _, line in ipairs(ns.Planner.linesByQuest[questId] or {}) do s.lines[line.id] = nil end
end

-- { { kind = "line"|"quest", id =, name = }, ... } sorted by name
function I:List()
    local s, out = Store(), {}
    for id, name in pairs(s.lines) do out[#out + 1] = { kind = "line", id = id, name = name } end
    for id, name in pairs(s.quests) do out[#out + 1] = { kind = "quest", id = id, name = name } end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

-- Asks first (Yes / No), then runs fn.
local POPUP = "FOREVERQUESTLINENAVIGATOR_CONFIRM"
function I:Confirm(text, fn)
    if not (StaticPopupDialogs and StaticPopup_Show) then fn(); return end
    StaticPopupDialogs[POPUP] = StaticPopupDialogs[POPUP] or {
        text = "%s",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(self, data)
            local run = data or self.data
            if type(run) == "function" then ns.Safe("ignore", run)() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(POPUP, text, nil, fn)
end

function I:AskIgnoreQuest(questId, lines)
    local P = ns.Planner
    lines = lines and #lines > 0 and lines or P.linesByQuest[questId]
    local what = (lines and #lines > 0) and ("the questline \"" .. P:LineName(lines[1]) .. "\"")
        or ("\"" .. P:QuestName(questId) .. "\"")
    self:Confirm(("Ignore %s on this character?\n\nYou can bring it back from \"Ignored\" at the bottom of the Route tab.")
        :format(what), function()
        I:IgnoreQuest(questId, lines)
        ns.Print("ignored " .. what .. ".")
        ns.RequestRefresh(0)
    end)
end

function I:AskIgnoreStop(stop)
    local lines = {}
    for _, entry in ipairs(stop.lines or {}) do lines[#lines + 1] = entry.line end
    self:AskIgnoreQuest(stop.questId, lines)
end

function I:AskRestore(entry)
    self:Confirm(("Bring back \"%s\"?"):format(tostring(entry.name)), function()
        I:Restore(entry.kind, entry.id)
        ns.Print(("\"%s\" is back."):format(tostring(entry.name)))
        ns.RequestRefresh(0)
    end)
end
