local _, ns = ...

ns.Database = {}

local function Merge(dst, src)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then
				dst[key] = {}
			end
			Merge(dst[key], value)
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end

function ns.Database.DefaultSettings()
	return {
		trackDamage = true,
		trackHealing = true,
		trackCrit = true,
		trackHit = true,
		trackPet = true,
		trackFight = true,
		alertFight = true,
		countOverheal = true,
		minimumAmount = 0,
		tooltip = true,
		tooltipEmpty = false,
		minimap = true,
		showPets = true,
		alert = true,
		alertSize = 18,
		alertHold = 4,
		alertTiming = "instant",
		lockAlert = false,
		lockLog = false,
		sound = true,
		soundCrit = "raid",
		soundHit = "ready",
		soundHealCrit = "level",
		soundHeal = "quest",
		soundThrottle = 2,
		chat = true,
		chatSummary = true,
		summaryLimit = 3,
		attemptCombatLog = false,
		colors = {
			title = { 0.86, 0.68, 0.24 },
			spell = { 1, 0.84, 0.45 },
			crit = { 1, 0.42, 0.16 },
			hit = { 0.95, 0.95, 0.95 },
			critHeal = { 0.4, 1, 0.62 },
			heal = { 0.55, 0.9, 0.58 },
			petCrit = { 1, 0.55, 0.78 },
			petHit = { 0.82, 0.74, 0.98 },
		},
	}
end

function ns.Database.Init()
	if type(CritMaticForeverDB) ~= "table" then
		CritMaticForeverDB = {}
	end
	if type(CritMaticForeverCharDB) ~= "table" then
		CritMaticForeverCharDB = {}
	end
	ns.account = CritMaticForeverDB
	ns.char = CritMaticForeverCharDB

	Merge(ns.account, {
		settings = {},
		positions = {},
		sizes = {},
		ignoredSpells = {},
		ignoredSpellIDs = {},
		ignoredTargets = {},
		minimapAngle = 210,
	})
	Merge(ns.account.settings, ns.Database.DefaultSettings())
	if type(ns.char.records) ~= "table" then
		ns.char.records = {}
	end
	if ns.char.welcomed == nil then
		ns.char.welcomed = false
	end
end

function ns.Database.Get(key)
	return ns.account.settings[key]
end

function ns.Database.Set(key, value)
	ns.account.settings[key] = value
end

function ns.Database.Settings()
	return ns.account.settings
end

function ns.Database.Color(key)
	local color = ns.account.settings.colors[key] or { 1, 1, 1 }
	return color[1] or 1, color[2] or 1, color[3] or 1
end

function ns.Database.SetColor(key, r, g, b)
	ns.account.settings.colors[key] = { r, g, b }
end

function ns.Database.ApplyPoint(frame, key, fallback)
	local saved = ns.account.positions[key]
	frame:ClearAllPoints()
	if type(saved) == "table" and type(saved.point) == "string" then
		frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
	else
		frame:SetPoint(fallback[1], UIParent, fallback[2], fallback[3], fallback[4])
	end
end

function ns.Database.SavePoint(key, frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return
	end
	ns.account.positions[key] = {
		point = point,
		relativePoint = relativePoint or point,
		x = x or 0,
		y = y or 0,
	}
end

function ns.Database.ApplySize(frame, key, width, height)
	local saved = ns.account.sizes[key]
	if type(saved) == "table" and type(saved.w) == "number" and type(saved.h) == "number" then
		frame:SetSize(saved.w, saved.h)
	else
		frame:SetSize(width, height)
	end
end

function ns.Database.SaveSize(key, frame)
	ns.account.sizes[key] = { w = frame:GetWidth(), h = frame:GetHeight() }
end

function ns.Database.ResetPositions()
	ns.account.positions = {}
	ns.account.sizes = {}
	ns.account.minimapAngle = 210
end

function ns.Database.EnsureRecord(spellID, isPet, name, icon)
	local key = ns.Logic.RecordKey(spellID, isPet)
	local record = ns.char.records[key]
	if type(record) ~= "table" then
		record = {
			spellID = spellID,
			isPet = isPet and true or false,
			damage = ns.Logic.NewBucket(),
			heal = ns.Logic.NewBucket(),
		}
		ns.char.records[key] = record
	end
	if type(record.damage) ~= "table" then
		record.damage = ns.Logic.NewBucket()
	end
	if type(record.heal) ~= "table" then
		record.heal = ns.Logic.NewBucket()
	end
	record.spellID = spellID
	record.isPet = isPet and true or false
	if type(name) == "string" and name ~= "" then
		record.name = name
	end
	if type(icon) == "number" then
		record.icon = icon
	end
	return record
end

function ns.Database.ForgetRecord(spellID, isPet)
	ns.char.records[ns.Logic.RecordKey(spellID, isPet)] = nil
end

function ns.Database.ResetRecords()
	ns.char.records = {}
end

function ns.Database.IsIgnoredSpell(spellID, spellName)
	return ns.Logic.IsIgnoredSpell(ns.account.ignoredSpells, ns.account.ignoredSpellIDs, spellID, spellName)
end

function ns.Database.IsIgnoredTarget(target)
	return ns.Logic.IsIgnoredTarget(ns.account.ignoredTargets, target)
end

function ns.Database.IgnoreSpell(name, spellID)
	local clean = ns.Logic.NormalizeName(name)
	if clean then
		ns.account.ignoredSpells[clean:lower()] = clean
	end
	if type(spellID) == "number" then
		ns.account.ignoredSpellIDs[spellID] = clean or true
	end
	return clean
end

function ns.Database.ForgetSpell(name, spellID)
	local clean = ns.Logic.NormalizeName(name)
	if clean then
		local lower = clean:lower()
		ns.account.ignoredSpells[lower] = nil
		for id, label in pairs(ns.account.ignoredSpellIDs) do
			if type(label) == "string" and label:lower() == lower then
				ns.account.ignoredSpellIDs[id] = nil
			end
		end
	end
	if type(spellID) == "number" then
		ns.account.ignoredSpellIDs[spellID] = nil
	end
end

function ns.Database.IgnoreTarget(name)
	local clean = ns.Logic.NormalizeName(name)
	if not clean then
		return nil
	end
	ns.account.ignoredTargets[clean:lower()] = clean
	return clean
end

function ns.Database.ForgetTarget(name)
	local clean = ns.Logic.NormalizeName(name)
	if clean then
		ns.account.ignoredTargets[clean:lower()] = nil
	end
end

function ns.Database.WipeSpells()
	ns.account.ignoredSpells = {}
	ns.account.ignoredSpellIDs = {}
end

function ns.Database.WipeTargets()
	ns.account.ignoredTargets = {}
end

local function sortedValues(map)
	local list = {}
	for _, value in pairs(map) do
		if type(value) == "string" then
			list[#list + 1] = value
		end
	end
	table.sort(list)
	return list
end

function ns.Database.IgnoredSpellList()
	return sortedValues(ns.account.ignoredSpells)
end

function ns.Database.IgnoredTargetList()
	return sortedValues(ns.account.ignoredTargets)
end

function ns.Database.RecordCount()
	local count = 0
	for _, record in pairs(ns.char.records) do
		local function used(bucket)
			if type(bucket) ~= "table" then
				return false
			end
			return (bucket.crit or 0) > 0 or (bucket.hit or 0) > 0 or (bucket.fight or 0) > 0
		end
		if type(record) == "table" and (used(record.damage) or used(record.heal)) then
			count = count + 1
		end
	end
	return count
end
