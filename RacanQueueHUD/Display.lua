-- Presentation: modern Lucide role icons (optional Blizzard atlases), colored counts and English text.
-- No background and no top label; move outline only under /rqh unlock.
-- The addon deliberately does not register with the Blizzard Edit Mode.
local _, Q = ...
local panel, moveHint
local guides = {}
local blocks = {}
local WIDTH = 350
local CENTER_X = WIDTH / 2
local ROLE_ORDER = {
    { key = "tank", role = "TANK", x = CENTER_X - 72, color = "ff3fa9ff",
        texture = "Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\tank.png",
        rgb = { 63 / 255, 169 / 255, 1 }, fallback = "groupfinder-icon-role-large-tank" },
    { key = "healer", role = "HEALER", x = CENTER_X, color = "ff31e85f",
        texture = "Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\healer.png",
        rgb = { 49 / 255, 232 / 255, 95 / 255 }, fallback = "groupfinder-icon-role-large-heal" },
    { key = "dps", role = "DAMAGER", x = CENTER_X + 72, color = "ffffd43b",
        texture = "Interface\\AddOns\\RacanQueueHUD\\Media\\Icons\\dps.png",
        rgb = { 1, 212 / 255, 59 / 255 }, fallback = "groupfinder-icon-role-large-dps" },
}

