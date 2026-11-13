local _, ns = ...

ns.Tooltips = {}

local function BucketHasNumbers(bucket)
	return type(bucket) == "table" and ((bucket.crit or 0) > 0 or (bucket.hit or 0) > 0)
end

local function RecordHasNumbers(record)
	return type(record) == "table" and (BucketHasNumbers(record.damage) or BucketHasNumbers(record.heal))
end

local function AddRecord(tooltip, record, prefix, critKey, hitKey, heal)
	if not RecordHasNumbers(record) then
		return false
	end
	local bucket = heal and record.heal or record.damage
	if not BucketHasNumbers(bucket) then
		return false
	end
	local wrote = false
	local function line(label, value, colorKey)
		if type(value) ~= "number" or value <= 0 then
			return
		end
		local r, g, b = ns.Database.Color(colorKey)
		tooltip:AddDoubleLine(prefix .. label, ns.FormatNumber(value), r, g, b, r, g, b)
		wrote = true
	end
	if heal then
		line(ns.L.BEST_HEAL_CRIT, bucket.crit, "critHeal")
		line(ns.L.BEST_HEAL, bucket.hit, "heal")
	else
		line(ns.L.BEST_CRIT, bucket.crit, critKey)
		line(ns.L.BEST_HIT, bucket.hit, hitKey)
	end
	return wrote
end

function ns.Tooltips.AddLines(tooltip, spellID)
	if not tooltip or not ns.Database.Get("tooltip") then
		return
	end
	if type(spellID) ~= "number" or not ns.char or not ns.char.records then
		return
	end
	local player = ns.char.records[ns.Logic.RecordKey(spellID, false)]
	local pet = ns.Database.Get("showPets") and ns.char.records[ns.Logic.RecordKey(spellID, true)] or nil
	local any = RecordHasNumbers(player) or RecordHasNumbers(pet)
	if not any then
		if ns.Database.Get("tooltipEmpty") then
			tooltip:AddLine(ns.L.NO_RECORD_YET, 0.6, 0.6, 0.6)
			tooltip:Show()
		end
		return
	end
	local tr, tg, tb = ns.Database.Color("title")
	tooltip:AddLine(ns.L.PERSONAL_BEST, tr, tg, tb)
	AddRecord(tooltip, player, "", "crit", "hit", false)
	AddRecord(tooltip, player, "", "critHeal", "heal", true)
	if pet then
		local petPrefix = ns.L.PET .. " "
		AddRecord(tooltip, pet, petPrefix, "petCrit", "petHit", false)
		AddRecord(tooltip, pet, petPrefix, "petCrit", "petHit", true)
	end
	tooltip:Show()
end

function ns.Tooltips.Init()
	if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
			local spellID = data and data.id
			if type(spellID) == "number" and not ns.ValueIsSecret(spellID) then
				ns.Tooltips.AddLines(tooltip, spellID)
			end
		end)
		return
	end
	if GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
			local spellID
			if tooltip.GetSpell then
				local _, id = tooltip:GetSpell()
				spellID = id
			end
			if type(spellID) == "number" then
				ns.Tooltips.AddLines(tooltip, spellID)
			end
		end)
	end
end
