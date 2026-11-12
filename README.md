# CritMatic Forever

Personal-best tracker for WoW Forever. For each spell it remembers your highest crit, your highest normal hit, and your highest fight total, then shows a new record on screen, in chat, and on the spell tooltip.

Inspired by [InfiniteLoopAlchemist](https://github.com/InfiniteLoopAlchemist)'s CritMatic addon. This project is a separate Forever client addon written from scratch for interface 16001. It is not affiliated with the original author or with Blizzard.

## What works on Forever

WoW Forever uses the same interface family as Midnight. Addons cannot register the combat log (`COMBAT_LOG_EVENT_UNFILTERED`). Registering that event is a protected action, so this addon never calls it. During a fight the size of a single hit, and whether it crit, stays hidden. Crit records stay empty for that reason.

When combat ends, the built-in damage meter exposes per-spell totals through `C_DamageMeter.GetCombatSessionSourceFromType`. The addon reads the current session and, if that is empty, the expired session. It stores those totals as a **fight best**: the damage or healing that spell did across the whole fight. It is not a single crit. The window says so. Overall session totals are not used, because those cover more than one fight.

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

The General tab turns damage, healing, crits, normal hits, pets, and fight totals on or off separately. A minimum amount drops small hits. Alerts can show immediately or when the fight ends. Sound, text size, and colors are configurable. The chat line and the end-of-fight summary are separate.

## Development

Record rules live in `CritMaticForever/Logic.lua` and do not call the WoW API.

```bash
lua5.1 tests/logic_test.lua
lua5.1 tests/syntax.lua
```

For a CurseForge upload, select interface `16001`, game version `1.60.1`, and the Forever flavor. The package must contain the `CritMaticForever` folder. `.pkgmeta` packs that folder, keeps `tests` out of the release, and uses `CHANGELOG.md` as the manual changelog.
