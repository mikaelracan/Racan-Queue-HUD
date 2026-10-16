# Racan Queue HUD 0.4.1 — Source audit (2026-10-16)

Target: WoW Retail Midnight 12.1.5, Interface 120105, build 70391.
`Gethe/wow-ui-source` is a community-hosted mirror of Blizzard's UI files,
not a guarantee of future Blizzard behavior. Source files are not redistributed.

## 0.3.1 queue behavior preserved

- UI version: https://github.com/Gethe/wow-ui-source/blob/live/version.txt
- QueueStatusFrame implementation:
  https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.lua
- QueueStatusFrame XML:
  https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.xml
- Queue role totals/needs: GetLFGQueueStats indices 6/7/8 (required), 3/4/5 (missing).
- Average Wait Time: myWait, 16th return; elapsed: GetTime - queuedTime (17th).
- Blizzard role atlases remain optional via GetIconForRole; modern transparent Lucide textures are the default. Colored totals use WoW FontString markup.

## Raid behavior inherited from 0.4.0 (unchanged in 0.4.1)

- `GetRaidRosterInfo(index)`: name at #1, online at #8, isDead at #9,
  assigned combatRole at #12; raid member indices can have gaps (iterate 1–40).
  https://warcraft.wiki.gg/wiki/API:GetRaidRosterInfo
- `UnitGroupRolesAssigned(unit)`: use for combat-role fallback if #12 is NONE;
  12.1 may yield secret values in restricted identity contexts.
  https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitRoleDocumentation.lua
  https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes/notes
- `UnitIsDeadOrGhost(unit)`: dead/ghost check; guard secret outcomes;
  roster isDead fallback when safe. Some class mechanics have special rules.
  https://warcraft.wiki.gg/wiki/API:UnitIsDeadOrGhost
- `GetInstanceInfo()` provides `instanceType` (#2), difficultyID (#3) and
  `lfgDungeonID` (#10). Only a player inside a raid instance and currently in
  a raid is shown the Raid HUD.
  https://warcraft.wiki.gg/wiki/API:GetInstanceInfo
- LFR difficultyIDs 7, 17, 151; `GetLFGMode(LE_LFG_CATEGORY_RF)` reports
  `lfgparty` while in an automated Raid Finder group; manual raids omit quotas.
  https://warcraft.wiki.gg/wiki/DifficultyID
  https://warcraft.wiki.gg/wiki/API:GetLFGMode
- Runtime event handling: GROUP_ROSTER_UPDATE, ROLE_CHANGED_INFORM,
  UNIT_CONNECTION, UNIT_FLAGS, PLAYER_ENTERING_WORLD and related events.
  No combat-log registration: this is intentionally read-only roster tracking.
- Restricted/secret value handling:
  https://warcraft.wiki.gg/wiki/Secret_Values
- Role quota caches: key by LFR wing ID, use client time to expire; no
  guessed default quotas. `GetLFGQueueStats` does not guarantee live
  post-entry role targets, hence the queue-time snapshot.

## Security / UX constraints

- Read-only addon: does not click Queue popups, change roles, inspect enemies,
  run automation, or modify Blizzard UI/secure frames.
- Fully transparent HUD. Blue drag outline only while `/rqh unlock` is active.
- No Blizzard Edit Mode integration; original `/rqh lock` / `unlock` preserved.
- Original queue view and user SavedVariables preserved across upgrade.
- Unassigned roles and inaccessible living status are displayed as caveats,
  never silently guessed.

## Validation

58 offline mocked Lua tests passed in Lua 5.3 (texlua); see Tests/TEST_RESULTS.txt.
The test harness is not a WoW client. No live boss/taint validation has run.

## Ikony Lucide pro verzi 0.4.1

Ikony `shield` (tank), `cross` (healer) a `swords` (DPS) odpovídají uzlům
`lucide-static@0.456.0/icon-nodes.json`; SVG jsou přímo v Media/Icons,
transparentní PNG 128×128 odvozené antialias rasterizací.

- https://app.unpkg.com/lucide-static@0.456.0/files/icon-nodes.json
- https://lucide.dev/icons/shield
- https://lucide.dev/icons/cross
- https://lucide.dev/icons/swords
- Licence: Media/Icons/LICENSE-LUCIDE.txt (ISC)
- WoW klient podporuje vlastní transparentní PNG s rozměry 2^N a explicitní
  příponou .png: https://warcraft.wiki.gg/wiki/API_TextureBase_SetTexture

Ikony nepoužívají žádné chráněné API, jen standardní Texture:SetTexture,
Texture:SetTexCoord a Texture:SetVertexColor.
