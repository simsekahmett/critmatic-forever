# CritMatic Forever

Personal-best tracker for WoW Forever. For each spell it remembers your highest crit, your highest normal hit, and your highest fight total, then shows a new record on screen, in chat, and on the spell tooltip.

Inspired by [InfiniteLoopAlchemist](https://github.com/InfiniteLoopAlchemist)'s CritMatic addon. This project is a separate Forever client addon written from scratch for interface 16001. It is not affiliated with the original author or with Blizzard.

## What works on Forever

WoW Forever uses the same interface family as Midnight. Addons cannot register the combat log (`COMBAT_LOG_EVENT_UNFILTERED`). Registering that event is a protected action, so this addon never calls it. During a fight, hit amounts reach addons only as secret values (`UNIT_COMBAT`), which can be shown but not compared, and the damage meter totals are secret too.

**Single hits and crits.** The client's own Combat Log chat tab still lists every hit, for example `Your Claw hit Saltstone Crystalhide 252 Physical. (Critical)`. The tab gets no new lines on its own during combat, but `C_CombatLog.RefilterEntries()` rebuilds it with the current fight's hits, even while it is not shown. On each hit (`UNIT_COMBAT` on your target, or a heal on you) the addon refills the tab at most once a second, reads the lines back as plain text, and keeps each spell's biggest normal hit and biggest crit (heals too). A new record is announced about a second after the hit. One more read runs when combat ends. This needs:

- a Combat Log chat tab (the default second tab; otherwise right-click a chat tab > New Window > Combat Log),
- the English client, because the lines are parsed in English,
- the tab's filter to include your own hits (the default does).

Pet hits are not read from the tab yet.

**Fight totals.** The built-in damage meter exposes per-spell totals after combat through `C_DamageMeter.GetCombatSessionSourceFromType`. The addon stores them as a **fight best** in the Fight tab: the damage or healing a spell did across the whole fight. That is not a single hit, so it is not announced unless *Alert when a fight total beats your previous best* is on.

`/cmf probe` prints what this client exposes (meter fields, `UNIT_COMBAT`, Combat Log tab lines) for troubleshooting.

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
