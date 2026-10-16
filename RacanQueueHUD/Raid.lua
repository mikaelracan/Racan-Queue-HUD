-- Racan Queue HUD 0.4.0: read-only raid roster display.
-- LFR: required/present/alive. Premade raids: present/alive.
-- Never guess an LFR role quota or assign an unselected role to DPS.
local _, Q = ...
local ROLES = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local LFR_DIFFICULTY = { [7] = true, [17] = true, [151] = true }
local CACHE_SECONDS = 4 * 60 * 60

local function uint(value)
    value = Q.Number(value)
    if value and value >= 0 and value < 101 and value == math.floor(value) then return value end
end

local function identifier(value)
    value = Q.Number(value)
    if value and value > 0 and value <= 100000000 and value == math.floor(value) then
        return value
    end
end

local function raidClock()
    local result = Q.Call("time")
    return result and Q.Number(result[1]) or nil
end

local function validTargets(data)
    if type(data) ~= "table" or not Q.Accessible(data) then return nil end
    if type(canaccesstable) == "function" and not canaccesstable(data) then return nil end
    local result = {
        tank = uint(data.tank), healer = uint(data.healer), dps = uint(data.dps),
        storedAt = Q.Number(data.storedAt),
    }
    if not result.tank or not result.healer or not result.dps
        or result.tank + result.healer + result.dps == 0 then return nil end
    local now = raidClock()
    if not now or not result.storedAt or result.storedAt > now + 300
        or now - result.storedAt > CACHE_SECONDS then return nil end
    return result
end

