# CritMatic Forever

Crit tracker for WoW Forever. It shows every crit on screen and in chat. Personal best records are off until the game API can hand an addon the hit number.

Inspired by [InfiniteLoopAlchemist](https://github.com/InfiniteLoopAlchemist)'s CritMatic addon. This project is a separate Forever client addon written from scratch for interface 16001. It is not affiliated with the original author or with Blizzard.

## What works on Forever

WoW Forever uses the same interface family as Midnight. Addons cannot register the combat log (`COMBAT_LOG_EVENT_UNFILTERED`). Registering that event is a protected action, so this addon never calls it. During a fight, `UNIT_COMBAT` reports the crit, but the amount stays a secret value and cannot be saved. Every crit is shown. Ticks and heal over time are shown only when they crit. Chat settings can share that line to party, guild, or raid.

`/cmf probe` prints what this client exposes (`UNIT_COMBAT`, Combat Log tab lines) for troubleshooting.

## Install

1. Copy the `CritMaticForever` folder into the Forever addon directory:

   `World of Warcraft\_forever_\Interface\AddOns\CritMaticForever`

2. `CritMaticForever.toc` must sit inside that folder. Close the game completely and start it again. New files do not load with `/reload`.
3. On the character list, enable **CritMatic Forever**.

## Use

| Command | What it does |
| --- | --- |
| `/cmf` or `/cm` | Open settings |
| `/cmlog` | Open the record window |
| `/cmchangelog` | Open the changelog |
| `/cmf ignore Spell Name` | Ignore a spell |
| `/cmf ignoretarget Name` | Ignore a target |
| `/cmf status` | Listener state and record counts |
| `/cmf demo` | Preview an alert |
| `/cmreset` | Delete this character's records |

Minimap button: left click opens records, right click opens settings, drag moves the button.

Right-click a row in the record window to share that record through say, yell, party, raid, guild, or whisper. The game only samples a share from a hardware event such as a click. There is no automatic emote.

Tooltips on the spellbook, the action bar, and chat links add that spell's records.

## Settings

The General tab turns damage, healing, crits, normal hits, and pets on or off separately. A minimum amount drops small hits. Alerts can show immediately or when the fight ends. Sound, text size, and colors are configurable. The chat line and the end-of-fight summary are separate.

## Development

Record rules live in `CritMaticForever/Logic.lua` and do not call the WoW API.

```bash
lua5.1 tests/logic_test.lua
lua5.1 tests/syntax.lua
```

For a CurseForge upload, select interface `16001`, game version `1.60.1`, and the Forever flavor. The package must contain the `CritMaticForever` folder. `.pkgmeta` packs that folder, keeps `tests` out of the release, and uses `CHANGELOG.md` as the manual changelog.