local function makeGuide(pointA, relativePointA, xA, yA, pointB, relativePointB, xB, yB, width, height)
    local line = panel:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(0.20, 0.73, 1, 0.9)
    line:SetPoint(pointA, panel, relativePointA, xA, yA)
    line:SetPoint(pointB, panel, relativePointB, xB, yB)
    if width then line:SetWidth(width) end
    if height then line:SetHeight(height) end
    line:Hide()
    guides[#guides + 1] = line
end

function Q.CreateDisplay()
    panel = CreateFrame("Frame", "RacanQueueHUDFrame", UIParent)
    Q.panel = panel
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")

    -- Thin selection frame, visible ONLY when the HUD is movable.
    -- The normal queue HUD has no background, no top header and no outline.
    makeGuide("TOPLEFT", "TOPLEFT", -2, 2, "TOPRIGHT", "TOPRIGHT", 2, 2, nil, 2)
    makeGuide("BOTTOMLEFT", "BOTTOMLEFT", -2, -2, "BOTTOMRIGHT", "BOTTOMRIGHT", 2, -2, nil, 2)
    makeGuide("TOPLEFT", "TOPLEFT", -2, 2, "BOTTOMLEFT", "BOTTOMLEFT", -2, -2, 2, nil)
    makeGuide("TOPRIGHT", "TOPRIGHT", 2, 2, "BOTTOMRIGHT", "BOTTOMRIGHT", 2, -2, 2, nil)

    moveHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moveHint:SetPoint("BOTTOM", panel, "TOP", 0, 7)
    moveHint:SetText("Racan Queue HUD - drag to move")
    moveHint:Hide()

    panel:SetScript("OnDragStart", function(self)
        if Q.db and not Q.db.locked then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not Q.db then return end
        local point, _, relativePoint, x, y = self:GetPoint(1)
        -- Save to addon-specific SavedVariables; no Blizzard Edit Mode changes.
        if point and relativePoint and type(x) == "number" and type(y) == "number" then
            Q.db.point, Q.db.relativePoint = point, relativePoint
            Q.db.x, Q.db.y = x, y
        end
    end)
    panel:Hide()
end

function Q.ApplyDisplay()
    if not panel or not Q.db then return end
    panel:SetScale(Q.db.scale)
    panel:SetWidth(WIDTH)
    panel:ClearAllPoints()
    panel:SetPoint(Q.db.point, UIParent, Q.db.relativePoint, Q.db.x, Q.db.y)
    local canMove = not Q.db.locked
    panel:EnableMouse(canMove)
    -- Show the simple blue outline only while unlocked for dragging.
    panel:SetFrameStrata(canMove and "DIALOG" or "MEDIUM")
    for _, line in ipairs(guides) do line:SetShown(canMove) end
    moveHint:SetShown(canMove)
end

local function newText(size, color)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetWidth(WIDTH - 24)
    text:SetHeight(20)
    if color then text:SetTextColor(color[1], color[2], color[3]) end
    return text
end

local function blockAt(index)
    if blocks[index] then return blocks[index] end
    local block = {
        name = newText(15, { 1, 0.82, 0.24 }),
        status = newText(14),
        average = newText(14),
        elapsed = newText(14),
        note = newText(12, { 0.85, 0.70, 0.50 }),
        icons = {}, counts = {},
    }
    block.name:SetHeight(36)
    block.status:SetHeight(45)
    block.note:SetHeight(28)
    for i in ipairs(ROLE_ORDER) do
        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetSize(40, 40)
        block.icons[i] = icon
        local count = newText(15)
        count:SetWidth(94)
        count:SetHeight(20)
        count:SetJustifyH("CENTER")
        block.counts[i] = count
    end
    blocks[index] = block
    return block
end

local function hideBlock(block)
    block.name:Hide()
    block.status:Hide()
    block.average:Hide()
    block.elapsed:Hide()
    block.note:Hide()
    for i = 1, 3 do
        block.icons[i]:Hide()
        block.counts[i]:Hide()
    end
end

local function at(text, x, y, value)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    text:SetText(value)
    text:Show()
end

local function roleNeedsMore(role, record)
    -- Preserve the original 0.4.0 brightness rules in both icon styles.
    if record.kind == "raid" then
        if record.lfr and type(role.required) == "number" then
            return (role.present or 0) < role.required
        end
        return (role.present or 0) == 0
    end
    return role.needed ~= 0
end

local function roleAtlas(spec, needMore)
    if type(GetIconForRole) == "function" then
        local ok, atlas = pcall(GetIconForRole, spec.role, needMore)
        if ok and type(atlas) == "string" and atlas ~= "" then return atlas end
    end
    return spec.fallback
end

local function applyRoleIcon(icon, spec, role, record)
    local needMore = roleNeedsMore(role, record)
    if Q.db.iconStyle == "blizzard" then
        icon:SetAtlas(roleAtlas(spec, needMore), false)
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetAlpha(1)
    else
        -- 128x128 transparent RGBA; PNG extension is required by WoW.
        -- The authored shape is white and the Blizzard texture vertex color
        -- applies the role's approved blue, green or yellow tint.
        icon:SetTexture(spec.texture)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetVertexColor(spec.rgb[1], spec.rgb[2], spec.rgb[3], 1)
        icon:SetAlpha(needMore and 0.5 or 1)
    end
end

local function renderRoles(block, record, offset)
    for i, spec in ipairs(ROLE_ORDER) do
        local role = record[spec.key] or {}
        local icon = block.icons[i]
        icon:ClearAllPoints()
        local x = spec.x
        if record.kind == "raid" then x = x + (i - 2) * 12 end
        icon:SetPoint("TOP", panel, "TOPLEFT", x, -offset)
        applyRoleIcon(icon, spec, role, record)
        icon:Show()

        local count = block.counts[i]
        count:ClearAllPoints()
        count:SetPoint("TOP", panel, "TOPLEFT", x, -(offset + 42))
        if record.kind == "raid" then
            count:SetText(Q.ColoredRaidFraction(role, spec.color, record.lfr))
        else
            count:SetText(Q.ColoredRoleFraction(role, spec.color))
        end
        count:Show()
    end
end

function Q.Render(records, now, preview)
    if not Q.db.enabled then panel:Hide(); return end
    if #records == 0 and Q.db.locked and not preview then
        panel:Hide()
        return
    end
    for _, block in ipairs(blocks) do hideBlock(block) end

    -- Queue name is the topmost HUD text; there is no separate QUEUE heading.
    local offset = 8
    if #records == 0 then
        local block = blockAt(1)
        at(block.name, 12, offset, "No active Dungeon Finder or Raid Finder queue")
        offset = offset + 42
    else
        for index, record in ipairs(records) do
            local block = blockAt(index)
            if record.kind == "raid" then
                at(block.name, 12, offset, record.categoryName .. " — " .. record.name)
                offset = offset + 36
                renderRoles(block, record, offset)
                offset = offset + 67
                local note = Q.RaidNotes(record)
                if note ~= "" then
                    at(block.note, 12, offset, note)
                    offset = offset + 30
                end
            else
                local lines = Q.Lines(record, now)
                at(block.name, 12, offset, lines[1])
                offset = offset + 36
                if record.mode == "queued" then
                renderRoles(block, record, offset)
                offset = offset + 67
                at(block.average, 12, offset, lines[3])
                offset = offset + 22
                at(block.elapsed, 12, offset, lines[4])
                offset = offset + 22
            else
                at(block.status, 12, offset, lines[2])
                    offset = offset + 45
                end
            end
            offset = offset + 10
        end
    end
    panel:SetHeight(offset + 4)
    panel:Show()
end