-- Save the per-wing role requirements seen *while queuing*, because Blizzard
-- may stop returning GetLFGQueueStats after the player joins the LFR raid.
function Q.RememberLFRTargets(records)
    if not Q.db then return end
    local category = Q.Number(LE_LFG_CATEGORY_RF)
    local now = raidClock()
    if not category or not now then return end
    local cache = type(Q.db.lfrTargets) == "table" and Q.db.lfrTargets or {}
    Q.db.lfrTargets = cache
    for _, record in ipairs(records) do
        if record.category == category and record.mode == "queued" then
            local id = identifier(record.id)
            local t = uint(record.tank and record.tank.total)
            local h = uint(record.healer and record.healer.total)
            local d = uint(record.dps and record.dps.total)
            if id and id > 0 and t and h and d and t + h + d > 0 then
                cache[id] = { tank = t, healer = h, dps = d, storedAt = now }
            end
        end
    end
    -- Bounded, expiring state; never carry stale LFR quotas indefinitely.
    local keys = {}
    for id, entry in pairs(cache) do
        if not identifier(id) or not validTargets(entry) then
            cache[id] = nil
        else
            keys[#keys + 1] = id
        end
    end
    if #keys > 16 then
        table.sort(keys, function(a, b) return cache[a].storedAt > cache[b].storedAt end)
        for i = 17, #keys do cache[keys[i]] = nil end
    end
end

local function targetFor(lfgDungeonID)
    local cache = Q.db and Q.db.lfrTargets
    if type(cache) ~= "table" or not Q.Accessible(cache) then return nil end
    if type(canaccesstable) == "function" and not canaccesstable(cache) then return nil end
    local id = identifier(lfgDungeonID)
    -- If the game supplies a dungeon/wing ID, match it strictly; no swapping
    -- targets between two different selected LFR wings.
    if id and id > 0 then return validTargets(cache[id]) end
    -- Some clients omit lfgDungeonID on initial zone load. A SINGLE recent
    -- queue entry is unambiguous; more than one entry must remain unknown.
    local selected, count = nil, 0
    for _, value in pairs(cache) do
        local target = validTargets(value)
        if target then count, selected = count + 1, target end
        if count > 1 then return nil end
    end
    return selected
end

local function getRole(rosterInfo, unit)
    local selected = rosterInfo and Q.Text(rosterInfo[12])
    if selected and ROLES[selected] then return selected end
    local assigned = Q.Call("UnitGroupRolesAssigned", unit)
    local value = assigned and Q.Text(assigned[1])
    if value and ROLES[value] then return value end
    return nil
end

local function living(rosterInfo, unit)
    local connected = rosterInfo[8]
    if not Q.Accessible(connected) then return nil, "unknown" end
    if not connected or connected == 0 then return false, "offline" end
    local r = Q.Call("UnitIsDeadOrGhost", unit)
    if r and Q.Accessible(r[1]) and type(r[1]) == "boolean" then
        return not r[1], "online"
    end
    -- A secret death result must never be treated as nil/alive. An explicit
    -- roster death result is still usable if accessible; otherwise unknown.
    local secretUnitDeath = r and not Q.Accessible(r[1])
    local dead = rosterInfo[9]
    if Q.Accessible(dead) and (dead == true or dead == 1) then
        return false, "online"
    end
    if not secretUnitDeath and Q.Accessible(dead)
        and (dead == nil or dead == false) then
        return true, "online"
    end
    return nil, "unknown"
end

local function raidType()
    local group = Q.Call("IsInRaid")
    if not group or not Q.Accessible(group[1]) or not group[1] then return nil end
    local info = Q.Call("GetInstanceInfo")
    if not info or Q.Text(info[2]) ~= "raid" then return nil end
    local dungeon = identifier(info[10])
    local rfCategory = Q.Number(LE_LFG_CATEGORY_RF)
    local mode
    if rfCategory then
        local r = Q.Call("GetLFGMode", rfCategory, dungeon)
        mode = r and Q.Text(r[1])
        if not mode then
            r = Q.Call("GetLFGMode", rfCategory)
            mode = r and Q.Text(r[1])
        end
    end
    local difficultyID = uint(info[3])
    local lfr = LFR_DIFFICULTY[difficultyID] or mode == "lfgparty"
    return { lfr = lfr and true or false, name = Q.Text(info[1]) or "Raid instance",
        lfgDungeonID = dungeon, difficultyID = difficultyID }
end

-- Read roster, not combat logs. A member contributes to 'present' while
-- still in the raid roster, even if offline. Offline members do not contribute
-- to 'alive'. Unknown roles are tracked separately, never counted as DPS.
function Q.CollectRaid()
    local context = raidType()
    if not context then return nil end
    local record = {
        kind = "raid", lfr = context.lfr, categoryName = context.lfr and "LFR" or "Raid",
        name = context.name, lfgDungeonID = context.lfgDungeonID,
        tank = { present = 0, alive = 0 }, healer = { present = 0, alive = 0 },
        dps = { present = 0, alive = 0 },
        unknownRoles = 0, unknownDeaths = 0, offline = 0, members = 0,
    }
    if record.lfr then
        local target = targetFor(context.lfgDungeonID)
        if target then
            record.tank.required = target.tank
            record.healer.required = target.healer
            record.dps.required = target.dps
        end
    end

    -- A raid roster can have holes; do NOT stop at GetNumGroupMembers().
    for index = 1, 40 do
        local info = Q.Call("GetRaidRosterInfo", index)
        if info and Q.Text(info[1]) then
            record.members = record.members + 1
            local unit = "raid" .. index
            local role = getRole(info, unit)
            local alive, state = living(info, unit)
            if state == "offline" then record.offline = record.offline + 1 end
            if alive == nil then record.unknownDeaths = record.unknownDeaths + 1 end
            local slot = role and record[ROLES[role]]
            if slot then
                slot.present = slot.present + 1
                if alive then slot.alive = slot.alive + 1 end
                if alive == nil then slot.aliveUnknown = true end
            else
                record.unknownRoles = record.unknownRoles + 1
            end
        end
    end
    local expectedResult = Q.Call("GetNumGroupMembers")
    local expected = expectedResult and uint(expectedResult[1])
    if expected and expected > record.members then record.rosterPending = expected - record.members end
    return record
end

local function c(value) return value == nil and "?" or tostring(value) end
local function paint(value, color)
    return "|c" .. color .. c(value) .. "|r"
end
local DEATH_RED = "ffff6060"

-- Queue X/Y colors remain unchanged in Q.ColoredRoleFraction.
-- LFR raid: required (role color) / present (role color if full) /
--           alive (role color if all present alive; red if somebody died).
-- Premade raid: present (role color) / alive (same or red).
function Q.ColoredRaidFraction(role, argb, lfr)
    role = role or {}
    local present = uint(role.present)
    local required = uint(role.required)
    local alive = not role.aliveUnknown and uint(role.alive) or nil
    if lfr then
        local current = present ~= nil and required ~= nil and present == required
            and paint(present, argb) or c(present)
        local live = alive and present and alive == present and paint(alive, argb)
            or alive and paint(alive, DEATH_RED) or c(alive)
        return (required ~= nil and paint(required, argb) or "?") .. "/" .. current .. "/" .. live
    end
    local live = alive and present and alive == present and paint(alive, argb)
        or alive and paint(alive, DEATH_RED) or c(alive)
    return (present ~= nil and paint(present, argb) or "?") .. "/" .. live
end

function Q.RaidNotes(record)
    local result = {}
    if record.unknownRoles > 0 then
        result[#result + 1] = "Unassigned roles: " .. record.unknownRoles
    end
    if record.offline > 0 then
        result[#result + 1] = "Offline (not alive): " .. record.offline
    end
    if record.unknownDeaths > 0 then
        result[#result + 1] = "Unknown alive status: " .. record.unknownDeaths
    end
    if record.rosterPending and record.rosterPending > 0 then
        result[#result + 1] = "Roster loading: " .. record.rosterPending
    end
    return table.concat(result, "  |  ")
end
