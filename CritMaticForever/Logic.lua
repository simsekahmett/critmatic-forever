-- Pure record rules. No WoW API calls, so the same file runs under tests.
local _, ns = ...
ns = ns or {}

local Logic = {}
ns.Logic = Logic

local AUTO_ATTACK = 6603

function Logic.NewBucket()
	return {
		crit = 0,
		hit = 0,
		prevCrit = 0,
		prevHit = 0,
		critTarget = nil,
		hitTarget = nil,
		critTime = nil,
		hitTime = nil,
		critCount = 0,
		hitCount = 0,
		fight = 0,
		prevFight = 0,
		fightTime = nil,
	}
end

function Logic.RecordKey(spellID, isPet)
	return (isPet and "pet:" or "p:") .. tostring(spellID)
end

function Logic.NormalizeName(name)
	if type(name) ~= "string" then
		return nil
	end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

function Logic.IsIgnoredSpell(ignoredNames, ignoredIDs, spellID, spellName)
	if type(spellID) == "number" and type(ignoredIDs) == "table" and ignoredIDs[spellID] then
		return true
	end
	if type(spellName) == "string" and type(ignoredNames) == "table" then
		if ignoredNames[spellName:lower()] then
			return true
		end
	end
	return false
end

function Logic.IsIgnoredTarget(ignoredTargets, target)
	if type(target) ~= "string" or target == "" or type(ignoredTargets) ~= "table" then
		return false
	end
	return ignoredTargets[target:lower()] == true or ignoredTargets[target:lower()] ~= nil
end

function Logic.IsUsableNumber(value)
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return value > 0
end

function Logic.FormatNumber(amount)
	local n = math.floor((tonumber(amount) or 0) + 0.5)
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local digits = tostring(n)
	local grouped = (digits:reverse():gsub("(%d%d%d)", "%1,")):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return sign .. grouped
end

function Logic.HexColor(r, g, b)
	local function channel(value)
		local byte = math.floor((tonumber(value) or 1) * 255 + 0.5)
		if byte < 0 then
			byte = 0
		elseif byte > 255 then
			byte = 255
		end
		return string.format("%02x", byte)
	end
	return channel(r) .. channel(g) .. channel(b)
end

