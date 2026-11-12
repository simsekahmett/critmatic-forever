local function loadLogic()
	local chunk, err = loadfile("CritMaticForever/Logic.lua")
	if not chunk then
		error(err)
	end
	local ns = {}
	chunk("CritMaticForever", ns)
	return ns.Logic
end

local Logic = loadLogic()
local failures = 0

local function eq(actual, expected, label)
	if actual ~= expected then
		failures = failures + 1
		io.stderr:write(string.format("FAIL %s\n  expected: %s\n  actual:   %s\n", label, tostring(expected), tostring(actual)))
	end
end

local function truthy(value, label)
	if not value then
		failures = failures + 1
		io.stderr:write("FAIL " .. label .. "\n")
	end
end

eq(Logic.FormatNumber(12), "12", "format small")
eq(Logic.FormatNumber(999), "999", "format hundreds")
eq(Logic.FormatNumber(1000), "1,000", "format thousand")
eq(Logic.FormatNumber(1234567), "1,234,567", "format million")
eq(Logic.FormatNumber(-2500), "-2,500", "format negative")

eq(Logic.NormalizeName("  Fireball  "), "Fireball", "trim name")
eq(Logic.NormalizeName("   "), nil, "blank name")
eq(Logic.RecordKey(133, false), "p:133", "player key")
eq(Logic.RecordKey(133, true), "pet:133", "pet key")

local names = { fireball = "Fireball" }
local ids = { [133] = true }
eq(Logic.IsIgnoredSpell(names, ids, 133, "Fireball"), true, "ignore id")
eq(Logic.IsIgnoredSpell(names, {}, nil, "FIREBALL"), true, "ignore name case")
eq(Logic.IsIgnoredSpell({}, {}, 116, "Frostbolt"), false, "not ignored")
eq(Logic.IsIgnoredTarget({ dummy = "Dummy" }, "Dummy"), true, "ignore target")
eq(Logic.IsIgnoredTarget({ dummy = "Dummy" }, "Boar"), false, "other target")

eq(Logic.Band(0x401, 0x400), 0x400, "band player type")
eq(Logic.Band(0x1001, 0x0001), 0x0001, "band mine")
eq(Logic.ClassifySource("Player-1", 0x401, "Player-1", false), "player", "player guid")
eq(Logic.ClassifySource("Pet-9", 0x1001, "Player-1", false), "pet", "pet flag")
eq(Logic.ClassifySource("Pet-9", 0x2001, "Player-1", false), "pet", "guardian flag")
eq(Logic.ClassifySource("Creature-1", 0x10, "Player-1", false), nil, "stranger")
eq(Logic.ClassifySource("Player-1", 0x401, "Player-1", true), nil, "secret source")
eq(Logic.ClassifySource("Other", 0x401, nil, false), "player", "mine player without guid")

local swing = Logic.DescribeEvent("SWING_DAMAGE", 120, -1, 1, 0, 0, 0, true, false, false, false)
eq(swing.spellID, 6603, "swing spell")
eq(swing.amount, 120, "swing amount")
eq(swing.critical, true, "swing crit")
eq(swing.kind, "damage", "swing kind")

local spell = Logic.DescribeEvent("SPELL_DAMAGE", 133, "Fireball", 4, 1523, 500, 4, 0, 0, 0, true, false, false, false)
eq(spell.spellID, 133, "spell id")
eq(spell.spellName, "Fireball", "spell name")
eq(spell.amount, 1523, "spell amount")
eq(spell.critical, true, "spell crit raw")

local heal = Logic.DescribeEvent("SPELL_HEAL", 2061, "Flash Heal", 2, 800, 100, 0, false)
eq(heal.kind, "heal", "heal kind")
eq(heal.amount, 800, "heal amount")
eq(heal.over, 100, "heal over")
eq(heal.critical, false, "heal not crit")
eq(Logic.DescribeEvent("SPELL_CAST_START", 133), nil, "ignore cast")

local bucket = Logic.NewBucket()
local _, first = Logic.ApplyHit(bucket, {
	kind = "damage", isCrit = true, amount = 1000, target = "Boar", now = 10,
}, {})
truthy(first, "first crit outcome")
eq(first.amount, 1000, "first amount")
eq(first.previous, 0, "first previous")
eq(bucket.crit, 1000, "stored crit")

local _, lower = Logic.ApplyHit(bucket, {
	kind = "damage", isCrit = true, amount = 900, target = "Boar", now = 11,
}, {})
eq(lower, nil, "lower crit ignored")
eq(bucket.crit, 1000, "crit unchanged")
eq(bucket.critCount, 2, "crit count")

local _, bigger = Logic.ApplyHit(bucket, {
	kind = "damage", isCrit = true, amount = 1400, target = "Wolf", now = 12,
}, {})
eq(bigger.previous, 1000, "previous crit")
eq(bucket.prevCrit, 1000, "stored previous")
eq(bucket.crit, 1400, "new crit")
eq(bucket.critTarget, "Wolf", "crit target")

local _, hit = Logic.ApplyHit(bucket, {
	kind = "damage", isCrit = false, amount = 700, target = "Wolf", now = 13,
}, {})
eq(hit.field, "hit", "normal hit field")
eq(bucket.hit, 700, "stored hit")
eq(bucket.crit, 1400, "hit does not replace crit")

local _, tied = Logic.ApplyHit(bucket, {
	kind = "damage", isCrit = false, amount = 700, now = 14,
}, {})
eq(tied, nil, "equal hit is not a record")

local _, blocked = Logic.ApplyHit(bucket, {
	kind = "damage", isCrit = true, amount = 5000, now = 15,
}, { trackCrit = false })
eq(blocked, nil, "crit tracking off")
eq(bucket.crit, 1400, "crit stays when tracking off")

local healBucket = Logic.NewBucket()
local _, rawHeal = Logic.ApplyHit(healBucket, {
	kind = "heal", isCrit = true, amount = 1000, over = 400, now = 1,
}, { countOverheal = false })
eq(rawHeal.amount, 600, "effective heal")
eq(healBucket.crit, 600, "stored effective heal")

local _, tiny = Logic.ApplyHit(Logic.NewBucket(), {
	kind = "damage", isCrit = true, amount = 40, now = 1,
}, { minimumAmount = 100 })
eq(tiny, nil, "below minimum")

local fightBucket = Logic.NewBucket()
local _, firstFight = Logic.ApplyFightTotal(fightBucket, 8000, 20, "damage")
truthy(firstFight.silent, "first fight total is quiet")
eq(fightBucket.fight, 8000, "first fight stored")
local _, secondFight = Logic.ApplyFightTotal(fightBucket, 7999, 30, "damage")
eq(secondFight, nil, "smaller fight ignored")
local _, thirdFight = Logic.ApplyFightTotal(fightBucket, 9000, 40, "damage")
eq(thirdFight.silent, false, "beating a fight total announces")
eq(thirdFight.previous, 8000, "fight previous")
eq(fightBucket.fight, 9000, "fight best")

local entries = {
	{ name = "Frostbolt", left = 10, right = 5 },
	{ name = "Fireball", left = 50, right = 1 },
	{ name = "Blizzard", left = 50, right = 9 },
}
Logic.SortEntries(entries, "left", true)
eq(entries[1].name, "Blizzard", "tie breaks by name")
eq(entries[3].name, "Frostbolt", "lowest last")

if failures > 0 then
	io.stderr:write(string.format("%d failure(s)\n", failures))
	os.exit(1)
end
print("logic tests passed")
