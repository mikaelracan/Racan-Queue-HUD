-- Offline mocks. These are NOT a WoW-client/secret-execution emulator.
local ROOT = arg[1] or "."
local Q, tests = {}, 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end
local function eq(a, b)
    assert(a == b, "Expected " .. tostring(b) .. "; received " .. tostring(a))
end
local function contains(text, fragment) assert(text:find(fragment, 1, true), text .. " lacks " .. fragment) end
local function load(name) assert(loadfile(ROOT .. "/" .. name))("RacanQueueHUD", Q) end
local function pack(...) return {n = select("#", ...), ...} end
local unpack = table.unpack or unpack
local state, stats, lists, names, calls
local secret = setmetatable({}, { __add = function() error("secret operation") end,
    __sub = function() error("secret operation") end,
    __tostring = function() error("secret stringify") end })
function issecretvalue(v) return rawequal(v, secret) end
function canaccessvalue(v) return not rawequal(v, secret) end
function canaccesstable(v) return not rawequal(v, secret) end
LE_LFG_CATEGORY_LFD, LE_LFG_CATEGORY_RF = 1, 3
local raidState = { active = false, difficulty = 17, lfgDungeonID = 201,
    name = "Mock Raid", roster = {} }
function time() return 1791993600 end
function IsInRaid() return raidState.active end
function GetInstanceInfo()
    if not raidState.active then return "Outside", "none", 0 end
    return raidState.name, "raid", raidState.difficulty, nil, nil, nil,
        nil, nil, nil, raidState.lfgDungeonID
end
function GetNumGroupMembers()
    local n = 0
    for _, member in pairs(raidState.roster) do if member then n = n + 1 end end
    return n
end
function GetRaidRosterInfo(index)
    local r = raidState.roster[index]
    if not r then return nil end
    return r.name, 0, 1, 80, "Warrior", "WARRIOR", "Mock Raid",
        r.online, r.dead and true or nil, nil, nil, r.role
end
function UnitGroupRolesAssigned(unit)
    local id = tonumber(unit:match("^raid(%d+)$"))
    return id and raidState.roster[id] and (raidState.roster[id].backup or raidState.roster[id].role)
        or "NONE"
end
function UnitIsDeadOrGhost(unit)
    local id = tonumber(unit:match("^raid(%d+)$"))
    local r = id and raidState.roster[id]
    return r and r.dead or false
end
local function member(name, role, dead, online)
    return { name = name, role = role, dead = dead or false,
        online = online == nil and true or online }
end
function GetTime() return 1000 end
function GetBuildInfo() return "12.1.5", "70391", "Oct 13 2026", 120105 end
function GetLFGMode(cat, id) return state[cat .. ":" .. (id or 0)] end
function GetLFGQueuedList(cat) return lists[cat] end
function GetLFGDungeonInfo(id) return names[id] end
function GetLFGQueueStats(cat, id)
    local key = cat .. ":" .. (id or 0)
    calls[key] = (calls[key] or 0) + 1
    local v = stats[key]
    if v then return unpack(v, 1, v.n) end
end
function GetLFGProposal() return false end
function GetLFGRoleUpdate() return false end
local function reset()
    state, stats, lists, names, calls = {}, {}, {}, {}, {}
    raidState.active, raidState.roster = false, {}
    function GetLFGProposal() return false end
    function GetLFGRoleUpdate() return false end
    Q.issues = {}
end
local function makeStats(id, tanks, heals, dps, totalT, totalH, totalD, wait, start)
    return pack(true, false, tanks, heals, dps, totalT, totalH, totalD,
        1, 1, "API Instance Name", 9999, 100, 200, 300, wait, start, id)
end
load("Queue.lua"); load("Raid.lua")

