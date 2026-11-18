-- Travel time between two map points, from Shortest Path Forever (optional).
--
-- Shortest Path Forever (GPL-3.0, github.com/cjber/shortest-path-forever) plans
-- real journeys on Forever: walking, flight paths, boats, zeppelins, portals and
-- the hearthstone. We only call its documented public API
-- (ShortestPathForever.API.Estimate, API version 1 or 2); none of its code is in
-- this addon. Without it, the planner uses straight-line distance as before.
--
-- Each route update may ask only a limited number of new questions (the answers
-- are cached), so the game never stalls; the rest use the straight-line estimate
-- and the next update fills them in.

local _, ns = ...

local T = { cache = {}, asked = 0 }
ns.Travel = T

local MAX_NEW_PER_PASS = 25  -- new Estimate calls per route update
local KEEP_SECONDS = 600     -- how long an answer is kept
local GRID = 0.02            -- points this close (2% of a map) share an answer

function T:Api()
    local spf = _G.ShortestPathForever
    local api = type(spf) == "table" and spf.API
    if type(api) ~= "table" or type(api.Estimate) ~= "function" then return nil end
    local version = api.version
    if type(version) ~= "number" or version < 1 or version > 2 then return nil end -- the contract we know
    return api
end

function T:Available() return self:Api() ~= nil end

function T:NewPass()
    self.asked = 0
    self.missing, self.retry = false, false
end

local function Cell(v) return math.floor(v / GRID + 0.5) end

-- Seconds from (map, x, y) to (map, x, y), x / y 0-1. nil when not known (yet).
function T:Seconds(fromMap, fromX, fromY, toMap, toX, toY)
    local api = self:Api()
    if not api or not (fromMap and fromX and toMap and toX) then return nil end
    local key = fromMap .. ":" .. Cell(fromX) .. ":" .. Cell(fromY) .. ">" .. toMap .. ":" .. Cell(toX) .. ":" .. Cell(toY)
    local hit = self.cache[key]
    local now = GetTime()
    if hit and now - hit.time < KEEP_SECONDS then return hit.seconds or nil end
    if self.asked >= MAX_NEW_PER_PASS then
        self.missing = true -- ask again on the next update
        return nil
    end
    self.asked = self.asked + 1
    local ok, seconds, reason = pcall(api.Estimate, fromMap, fromX, fromY, toMap, toX, toY)
    if ok and type(seconds) == "number" then
        self.cache[key] = { time = now, seconds = seconds }
        return seconds
    end
    if ok and reason == "unreachable" then
        self.cache[key] = { time = now, seconds = false }
    elseif not ok then
        ns.LogError("travel estimate", seconds)
        self.cache[key] = { time = now, seconds = false }
    else
        self.retry = true -- "loading" / "combat": try again a bit later
    end
    return nil
end

function T:Clear() wipe(self.cache) end