-- 32-bit AND. Uses the client bit library when the game provides one.
function Logic.Band(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then
		return 0
	end
	if bit and bit.band then
		return bit.band(a, b)
	end
	local result = 0
	local place = 1
	local left = a
	local right = b
	while left > 0 and right > 0 do
		if left % 2 >= 1 and right % 2 >= 1 then
			result = result + place
		end
		left = math.floor(left / 2)
		right = math.floor(right / 2)
		place = place * 2
	end
	return result
end

-- Combat log source flags. Values are the standard COMBATLOG_OBJECT_* masks.
local MINE = 0x00000001
local PLAYER = 0x00000400
local PET = 0x00001000
local GUARDIAN = 0x00002000

function Logic.ClassifySource(sourceGUID, sourceFlags, playerGUID, isSecret)
	if isSecret or type(sourceFlags) ~= "number" then
		return nil
	end
	if type(playerGUID) == "string" and sourceGUID == playerGUID then
		return "player"
	end
	if Logic.Band(sourceFlags, MINE) == 0 then
		return nil
	end
	if Logic.Band(sourceFlags, PET) ~= 0 or Logic.Band(sourceFlags, GUARDIAN) ~= 0 then
		return "pet"
	end
	if Logic.Band(sourceFlags, PLAYER) ~= 0 then
		return "player"
	end
	return nil
end

-- Suffix layouts match the combat log after the 11 shared arguments.
-- SWING_DAMAGE: amount, overkill, school, resisted, blocked, absorbed, critical, ...
-- SPELL/RANGE damage: spellId, spellName, spellSchool, amount, overkill, school,
--   resisted, blocked, absorbed, critical, ...
-- SPELL heal: spellId, spellName, spellSchool, amount, overhealing, absorbed, critical
function Logic.DescribeEvent(subevent, ...)
	if subevent == "SWING_DAMAGE" then
		return {
			kind = "damage",
			spellID = AUTO_ATTACK,
			spellName = nil,
			amount = select(1, ...),
			over = select(2, ...),
			critical = select(7, ...),
		}
	end
	if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
		or subevent == "RANGE_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE" then
		return {
			kind = "damage",
			spellID = select(1, ...),
			spellName = select(2, ...),
			amount = select(4, ...),
			over = select(5, ...),
			critical = select(10, ...),
		}
	end
	if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
		return {
			kind = "heal",
			spellID = select(1, ...),
			spellName = select(2, ...),
			amount = select(4, ...),
			over = select(5, ...),
			critical = select(7, ...),
		}
	end
	return nil
end

local function setting(settings, key, default)
	if type(settings) ~= "table" or settings[key] == nil then
		return default
	end
	return settings[key]
end

function Logic.ApplyHit(bucket, event, settings)
	if type(bucket) ~= "table" then
		bucket = Logic.NewBucket()
	end
	if type(event) ~= "table" then
		return bucket, nil
	end
	if event.kind == "damage" and setting(settings, "trackDamage", true) == false then
		return bucket, nil
	end
	if event.kind == "heal" and setting(settings, "trackHealing", true) == false then
		return bucket, nil
	end
	local isCrit = event.isCrit == true
	if isCrit and setting(settings, "trackCrit", true) == false then
		return bucket, nil
	end
	if not isCrit and setting(settings, "trackHit", true) == false then
		return bucket, nil
	end

	local amount = event.amount
	if event.kind == "heal" and setting(settings, "countOverheal", true) == false then
		local over = event.over
		if type(over) == "number" and over > 0 and type(amount) == "number" then
			amount = amount - over
		end
	end
	if not Logic.IsUsableNumber(amount) then
		return bucket, nil
	end
	local minimum = setting(settings, "minimumAmount", 0)
	if type(minimum) == "number" and amount < minimum then
		return bucket, nil
	end

	local field = isCrit and "crit" or "hit"
	local previous = bucket[field] or 0
	local countKey = field .. "Count"
	bucket[countKey] = (bucket[countKey] or 0) + 1
	if amount <= previous then
		return bucket, nil
	end

	if isCrit then
		bucket.prevCrit = previous
		bucket.critTarget = event.target
		bucket.critTime = event.now
	else
		bucket.prevHit = previous
		bucket.hitTarget = event.target
		bucket.hitTime = event.now
	end
	bucket[field] = amount
	return bucket, {
		field = field,
		kind = event.kind,
		amount = amount,
		previous = previous,
		silent = false,
	}
end

function Logic.ApplyFightTotal(bucket, total, now, kind)
	if type(bucket) ~= "table" then
		bucket = Logic.NewBucket()
	end
	if not Logic.IsUsableNumber(total) then
		return bucket, nil
	end
	local previous = bucket.fight or 0
	if total <= previous then
		return bucket, nil
	end
	bucket.prevFight = previous
	bucket.fight = total
	bucket.fightTime = now
	return bucket, {
		field = "fight",
		kind = kind or "damage",
		amount = total,
		previous = previous,
		-- The first seen total is stored quietly. Later fights announce a new best.
		silent = previous <= 0,
	}
end

function Logic.SortEntries(entries, key, descending)
	table.sort(entries, function(a, b)
		local av = a[key]
		local bv = b[key]
		if type(av) == "string" or type(bv) == "string" then
			av = tostring(av or "")
			bv = tostring(bv or "")
		else
			av = tonumber(av) or 0
			bv = tonumber(bv) or 0
		end
		if av == bv then
			local an = a.name or ""
			local bn = b.name or ""
			if an == bn then
				return false
			end
			return an < bn
		end
		if descending then
			return av > bv
		end
		return av < bv
	end)
	return entries
end

function Logic.AutoAttackID()
	return AUTO_ATTACK
end
