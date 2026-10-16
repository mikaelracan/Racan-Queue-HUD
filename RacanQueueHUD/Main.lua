local addonName, Q = ...
local driver = CreateFrame("Frame")
local initialized, scheduled, ticker, previewKind = false, false, nil, nil
local latest = {}
local VALID_POINTS = {
    TOP = true, TOPLEFT = true, TOPRIGHT = true, CENTER = true,
    LEFT = true, RIGHT = true, BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function message(text) print("|cffffcc33Racan Queue HUD:|r " .. text) end

local function normalizeDB()
    local db = type(RacanQueueHUDDB) == "table" and RacanQueueHUDDB or {}
    if type(db.enabled) ~= "boolean" then db.enabled = true end
    if type(db.locked) ~= "boolean" then db.locked = true end
    db.scale = Q.Number(db.scale) or 1
    if db.scale < 0.6 or db.scale > 2 then db.scale = 1 end
    db.point = VALID_POINTS[Q.Text(db.point) or ""] and db.point or "TOP"
    db.relativePoint = VALID_POINTS[Q.Text(db.relativePoint) or ""] and db.relativePoint or "TOP"
    db.x, db.y = Q.Number(db.x) or 0, Q.Number(db.y) or -180
    if math.abs(db.x) > 20000 or math.abs(db.y) > 20000 then db.x, db.y = 0, -180 end
    -- Migration from v0.2: remove the old background setting. There is no
    -- background texture at all in v0.3, including existing installations.
    db.background = nil
    if type(db.lfrTargets) ~= "table" then db.lfrTargets = {} end
    -- Existing 0.4.0 installations get the requested modern icons by default.
    -- Original Blizzard icons remain selectable via /rqh icons blizzard.
    if db.iconStyle ~= "modern" and db.iconStyle ~= "blizzard" then db.iconStyle = "modern" end
    db.schema = 4
    RacanQueueHUDDB, Q.db = db, db
end

local function sample(now)
    return {
        categoryName = "Queue HUD", name = "PREVIEW (not in queue)", mode = "queued",
        tank = { total = 1, found = 0, needed = 1 },
        healer = { total = 1, found = 0, needed = 1 },
        dps = { total = 3, found = 3, needed = 0 },
        started = now - 25, wait = 87,
    }
end

local function sampleRaid(lfr)
    return {
        kind = "raid", lfr = lfr, categoryName = lfr and "LFR" or "Raid",
        name = "PREVIEW (not in raid)",
        tank = { required = lfr and 2 or nil, present = 1, alive = 0 },
        healer = { required = lfr and 3 or nil, present = 3, alive = 2 },
        dps = { required = lfr and 20 or nil, present = 20, alive = 15 },
        unknownRoles = 0, unknownDeaths = 0, offline = 0,
    }
end

local refresh
refresh = function()
    scheduled = false
    if not initialized then return end
    latest = Q.Collect()
    Q.RememberLFRTargets(latest)
    local raid = Q.CollectRaid()
    local now = Q.Number(GetTime()) or 0
    local hasLiveData = raid ~= nil or #latest > 0
    if hasLiveData then previewKind = nil end -- Live data always overrides preview.
    local visibleRecords = raid and { raid } or latest
    -- With no live status, preview remains optional and independent of unlock.
    if not hasLiveData and previewKind then
        visibleRecords = { previewKind == "lfr" and sampleRaid(true)
            or previewKind == "manual" and sampleRaid(false) or sample(now) }
    end
    Q.Render(visibleRecords, now, previewKind ~= nil)
    -- Refresh once per second while queued OR inside a raid instance.
    if hasLiveData and Q.db.enabled then
        if not ticker then ticker = C_Timer.NewTicker(1, refresh) end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end
Q.Refresh = refresh

local function requestRefresh()
    if initialized and not scheduled then
        scheduled = true
        C_Timer.After(0.05, refresh)
    end
end

local function help()
    message("/rqh unlock | lock | test [queue|lfr|manual] | icons [modern|blizzard] | on | off | scale 1.2 | reset | debug")
end

local function diagnostics()
    local version, build, _, interface = GetBuildInfo()
    print("|cffff5555========== OUTPUT START ==========|r")
    print("ADDON=RacanQueueHUD VERSION=" .. Q.version)
    print("ICON_STYLE=" .. Q.db.iconStyle)
    print("CLIENT=" .. (Q.Text(version) or "?") .. " BUILD=" .. (Q.Text(build) or "?")
        .. " INTERFACE=" .. tostring(Q.Number(interface) or "?"))
    print("IN_GAME_VALIDATION=USER_TEST_REQUIRED")
    local records, now = Q.Collect(), GetTime()
    print("ACTIVE_QUEUE_BLOCKS=" .. #records)
    local raid = Q.CollectRaid()
    print("RAID_MODE=" .. (raid and (raid.lfr and "LFR" or "PREMADE") or "NONE"))
    if raid then
        print("RAID_INSTANCE=" .. raid.name .. " DUNGEON_ID=" .. tostring(raid.lfgDungeonID or "?"))
        print("RAID_ROSTER=" .. raid.members .. " UNASSIGNED=" .. raid.unknownRoles
            .. " OFFLINE=" .. raid.offline .. " UNKNOWN_ALIVE=" .. raid.unknownDeaths)
        for _, key in ipairs({ "tank", "healer", "dps" }) do
            local r = raid[key]
            print("RAID_ROLE=" .. key .. " REQUIRED=" .. tostring(r.required or "?")
                .. " PRESENT=" .. tostring(r.present) .. " ALIVE=" .. tostring(r.aliveUnknown and "?" or r.alive))
        end
    end
    for _, r in ipairs(records) do
        print("CATEGORY=" .. r.category .. " ID=" .. tostring(r.id or "?") .. " MODE=" .. r.mode)
        for _, line in ipairs(Q.Lines(r, now)) do if line ~= "" then print(line) end end
    end
    local keys = {}
    for key in pairs(Q.issues) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do print("API_NOTE[" .. key .. "]=" .. Q.issues[key]) end
    print("|cffff5555========== OUTPUT END ==========|r")
end

local function command(input)
    if not initialized then return end
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "unlock" then
        Q.db.enabled, Q.db.locked = true, false
        message("HUD unlocked. Drag to move it, then type /rqh lock.")
    elseif cmd == "lock" then
        Q.db.locked, previewKind = true, nil
        message("HUD locked. Mouse clicks pass through.")
    elseif cmd == "test" then
        local chosen = arg == "lfr" and "lfr" or arg == "manual" and "manual" or "queue"
        if Q.CollectRaid() or #Q.Collect() > 0 then
            message("Live queue/raid data active: preview is unavailable.")
            previewKind = nil
        else
            if previewKind == chosen then
                previewKind = nil
            else
                previewKind = chosen
            end
        end
        Q.db.enabled = true
    elseif cmd == "on" then Q.db.enabled = true
    elseif cmd == "off" then Q.db.enabled, previewKind = false, nil
    elseif cmd == "scale" then
        local value = Q.Number(tonumber(((arg or ""):gsub(",", "."))))
        if not value or value < 0.6 or value > 2 then
            message("Scale must be a number between 0.6 and 2.")
            return
        end
        Q.db.scale = value
    elseif cmd == "icons" then
        if arg ~= "modern" and arg ~= "blizzard" then
            message("Use /rqh icons modern or /rqh icons blizzard.")
            return
        end
        Q.db.iconStyle = arg
        message("Role icons: " .. arg .. ".")
    elseif cmd == "bg" then
        message("The HUD is always background-free.")
        return
    elseif cmd == "reset" then
        RacanQueueHUDDB = nil
        normalizeDB()
        previewKind = nil
        message("Default position and appearance restored.")
    elseif cmd == "debug" then diagnostics(); return
    else help(); return end
    Q.ApplyDisplay()
    refresh()
end

SLASH_RACANQUEUEHUD1 = "/rqh"
SlashCmdList.RACANQUEUEHUD = command

local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_ROLE_CHECK_UPDATE",
    "LFG_READY_CHECK_UPDATE", "LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_UPDATE",
    "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_FLAGS",
    "UNIT_CONNECTION", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "ROLE_CHANGED_INFORM", "PLAYER_SPECIALIZATION_CHANGED",
}
for _, event in ipairs(EVENTS) do driver:RegisterEvent(event) end

driver:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        normalizeDB()
        Q.CreateDisplay()
        initialized = true
        Q.ApplyDisplay()
        self:UnregisterEvent("ADDON_LOADED")
        message("v" .. Q.version .. " loaded. Use /rqh unlock to move the HUD; /rqh lock to finish.")
        requestRefresh()
    else requestRefresh() end
end)
