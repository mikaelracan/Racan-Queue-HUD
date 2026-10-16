# Racan Queue HUD

A lightweight World of Warcraft Retail addon for displaying Dungeon Finder, Raid Finder, and raid group status directly on screen.

**Version:** 0.4.1  
**Target:** World of Warcraft Retail – Midnight 12.1.5

## About the Project

Racan Queue HUD is a personal project created by a World of Warcraft player with the assistance of artificial intelligence (ChatGPT).

AI assistance was used for addon design, Lua programming, graphical elements, and preliminary automated testing.

The goal is to make existing in-game information easier to see without automating gameplay.

## Features

**Dungeon Finder and Raid Finder**

- Tank, Healer, and DPS role counters.
- Average estimated waiting time.
- Time spent in queue.
- Custom colored role icons.
- Automatic display when joining a supported queue.

**Raid Status**

- Automatic switching between queue and raid views.
- LFR: required / present / alive players per role.
- Manually assembled raids: present / alive players per role.
- Raid composition updates when members join, leave, die, or are resurrected.
- Unknown or unavailable information is not replaced with invented values.

**Customization**

- Transparent interface without a background panel.
- Movable display with saved position.
- Modern custom icons or original Blizzard role icons.
- Configurable interface scale.

## Installation

Download the addon ZIP, extract it, and place the `RacanQueueHUD` folder inside:

`World of Warcraft/_retail_/Interface/AddOns/`

Enable Racan Queue HUD in the game's addon list.

## Commands

| Command | Description |
|---|---|
| `/rqh unlock` | Unlock and move the display |
| `/rqh lock` | Lock the display position |
| `/rqh test lfr` | Preview the LFR raid display |
| `/rqh test manual` | Preview the manually assembled raid display |
| `/rqh icons modern` | Use modern custom role icons |
| `/rqh icons blizzard` | Use original Blizzard role icons |

## Development and Testing

The addon uses the standard World of Warcraft Lua addon environment.

Preliminary testing was performed using simulated WoW API functions. Full validation of the latest raid functionality inside the live game client, especially during encounters, remains necessary.

## Important Disclaimer

**Racan Queue HUD is an unofficial, AI-assisted project and has not been reviewed or approved by Blizzard Entertainment.**

The author is not a professional addon developer and does not claim that every implementation detail has been independently verified against Blizzard's current addon development policies.

The project is intended only to display information through permitted in-game UI mechanisms. It is not intended to automate combat, perform protected actions, or bypass Blizzard's API restrictions.

Clarification regarding the display of living raid members by role during encounters is being sought.

World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment.

## Source Code and Credits

The Lua source code is publicly available in the `RacanQueueHUD` directory.

For icon attribution and relevant licensing information, see `RacanQueueHUD/SOURCES.md` and `RacanQueueHUD/LICENSE.txt`.

Feedback and technical review are welcome.
