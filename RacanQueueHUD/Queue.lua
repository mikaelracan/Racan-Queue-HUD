-- Racan Queue HUD 0.4.1. Retail 12.1.5, Lua 5.1-compatible source.
-- Read-only API boundary. Never hook/reparent Blizzard frames or automate a queue.
local _, Q = ...
Q.version = "0.4.1"
Q.issues = {}

function Q.Accessible(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then return false end
    return true
end

function Q.Number(value)
    if not Q.Accessible(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function Q.Text(value)
    if not Q.Accessible(value) or type(value) ~= "string" then return nil end
    if value == "" then return nil end
    return value
end

local function pack(...) return { n = select("#", ...), ... } end

-- Preserve nil slots in the legacy API's positional return values.
function Q.Call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then
        Q.issues[name] = "API unavailable"
        return nil
    end
    local result = pack(pcall(fn, ...))
    if not result[1] then
        Q.issues[name] = Q.Text(result[2]) or "API call failed"
        return nil
    end
    local count = result.n - 1
    for i = 1, count do result[i] = result[i + 1] end
    result[count + 1] = nil
    result.n = count
    return result
end

local ACTIVE = { queued = true, suspended = true, proposal = true, rolecheck = true, listed = true }
function Q.IsActive(mode) return ACTIVE[Q.Text(mode) or ""] == true end

local function modeFor(category, id)
    local result = Q.Call("GetLFGMode", category, id)
    return result and Q.Text(result[1]) or nil
end

local function integer(value)
    value = Q.Number(value)
    if value and value >= 0 and value == math.floor(value) then return value end
end

local function positiveID(value)
    value = integer(value)
    if value and value > 0 then return value end
end

local function readIDs(category)
    local result = Q.Call("GetLFGQueuedList", category, {})
    local list = result and result[1]
    local ids = {}
    if not Q.Accessible(list) or type(list) ~= "table" then return ids end
    -- A restricted container must not be inspected by this addon.
    if type(canaccesstable) == "function" and not canaccesstable(list) then return ids end
    local ok = pcall(function()
        for key, value in pairs(list) do
            local id = positiveID(key)
            if id and Q.Accessible(value) and value then ids[id] = true end
        end
    end)
    if not ok then Q.issues.GetLFGQueuedList = "Queue list cannot be read" end
    return ids
end

local function sortedIDs(ids)
    local result = {}
    for id in pairs(ids) do result[#result + 1] = id end
    table.sort(result)
    return result
end

local function getName(id)
    if not id then return nil end
    local result = Q.Call("GetLFGDungeonInfo", id)
    return result and Q.Text(result[1]) or nil
end

local function role(total, needed)
    total, needed = integer(total), integer(needed)
    if total and total > 100 then total = nil end
    if not total or not needed or needed > total then
        return { total = total }
    end
    return { total = total, needed = needed, found = total - needed }
end

function Q.MakeRecord(category, label, id, mode, stats, name)
    local record = {
        category = category, categoryName = label, id = id, mode = mode,
        name = name or getName(id) or label,
        tank = {}, healer = {}, dps = {},
    }
    if not stats or mode ~= "queued" then return record end
    -- Do not silently reuse the active wing's statistics for another wing.
    local returnedID = positiveID(stats[18])
    if id and returnedID and id ~= returnedID then
        Q.issues["queue:" .. category .. ":" .. id] = "API returned data for a different queue"
        return record
    end
    -- Same roles and wait field as Blizzard's QueueStatusEntry_SetUpLFG.
    record.tank = role(stats[6], stats[3])
    record.healer = role(stats[7], stats[4])
    record.dps = role(stats[8], stats[5])
    local t, h, d = record.tank.total, record.healer.total, record.dps.total
    if t and h and d and t + h + d == 0 then
        record.tank, record.healer, record.dps = {}, {}, {}
    end
    local wait, started = Q.Number(stats[16]), Q.Number(stats[17])
    if wait and wait > 0 then record.wait = wait end
    if started and started > 0 then record.started = started end
    return record
end

function Q.Collect()
    local records, specs = {}, {}
    local lfd, rf = positiveID(LE_LFG_CATEGORY_LFD), positiveID(LE_LFG_CATEGORY_RF)
    if lfd then specs[#specs + 1] = { id = lfd, label = "Dungeon Finder" } end
    if rf then specs[#specs + 1] = { id = rf, label = "LFR", perWing = true } end
    if #specs == 0 then Q.issues.categories = "LFD/LFR categories unavailable" end
    local proposal = Q.Call("GetLFGProposal")
    local roleCheck = Q.Call("GetLFGRoleUpdate")
    for _, spec in ipairs(specs) do
        local category = spec.id
        local catMode = modeFor(category)
        local ids, hints = readIDs(category), {}
        if proposal and Q.Accessible(proposal[1]) and proposal[1]
            and positiveID(proposal[14]) == category then
            local id = positiveID(proposal[2])
            if id then ids[id], hints[id] = true, "proposal" end
        end
        if roleCheck and Q.Accessible(roleCheck[1]) and roleCheck[1]
            and positiveID(roleCheck[4]) == category then
            local id = positiveID(roleCheck[5])
            if id then ids[id], hints[id] = true, "rolecheck" end
        end
        local ordered = sortedIDs(ids)
        if spec.perWing then
            local before = #records
            for _, id in ipairs(ordered) do
                local mode = modeFor(category, id) or hints[id] or catMode
                if Q.IsActive(mode) then
                    local stats = mode == "queued" and Q.Call("GetLFGQueueStats", category, id) or nil
                    records[#records + 1] = Q.MakeRecord(category, spec.label, id, mode, stats)
                end
            end
            -- A transition may expose only category-level state, with no wing IDs yet.
            if #records == before and Q.IsActive(catMode) then
                local stats = catMode == "queued" and Q.Call("GetLFGQueueStats", category) or nil
                local id = stats and positiveID(stats[18]) or nil
                records[#records + 1] = Q.MakeRecord(category, spec.label, id, catMode, stats)
            end
        else
            -- Multiple selected dungeons are ONE matchmaking queue, not separate queues.
            local stats = (Q.IsActive(catMode) or #ordered > 0)
                and Q.Call("GetLFGQueueStats", category) or nil
            local id = stats and positiveID(stats[18]) or ordered[1]
            local mode = (id and modeFor(category, id)) or (id and hints[id]) or catMode
            if Q.IsActive(mode) then
                local name = #ordered > 1 and "Multiple selected dungeons" or nil
                records[#records + 1] = Q.MakeRecord(category, spec.label, id, mode, stats, name)
            end
        end
    end
    return records
end

function Q.Time(seconds)
    seconds = Q.Number(seconds)
    if not seconds or seconds < 0 then return "?" end
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds / 60) % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, seconds % 60) end
    return string.format("%02d:%02d", minutes, seconds % 60)
end

local function count(value) return value ~= nil and tostring(value) or "?" end
function Q.RoleFraction(r) return count(r.found) .. "/" .. count(r.total) end

-- Color only the target Y while incomplete; leave X and the slash in the
-- original FontString color. When both counts are known and X == Y, color
-- X as well. Do not interpret secret, unavailable or zero-capacity counts
-- as evidence that a role is full.
function Q.ColoredRoleFraction(role, argb)
    role = role or {}
    local found, total = Q.Number(role.found), Q.Number(role.total)
    local isFull = found ~= nil and total ~= nil and total > 0 and found == total
    local left = count(found)
    if isFull then left = "|c" .. argb .. left .. "|r" end
    return left .. "/|c" .. argb .. count(total) .. "|r"
end

function Q.Lines(record, now)
    local title = record.categoryName
    if record.name ~= title then title = title .. " — " .. record.name end
    if record.mode ~= "queued" then
        local statuses = {
            proposal = "GROUP FOUND - accept via the game dialog.",
            rolecheck = "Waiting for role confirmation.",
            suspended = "Queue is suspended.",
            listed = "Queued; waiting for updated queue status.",
        }
        return { title, statuses[record.mode] or "Waiting for game data.", "", "" }
    end
    local elapsed
    if record.started and now and record.started <= now then elapsed = now - record.started end
    return {
        title,
        -- Diagnostic text only. The HUD renders these three counts under role icons.
        "Tank: " .. Q.RoleFraction(record.tank) .. "   |   Heal: " .. Q.RoleFraction(record.healer)
            .. "   |   DPS: " .. Q.RoleFraction(record.dps),
        "Average Wait Time: " .. Q.Time(record.wait),
        "Time in Queue: " .. Q.Time(elapsed),
    }
end