test("No active queue", function() reset(); eq(#Q.Collect(), 0) end)
test("Positional return holes preserved", function()
    function TestHoles() return nil, 3, nil, 6 end
    local r = Q.Call("TestHoles"); eq(r.n, 4); eq(r[2], 3); eq(r[4], 6)
end)
test("Screenshot LFD role counts / myWait / elapsed timestamp", function()
    reset(); state["1:0"], state["1:101"] = "queued", "queued"
    lists[1], names[101] = {[101] = true}, "Random Dungeon"
    stats["1:0"] = makeStats(101, 1, 1, 0, 1, 1, 3, 87, 975)
    local records = Q.Collect(); eq(#records, 1)
    local lines = Q.Lines(records[1], 1000)
    contains(lines[2], "Tank: 0/1"); contains(lines[2], "Heal: 0/1"); contains(lines[2], "DPS: 3/3")
    contains(lines[3], "Average Wait Time: 01:27")
    contains(lines[4], "Time in Queue: 00:25")
    assert(not table.concat(lines, " "):find("Chybí", 1, true))
end)
test("Two LFR wings use distinct requested statistics", function()
    reset(); state["3:0"], state["3:201"], state["3:202"] = "queued", "queued", "queued"
    lists[3], names[201], names[202] = {[202] = true, [201] = true}, "Wing A", "Wing B"
    stats["3:201"] = makeStats(201, 1, 2, 4, 2, 5, 18, 720, 538)
    stats["3:202"] = makeStats(202, 0, 1, 8, 2, 5, 18, 1500, 750)
    local r = Q.Collect(); eq(#r, 2); eq(r[1].id, 201); eq(r[2].id, 202)
    eq(r[1].tank.found, 1); eq(r[2].tank.found, 2)
    eq(r[1].wait, 720); eq(r[2].wait, 1500)
    contains(Q.Lines(r[1], 1000)[4], "07:42"); contains(Q.Lines(r[2], 1000)[4], "04:10")
    eq(calls["3:0"], nil)
end)
test("Multiple selected dungeons remain a single queue", function()
    reset(); state["1:0"], state["1:101"] = "queued", "queued"
    lists[1] = {[101] = true, [102] = true}
    stats["1:0"] = makeStats(101, 0, 1, 2, 1, 1, 3, 90, 900)
    local r = Q.Collect(); eq(#r, 1); eq(r[1].name, "Multiple selected dungeons")
end)
test("Unknown wait is not replaced by global average", function()
    local r = Q.MakeRecord(3, "LFR", 201, "queued", makeStats(201, 1, 2, 4, 2, 5, 18, -1, 950))
    eq(r.wait, nil); contains(Q.Lines(r, 1000)[3], "Average Wait Time: ?")
end)
test("Zero / nil / future queue time does not become huge elapsed", function()
    for _, start in ipairs({0, -1, 1100}) do
        local r = Q.MakeRecord(3, "LFR", 201, "queued", makeStats(201, 1, 2, 4, 2, 5, 18, 90, start))
        contains(Q.Lines(r, 1000)[4], "Time in Queue: ?")
    end
end)
test("Unavailable wing stats do not borrow another wing", function()
    local r = Q.MakeRecord(3, "LFR", 202, "queued", makeStats(201, 1, 2, 4, 2, 5, 18, 90, 950))
    eq(r.tank.found, nil); eq(r.started, nil); eq(r.wait, nil)
end)
test("Secret numeric fields render placeholders without arithmetic", function()
    local v = makeStats(201, secret, 2, 4, 2, 5, 18, secret, secret)
    local r = Q.MakeRecord(3, "LFR", 201, "queued", v)
    contains(Q.Lines(r, 1000)[2], "Tank: ?/2"); eq(r.wait, nil); eq(r.started, nil)
end)
test("Secret mode/list safe fallback", function()
    reset(); state["3:0"] = secret; lists[3] = secret
    eq(#Q.Collect(), 0)
end)
test("Invalid role values are not invented or clamped", function()
    local r = Q.MakeRecord(3, "LFR", 201, "queued", makeStats(201, 3, -1, 1.5, 2, 5, 18, 90, 900))
    eq(r.tank.found, nil); eq(r.healer.found, nil); eq(r.dps.found, nil)
end)
test("All-zero role placeholders remain unknown", function()
    local r = Q.MakeRecord(3, "LFR", 201, "queued", makeStats(201, 0, 0, 0, 0, 0, 0, 0, 0))
    contains(Q.Lines(r, 1000)[2], "Tank: ?/?")
end)
test("Proposal visible even when absent from queued list", function()
    reset()
    function GetLFGProposal() return true, 201, 1, 1, "Wing A", nil, nil, nil, nil, nil, nil, nil, nil, 3 end
    local r = Q.Collect(); eq(#r, 1); eq(r[1].mode, "proposal")
    contains(Q.Lines(r[1], 1000)[2], "GROUP FOUND")
end)
test("Role check category and ID included", function()
    reset()
    function GetLFGRoleUpdate() return true, 5, 1, 1, 101 end
    local r = Q.Collect(); eq(#r, 1); eq(r[1].mode, "rolecheck")
end)
test("Suspended queue does not show stale searching numbers", function()
    reset(); state["3:0"], state["3:201"] = "suspended", "suspended"; lists[3] = {[201] = true}
    local r = Q.Collect(); eq(#r, 1); contains(Q.Lines(r[1], 1000)[2], "suspended")
    eq(calls["3:201"], nil)
end)
test("Entered dungeon hides only that wing; other queue remains", function()
    reset(); state["3:0"], state["3:201"], state["3:202"] = "lfgparty", "lfgparty", "queued"
    lists[3] = {[201] = true, [202] = true}
    stats["3:202"] = makeStats(202, 1, 2, 3, 2, 5, 18, 300, 950)
    local r = Q.Collect(); eq(#r, 1); eq(r[1].id, 202)
end)
test("Category-only transition", function()
    reset(); state["3:0"] = "queued"; lists[3] = nil
    stats["3:0"] = makeStats(201, 1, 2, 3, 2, 5, 18, 300, 950)
    local r = Q.Collect(); eq(#r, 1); eq(r[1].id, 201)
end)
test("Missing API / raised error captured for diagnostics", function()
    eq(Q.Call("NoSuchAPI"), nil); assert(Q.issues.NoSuchAPI)
    function ErrorAPI() error("Synthetic error") end
    eq(Q.Call("ErrorAPI"), nil); contains(Q.issues.ErrorAPI, "Synthetic error")
end)
test("Duration formatting", function()
    eq(Q.Time(0), "00:00"); eq(Q.Time(59.99), "00:59"); eq(Q.Time(3661), "1:01:01")
    eq(Q.Time(0/0), "?"); eq(Q.Time(math.huge), "?"); eq(Q.Time(secret), "?")
end)
test("Incomplete tank count keeps X and slash default, colors Y blue", function()
    eq(Q.ColoredRoleFraction({found = 0, total = 1}, "ff3fa9ff"), "0/|cff3fa9ff1|r")
end)
test("Complete tank count colors X and Y blue", function()
    eq(Q.ColoredRoleFraction({found = 1, total = 1}, "ff3fa9ff"), "|cff3fa9ff1|r/|cff3fa9ff1|r")
end)
test("Incomplete healer green and complete healer green", function()
    eq(Q.ColoredRoleFraction({found = 3, total = 5}, "ff31e85f"), "3/|cff31e85f5|r")
    eq(Q.ColoredRoleFraction({found = 5, total = 5}, "ff31e85f"), "|cff31e85f5|r/|cff31e85f5|r")
end)
test("Incomplete DPS yellow and complete DPS yellow", function()
    eq(Q.ColoredRoleFraction({found = 2, total = 3}, "ffffd43b"), "2/|cffffd43b3|r")
    eq(Q.ColoredRoleFraction({found = 3, total = 3}, "ffffd43b"), "|cffffd43b3|r/|cffffd43b3|r")
end)
test("Unavailable or zero-capacity role not falsely shown as full", function()
    eq(Q.ColoredRoleFraction({found = secret, total = 1}, "ff3fa9ff"), "?/|cff3fa9ff1|r")
    eq(Q.ColoredRoleFraction({found = 1, total = secret}, "ff3fa9ff"), "1/|cff3fa9ff?|r")
    eq(Q.ColoredRoleFraction({found = 0, total = 0}, "ff3fa9ff"), "0/|cff3fa9ff0|r")
    eq(Q.ColoredRoleFraction({}, "ff3fa9ff"), "?/|cff3fa9ff?|r")
end)

-- Small UI mock to exercise the actual initialization, commands and event lifecycle.
local objects, delayed, tickers = {}, {}, {}
local methods = {}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:SetPoint(...) self.point = {...} end
function methods:GetPoint() return unpack(self.point or {"TOP", UIParent, "TOP", 0, -180}) end
function methods:ClearAllPoints() self.point = nil end
function methods:SetText(text) self.text = text end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(shown) self.shown = not not shown end
function methods:IsShown() return self.shown end
function methods:EnableMouse(v) self.mouse = v end
function methods:SetHeight(v) assert(type(v) == "number"); self.height = v end
function methods:SetWidth(v) self.width = v end
function methods:SetScale(v) self.scale = v end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetAtlas(atlas, useAtlasSize)
    self.atlas, self.atlasSize, self.texture = atlas, useAtlasSize, nil
end
function methods:SetTexture(texture) self.texture, self.atlas = texture, nil end
function methods:SetTexCoord(...) self.texCoord = {...} end
function methods:SetVertexColor(...) self.vertexColor = {...} end
function methods:SetAlpha(alpha) self.alpha = alpha end
local noopNames = {"SetFrameStrata", "SetClampedToScreen", "SetMovable", "RegisterForDrag", "SetAllPoints",
    "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFont", "SetTextColor", "StartMoving", "StopMovingOrSizing"}
for _, name in ipairs(noopNames) do methods[name] = function() end end
function methods:SetColorTexture(r, g, b, a) self.textureColor = {r,g,b,a} end
local function object(name)
    local o = setmetatable({scripts = {}, events = {}, shown = false}, {__index = methods})
    objects[#objects + 1] = o
    if name then _G[name] = o end
    return o
end
function methods:CreateFontString(name) return object(name) end
function methods:CreateTexture(name) return object(name) end
function CreateFrame(_, name) return object(name) end
UIParent, SlashCmdList = object("UIParent"), {}
C_Timer = {
    After = function(_, fn) delayed[#delayed + 1] = fn end,
    NewTicker = function(_, fn)
        local t = { callback = fn, cancelled = false }
        function t:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}
local function pump()
    local due = delayed; delayed = {}
    for _, fn in ipairs(due) do fn() end
end
function GetIconForRole(role, disabled)
    return "role-test-" .. role .. (disabled and "-muted" or "-active")
end
reset(); load("Display.lua"); load("Main.lua")
local driver
for _, o in ipairs(objects) do if o.events.ADDON_LOADED then driver = o end end
assert(driver)
test("SavedVariables initialize only on this addon event", function()
    driver.scripts.OnEvent(driver, "ADDON_LOADED", "OtherAddon"); eq(Q.db, nil)
    -- Mimic a player upgrading from version 0.2.0: keep their positioning,
    -- migrate away the saved translucent background configuration.
    RacanQueueHUDDB = {
        background = 0.35, point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
        x = -42, y = 55, scale = 1.3,
    }
    driver.scripts.OnEvent(driver, "ADDON_LOADED", "RacanQueueHUD"); pump()
    eq(Q.db.enabled, true); eq(Q.db.locked, true); eq(Q.panel:IsShown(), false)
    eq(Q.db.background, nil); eq(Q.db.schema, 4); eq(Q.db.iconStyle, "modern")
    eq(Q.db.point, "BOTTOMRIGHT"); eq(Q.db.x, -42); eq(Q.db.y, 55); eq(Q.db.scale, 1.3)
end)
test("Unlock / lock works without a queue", function()
    SlashCmdList.RACANQUEUEHUD("unlock"); eq(Q.panel:IsShown(), true); eq(Q.panel.mouse, true)
    SlashCmdList.RACANQUEUEHUD("lock"); eq(Q.panel:IsShown(), false); eq(Q.panel.mouse, false)
end)
test("Unlock shows only draggable outline, lock hides outline", function()
    reset()
    SlashCmdList.RACANQUEUEHUD("unlock")
    eq(Q.panel.mouse, true)
    local guidesShown, visibleInstruction = 0, false
    for _, o in ipairs(objects) do
        if o.textureColor and o.shown then guidesShown = guidesShown + 1 end
        if o.shown and o.text and o.text:find("drag to move", 1, true) then
            visibleInstruction = true
        end
    end
    eq(guidesShown, 4); eq(visibleInstruction, true)
    SlashCmdList.RACANQUEUEHUD("lock")
    eq(Q.panel.mouse, false)
    for _, o in ipairs(objects) do
        if o.textureColor then eq(o.shown, false) end
        if o.text and o.text:find("drag to move", 1, true) then eq(o.shown, false) end
    end
end)
test("No Blizzard Edit Mode callback registration or controls", function()
    eq(_G.EventRegistry, nil)
    eq(Q.editModeActive, nil)
    eq(SlashCmdList.RACANQUEUEHUD ~= nil, true)
end)
test("Scale decimal and comma; deprecated bg never creates a background", function()
    SlashCmdList.RACANQUEUEHUD("scale 1.2"); eq(Q.db.scale, 1.2)
    SlashCmdList.RACANQUEUEHUD("scale 1,4"); eq(Q.db.scale, 1.4)
    SlashCmdList.RACANQUEUEHUD("bg 1"); eq(Q.db.background, nil)
    SlashCmdList.RACANQUEUEHUD("scale xyz"); eq(Q.db.scale, 1.4)
    SlashCmdList.RACANQUEUEHUD("scale 99"); eq(Q.db.scale, 1.4)
end)
test("Modern role icons with counts; missing row absent", function()
    reset(); state["1:0"], state["1:101"] = "queued", "queued"
    lists[1] = {[101] = true}
    stats["1:0"] = makeStats(101, 1, 1, 0, 1, 1, 3, 87, 975)
    Q.Refresh()
    eq(Q.panel.width, 350)
    local icons, counts = {}, {}
    for _, o in ipairs(objects) do
        if o.texture and o.shown then icons[o.texture] = o end
        if o.text and o.shown then counts[o.text] = (counts[o.text] or 0) + 1 end
        if o.text then assert(not o.text:find("Chybí", 1, true)) end
        if o.shown and o.text then
            assert(o.text ~= "FRONTA" and o.text ~= "QUEUE" and o.text ~= "Queue")
            assert(not o.text:find("PŘESUN", 1, true))
        end
        -- Only the drag guides may have a solid-color texture and they must
        -- be hidden whenever the HUD is locked (no dark transparent backdrop).
        if o.textureColor then eq(o.shown, false) end
    end
    assert(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\tank.png"])
    assert(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\healer.png"])
    assert(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\dps.png"])
    eq(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\tank.png"].alpha, 0.5)
    eq(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\healer.png"].alpha, 0.5)
    eq(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\dps.png"].alpha, 1)
    assert(counts["0/|cff3fa9ff1|r"] == 1)
    assert(counts["0/|cff31e85f1|r"] == 1)
    assert(counts["|cffffd43b3|r/|cffffd43b3|r"] == 1)
    assert(counts["Average Wait Time: 01:27"])
    assert(counts["Time in Queue: 00:25"])
end)
test("Role icon brightness follows whether a role is filled", function()
    stats["1:0"] = makeStats(101, 0, 0, 1, 1, 1, 3, 87, 975)
    Q.Refresh()
    local icons, counts = {}, {}
    for _, o in ipairs(objects) do
        if o.texture and o.shown then icons[o.texture] = o end
        if o.text and o.shown then counts[o.text] = true end
    end
    eq(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\tank.png"].alpha, 1)
    eq(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\healer.png"].alpha, 1)
    eq(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\dps.png"].alpha, 0.5)
    assert(counts["|cff3fa9ff1|r/|cff3fa9ff1|r"])
    assert(counts["|cff31e85f1|r/|cff31e85f1|r"])
    assert(counts["2/|cffffd43b3|r"])
end)
test("Modern icon colors are exact role RGB and texture coordinates full", function()
    local seen = {}
    for _, o in ipairs(objects) do
        if o.texture and o.shown then
            seen[o.texture:match("([^\\]+)%.png$")] = o
        end
    end
    for _, role in ipairs({"tank", "healer", "dps"}) do
        assert(seen[role] and seen[role].vertexColor)
        eq(seen[role].texCoord[1], 0)
        eq(seen[role].texCoord[2], 1)
        eq(seen[role].texCoord[3], 0)
        eq(seen[role].texCoord[4], 1)
    end
    eq(seen.tank.vertexColor[1], 63 / 255)
    eq(seen.healer.vertexColor[2], 232 / 255)
    eq(seen.dps.vertexColor[3], 59 / 255)
end)
test("User can switch old Blizzard role icons without changing layout", function()
    local oldScale, oldPoint = Q.db.scale, Q.db.point
    SlashCmdList.RACANQUEUEHUD("icons blizzard")
    eq(Q.db.iconStyle, "blizzard")
    local atlases = {}
    for _, o in ipairs(objects) do
        if o.shown and o.atlas then
            atlases[o.atlas] = true
            eq(o.vertexColor[1], 1)
            eq(o.alpha, 1)
        end
    end
    assert(atlases["role-test-TANK-active"])
    assert(atlases["role-test-HEALER-active"])
    assert(atlases["role-test-DAMAGER-muted"])
    SlashCmdList.RACANQUEUEHUD("icons modern")
    eq(Q.db.iconStyle, "modern")
    local modernCount = 0
    for _, o in ipairs(objects) do
        if o.shown and o.texture then modernCount = modernCount + 1 end
    end
    eq(modernCount, 3)
    eq(Q.db.scale, oldScale); eq(Q.db.point, oldPoint)
end)
test("Invalid icon style does not corrupt saved preference", function()
    SlashCmdList.RACANQUEUEHUD("icons whatever")
    eq(Q.db.iconStyle, "modern")
end)
test("Unknown role count uses placeholder and muted icon", function()
    stats["1:0"] = makeStats(101, secret, 1, 0, 1, 1, 3, 87, 975)
    Q.Refresh()
    local icons, missing = {}, false
    for _, o in ipairs(objects) do
        if o.texture and o.shown then icons[o.texture] = o end
        if o.text == "?/|cff3fa9ff1|r" and o.shown then missing = true end
    end
    assert(icons["Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\tank.png"].alpha == 0.5 and missing)
end)
test("Proposal state hides role icons instead of stale counts", function()
    state["1:0"], state["1:101"] = "proposal", "proposal"
    Q.Refresh()
    for _, o in ipairs(objects) do if o.atlas or o.texture then eq(o.shown, false) end end
end)
test("Fallback atlases work if Blizzard role helper is unavailable", function()
    SlashCmdList.RACANQUEUEHUD("icons blizzard")
    local original = GetIconForRole
    GetIconForRole = nil
    reset(); state["1:0"], state["1:101"] = "queued", "queued"
    lists[1] = {[101] = true}
    stats["1:0"] = makeStats(101, 1, 1, 0, 1, 1, 3, 87, 975)
    Q.Refresh()
    local seen = {}
    for _, o in ipairs(objects) do if o.atlas and o.shown then seen[o.atlas] = true end end
    assert(seen["groupfinder-icon-role-large-tank"])
    assert(seen["groupfinder-icon-role-large-heal"])
    assert(seen["groupfinder-icon-role-large-dps"])
    GetIconForRole = original
    SlashCmdList.RACANQUEUEHUD("icons modern")
end)
test("Two active LFR wings render two icon rows and different times", function()
    reset(); state["3:0"], state["3:201"], state["3:202"] = "queued", "queued", "queued"
    lists[3] = {[201] = true, [202] = true}
    names[201], names[202] = "Wing One", "Wing Two"
    stats["3:201"] = makeStats(201, 1, 2, 4, 2, 5, 18, 720, 538)
    stats["3:202"] = makeStats(202, 0, 1, 8, 2, 5, 18, 1500, 750)
    Q.Refresh()
    local icons, averages = 0, {}
    for _, o in ipairs(objects) do
        if (o.texture or o.atlas) and o.shown then icons = icons + 1 end
        if o.shown and o.text then averages[o.text] = true end
    end
    eq(icons, 6)
    assert(averages["Average Wait Time: 12:00"])
    assert(averages["Average Wait Time: 25:00"])
    assert(Q.panel.height > 260)
end)
test("Preview explicitly labelled; real queue overrides it", function()
    reset()
    SlashCmdList.RACANQUEUEHUD("test"); eq(Q.panel:IsShown(), true)
    local found = false
    for _, o in ipairs(objects) do if o.text and o.text:find("PREVIEW (not in queue)", 1, true) then found = true end end
    assert(found)
    state["1:0"], state["1:101"] = "queued", "queued"; lists[1] = {[101] = true}
    stats["1:0"] = makeStats(101, 1, 1, 0, 1, 1, 3, 87, 975)
    driver.scripts.OnEvent(driver, "LFG_UPDATE"); pump()
    eq(Q.panel:IsShown(), true); assert(#tickers > 0)
    reset(); Q.Refresh(); eq(Q.panel:IsShown(), false); eq(tickers[#tickers].cancelled, true)
end)
test("Off/on does not change actual queue state", function()
    state["3:0"] = "queued"; stats["3:0"] = makeStats(201, 1, 2, 3, 2, 5, 18, 300, 950)
    Q.Refresh(); eq(Q.panel:IsShown(), true)
    SlashCmdList.RACANQUEUEHUD("off"); eq(Q.panel:IsShown(), false); eq(state["3:0"], "queued")
    SlashCmdList.RACANQUEUEHUD("on"); eq(Q.panel:IsShown(), true)
end)
test("Diagnostics runs; reset restores defaults", function()
    SlashCmdList.RACANQUEUEHUD("debug")
    SlashCmdList.RACANQUEUEHUD("reset"); eq(Q.db.scale, 1); eq(Q.db.background, nil)
    eq(Q.db.point, "TOP"); eq(Q.db.y, -180); eq(Q.db.iconStyle, "modern")
end)

-- 0.4.1: raid integration, quota safety and preserved legacy HUD behavior.
local function raidRosterScenario()
    raidState.roster = {
        [1] = member("MainTank", "TANK", true),
        [2] = member("Healer1", "HEALER", true),
        [3] = member("Healer2", "HEALER"),
        [4] = member("Healer3", "HEALER"),
    }
    for i = 1, 20 do
        raidState.roster[i + 4] = member("Dps" .. i, "DAMAGER", i <= 5)
    end
end
local function visibleTexts()
    local result = {}
    for _, o in ipairs(objects) do
        if o.shown and o.text and o.text ~= "" then result[#result + 1] = o.text end
    end
    return result
end
local function haveText(fragment)
    for _, value in ipairs(visibleTexts()) do
        if value:find(fragment, 1, true) then return true end
    end
    return false
end
local function activeCountColors()
    local r = {}
    for _, o in ipairs(objects) do
        if o.shown and (o.atlas or o.texture) then r[#r + 1] = o.atlas or o.texture end
    end
    return r
end

test("LFR requirements are remembered per wing, including after joining", function()
    reset(); Q.db.lfrTargets = {}
    state["3:0"], state["3:201"], state["3:202"] = "queued", "queued", "queued"
    lists[3] = {[201] = true, [202] = true}
    stats["3:201"] = makeStats(201, 1, 1, 1, 2, 3, 20, 240, 950)
    stats["3:202"] = makeStats(202, 1, 2, 1, 2, 5, 18, 240, 950)
    Q.RememberLFRTargets(Q.Collect())
    eq(Q.db.lfrTargets[201].tank, 2); eq(Q.db.lfrTargets[201].healer, 3)
    eq(Q.db.lfrTargets[202].healer, 5)
    reset(); raidState.active = true; raidState.difficulty = 17; raidState.lfgDungeonID = 201
    raidRosterScenario()
    local data = Q.CollectRaid()
    eq(data.lfr, true); eq(data.tank.required, 2); eq(data.healer.required, 3)
    eq(data.dps.required, 20); eq(data.tank.present, 1); eq(data.tank.alive, 0)
    eq(data.healer.present, 3); eq(data.healer.alive, 2)
    eq(data.dps.present, 20); eq(data.dps.alive, 15)
    eq(data.members, 24); eq(data.unknownRoles, 0)
    raidState.lfgDungeonID = 202
    data = Q.CollectRaid()
    eq(data.healer.required, 5); eq(data.dps.required, 18)
end)

test("Integration renders exact LFR triple with source quota and no times", function()
    raidState.lfgDungeonID = 201
    Q.db.enabled = true; Q.db.locked = true
    Q.Refresh()
    assert(haveText("LFR — Mock Raid"))
    assert(haveText("|cff3fa9ff2|r/1/|cffff60600|r"))
    assert(haveText("|cff31e85f3|r/|cff31e85f3|r/|cffff60602|r"))
    assert(haveText("|cffffd43b20|r/|cffffd43b20|r/|cffff606015|r"))
    assert(not haveText("Average Wait Time"))
    assert(not haveText("Time in Queue"))
    eq(#activeCountColors(), 3)
    for _, o in ipairs(objects) do if o.textureColor then eq(o.shown, false) end end
end)

test("LFR death and resurrection update only the living counter", function()
    raidState.roster[1].dead = false
    raidState.roster[2].dead = false
    Q.Refresh()
    local data = Q.CollectRaid()
    eq(data.tank.alive, 1); eq(data.healer.alive, 3)
    eq(data.tank.present, 1); eq(data.healer.present, 3)
    assert(haveText("|cff31e85f3|r/|cff31e85f3|r/|cff31e85f3|r"))
end)

test("LFR tank departure lowers present and living, not required", function()
    raidState.roster[1] = nil
    local data = Q.CollectRaid()
    eq(data.tank.required, 2); eq(data.tank.present, 0); eq(data.tank.alive, 0)
    Q.Refresh()
    assert(haveText("|cff3fa9ff2|r/0/|cff3fa9ff0|r"))
end)

test("Premade raid suppresses required field entirely", function()
    reset(); raidState.active = true; raidState.difficulty = 14
    raidState.lfgDungeonID = nil
    raidRosterScenario()
    local data = Q.CollectRaid()
    eq(data.lfr, false); eq(data.tank.required, nil)
    eq(data.tank.present, 1); eq(data.tank.alive, 0)
    eq(data.healer.present, 3); eq(data.healer.alive, 2)
    eq(data.dps.present, 20); eq(data.dps.alive, 15)
    Q.Refresh()
    assert(haveText("Raid — Mock Raid"))
    assert(haveText("|cff3fa9ff1|r/|cffff60600|r"))
    assert(haveText("|cff31e85f3|r/|cffff60602|r"))
    assert(haveText("|cffffd43b20|r/|cffff606015|r"))
    assert(not haveText("?/"))
    assert(not haveText("Average Wait Time"))
end)

test("Unknown premade roles shown separately, not counted as DPS", function()
    raidState.roster[25] = member("WithoutRole", "NONE", false)
    local data = Q.CollectRaid()
    eq(data.unknownRoles, 1); eq(data.dps.present, 20)
    contains(Q.RaidNotes(data), "Unassigned roles: 1")
    Q.Refresh(); assert(haveText("Unassigned roles: 1"))
end)

test("Role fallback and sparse raid slots work", function()
    reset(); raidState.active = true; raidState.difficulty = 16
    raidState.roster[1] = member("First", "NONE")
    raidState.roster[1].backup = "TANK"
    raidState.roster[40] = member("Last", "DAMAGER")
    local data = Q.CollectRaid()
    eq(data.members, 2); eq(data.tank.present, 1); eq(data.dps.present, 1)
    eq(data.unknownRoles, 0); eq(data.rosterPending, nil)
end)

test("Offline roster members remain present, not counted alive", function()
    raidState.roster[40].online = false
    local data = Q.CollectRaid()
    eq(data.dps.present, 1); eq(data.dps.alive, 0)
    eq(data.offline, 1)
    contains(Q.RaidNotes(data), "Offline (not alive): 1")
end)

test("Raid with unobserved LFR quota shows unknown, never invents 2/3/20", function()
    reset(); Q.db.lfrTargets = {}
    raidState.active = true; raidState.difficulty = 17; raidState.lfgDungeonID = 201
    raidState.roster[1] = member("Fresh", "HEALER")
    local data = Q.CollectRaid()
    eq(data.lfr, true); eq(data.healer.required, nil)
    local text = Q.ColoredRaidFraction(data.healer, "ff31e85f", true)
    contains(text, "?/1/")
end)

test("Two cached wings with missing ID must not leak another wing's quota", function()
    Q.db.lfrTargets = {
        [201] = {tank = 2, healer = 3, dps = 20, storedAt = time()},
        [202] = {tank = 2, healer = 5, dps = 18, storedAt = time()},
    }
    raidState.lfgDungeonID = nil
    local data = Q.CollectRaid()
    eq(data.healer.required, nil)
end)

test("Exactly one cached wing can be used only when raid wing ID is absent", function()
    Q.db.lfrTargets[202] = nil
    local data = Q.CollectRaid()
    eq(data.healer.required, 3)
    raidState.lfgDungeonID = 333
    data = Q.CollectRaid()
    eq(data.healer.required, nil)
end)

test("Expired cache is rejected and purged", function()
    Q.db.lfrTargets[201].storedAt = time() - 5*60*60
    raidState.lfgDungeonID = 201
    eq(Q.CollectRaid().healer.required, nil)
    Q.RememberLFRTargets({})
    eq(Q.db.lfrTargets[201], nil)
end)

test("Unknown living statuses show ? and do not pretend a death count", function()
    local originalDead = UnitIsDeadOrGhost
    UnitIsDeadOrGhost = function() return secret end
    local originalRoster = GetRaidRosterInfo
    GetRaidRosterInfo = function(index)
        if index == 1 then return "Friend", 0, 1, 80, "Mage", "MAGE", "Raid", true, secret,
            nil, nil, "DAMAGER" end
        return nil
    end
    reset(); raidState.active = true; raidState.difficulty = 14
    local data = Q.CollectRaid()
    eq(data.dps.present, 1); eq(data.dps.aliveUnknown, true)
    contains(Q.ColoredRaidFraction(data.dps, "ffffd43b", false), "/?")
    eq(data.unknownDeaths, 1)
    GetRaidRosterInfo = originalRoster
    UnitIsDeadOrGhost = originalDead
end)

test("Secret unit-death response cannot silently turn nil roster flag into alive", function()
    local originalDead = UnitIsDeadOrGhost
    UnitIsDeadOrGhost = function() return secret end
    reset(); raidState.active = true; raidState.difficulty = 14
    raidState.roster[1] = member("ProtectedMember", "TANK", false, true)
    local data = Q.CollectRaid()
    eq(data.tank.present, 1); eq(data.tank.aliveUnknown, true)
    eq(data.unknownDeaths, 1)
    UnitIsDeadOrGhost = originalDead
end)

test("Preview variants show raid LFR / manual without real group", function()
    reset(); Q.db.enabled = true; Q.db.locked = true
    SlashCmdList.RACANQUEUEHUD("test lfr")
    assert(haveText("LFR — PREVIEW (not in raid)"))
    assert(haveText("|cff3fa9ff2|r/1/|cffff60600|r"))
    SlashCmdList.RACANQUEUEHUD("test manual")
    assert(haveText("Raid — PREVIEW (not in raid)"))
    assert(haveText("|cff3fa9ff1|r/|cffff60600|r"))
    SlashCmdList.RACANQUEUEHUD("test manual")
    eq(Q.panel:IsShown(), false)
end)

test("Raid takes precedence over a simultaneous queue; switches back", function()
    reset(); Q.db.enabled = true; Q.db.locked = true
    state["1:0"], state["1:101"] = "queued", "queued"
    lists[1] = {[101] = true}
    stats["1:0"] = makeStats(101, 0, 1, 1, 1, 1, 3, 90, 900)
    raidState.active = true; raidState.difficulty = 14
    raidState.roster[1] = member("ManualTank", "TANK")
    Q.Refresh()
    assert(haveText("Raid — Mock Raid"))
    assert(not haveText("Time in Queue"))
    raidState.active = false
    Q.Refresh()
    assert(haveText("Average Wait Time"))
end)

test("One addon, original positioning, no Edit Mode, and intact queue fractions", function()
    reset(); raidState.active = false
    state["1:0"], state["1:101"] = "queued", "queued"
    lists[1] = {[101] = true}
    stats["1:0"] = makeStats(101, 1, 1, 0, 1, 1, 3, 87, 975)
    Q.Refresh()
    assert(haveText("0/|cff3fa9ff1|r"))
    assert(haveText("0/|cff31e85f1|r"))
    assert(haveText("|cffffd43b3|r/|cffffd43b3|r"))
    SlashCmdList.RACANQUEUEHUD("unlock"); eq(Q.panel.mouse, true)
    SlashCmdList.RACANQUEUEHUD("lock"); eq(Q.panel.mouse, false)
    eq(_G.EventRegistry, nil)
end)

print("\nOFFLINE_TESTS_PASSED=" .. tests)
print("LUA_RUNTIME=" .. _VERSION)
print("WOW_CLIENT_TESTS=NOT_RUN")
print("REAL_SECRET_VALUES_TESTS=NOT_RUN")
