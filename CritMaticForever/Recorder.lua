local _, ns = ...

ns.Recorder = {
	hidden = 0,
	pending = {},
	fightFeed = {},
	session = {
		damage = {},
		healing = {},
		petDamage = {},
		petHealing = {},
		secret = false,
		updated = nil,
		available = false,
	},
}

local function BucketFor(record, kind)
	if kind == "heal" then
		return record.heal
	end
	return record.damage
end

function ns.Recorder.BuildPayload(record, outcome)
	local L = ns.L
	local name = record.name or ("#" .. tostring(record.spellID))
	if record.isPet then
		name = L.PET .. ": " .. name
	end

	local label, colorKey, soundKey
	if outcome.field == "fight" and outcome.kind == "heal" then
		label, colorKey, soundKey = L.NEW_FIGHT_HEAL, "heal", "soundHeal"
	elseif outcome.field == "fight" then
		label, colorKey, soundKey = L.NEW_FIGHT, "hit", "soundHit"
	elseif outcome.kind == "heal" and outcome.field == "crit" then
		label, colorKey, soundKey = L.NEW_HEAL_CRIT, record.isPet and "petCrit" or "critHeal", "soundHealCrit"
	elseif outcome.kind == "heal" then
		label, colorKey, soundKey = L.NEW_HEAL, "heal", "soundHeal"
	elseif outcome.field == "crit" then
		label, colorKey, soundKey = L.NEW_CRIT, record.isPet and "petCrit" or "crit", "soundCrit"
	else
		label, colorKey, soundKey = L.NEW_HIT, record.isPet and "petHit" or "hit", "soundHit"
	end

	local amount = ns.FormatNumber(outcome.amount)
	local previous
	local chat
	if outcome.previous and outcome.previous > 0 then
		previous = ns.FormatNumber(outcome.previous)
		chat = string.format(L.CHAT_RECORD_PREV, label, name, amount, previous)
	else
		chat = string.format(L.CHAT_RECORD, label, name, amount)
	end

	return {
		name = name,
		label = label,
		amount = amount,
		previous = previous,
		icon = record.icon,
		colorKey = colorKey,
		chat = chat,
		sound = ns.Database.Get(soundKey),
		spellID = record.spellID,
		isPet = record.isPet,
		field = outcome.field,
		kind = outcome.kind,
		rawAmount = outcome.amount,
		chatted = false,
	}
end

function ns.Recorder.Emit(payload)
	if not payload then
		return
	end
	local showAlert = ns.Database.Get("alert")
	if payload.field == "fight" then
		showAlert = showAlert and ns.Database.Get("alertFight")
	end
	if showAlert then
		ns.Alerts.Show(payload, false)
	end
	if ns.Database.Get("chat") then
		ns.Print(payload.chat)
		payload.chatted = true
	end
	ns.Recorder.fightFeed[#ns.Recorder.fightFeed + 1] = payload
	if ns.CritLog and ns.CritLog.Refresh and ns.CritLog.IsShown and ns.CritLog.IsShown() then
		ns.CritLog.Refresh()
	end
end

function ns.Recorder.Celebrate(record, outcome)
	if not outcome or outcome.silent then
		return
	end
	local payload = ns.Recorder.BuildPayload(record, outcome)
	local defer = ns.Database.Get("alertTiming") == "combatend" and ns.Recorder.inCombat
	if defer then
		ns.Recorder.pending[#ns.Recorder.pending + 1] = payload
		return
	end
	ns.Recorder.Emit(payload)
end

function ns.Recorder.PrintSummary()
	local feed = ns.Recorder.fightFeed or {}
	ns.Recorder.fightFeed = {}
	if not ns.Database.Get("chatSummary") then
		return
	end
	local fresh = {}
	for index = 1, #feed do
		local payload = feed[index]
		if payload and not payload.chatted then
			fresh[#fresh + 1] = payload
		end
	end
	if #fresh == 0 then
		return
	end
	table.sort(fresh, function(a, b)
		return (a.rawAmount or 0) > (b.rawAmount or 0)
	end)
	local limit = ns.Database.Get("summaryLimit") or 3
	ns.Print(ns.L.SUMMARY_HEADER)
	local shown = 0
	local seen = {}
	for index = 1, #fresh do
		local payload = fresh[index]
		local key = tostring(payload.spellID) .. ":" .. tostring(payload.field) .. ":" .. tostring(payload.kind)
		if not seen[key] then
			seen[key] = true
			ns.Print(payload.chat)
			shown = shown + 1
			if shown >= limit then
				break
			end
		end
	end
end

function ns.Recorder.FlushPending()
	local queued = ns.Recorder.pending or {}
	ns.Recorder.pending = {}
	for index = 1, #queued do
		ns.Recorder.Emit(queued[index])
	end
	ns.Recorder.PrintSummary()
end

local function ResolveSpell(described)
	local name, icon = ns.SpellInfo(described.spellID)
	name = name or ns.PlainString(described.spellName)
	if not name and described.spellID == ns.Logic.AutoAttackID() then
		name = ns.L.AUTO_ATTACK
	end
	if not name and type(described.spellID) == "number" then
		name = "#" .. tostring(described.spellID)
	end
	return name, icon
end

function ns.Recorder.HandleEvent(subevent, sourceGUID, sourceFlags, destName, ...)
	local described = ns.Logic.DescribeEvent(subevent, ...)
	if not described then
		return
	end
	if ns.ValueIsSecret(described.amount) or ns.ValueIsSecret(described.critical) or ns.ValueIsSecret(described.spellID) then
		ns.Recorder.hidden = ns.Recorder.hidden + 1
		if not ns.Recorder.toldSecret then
			ns.Recorder.toldSecret = true
			ns.Print(ns.L.SECRET_HITS)
		end
		return
	end
	if type(described.spellID) ~= "number" then
		return
	end
	described.critical = described.critical == true

	local playerGUID = UnitGUID and UnitGUID("player") or nil
	if ns.ValueIsSecret(playerGUID) then
		playerGUID = nil
	end
	-- A secret GUID must not be compared. Flags alone can still tell player from pet.
	if ns.ValueIsSecret(sourceFlags) or type(sourceFlags) ~= "number" then
		return
	end
	local safeGUID = sourceGUID
	if ns.ValueIsSecret(safeGUID) then
		safeGUID = nil
	end
	local who = ns.Logic.ClassifySource(safeGUID, sourceFlags, playerGUID, false)
	if who == "pet" then
		if not ns.Database.Get("trackPet") then
			return
		end
		if type(UnitIsPossessed) == "function" and UnitExists("pet") and UnitIsPossessed("pet") then
			return
		end
	end
	if who ~= "player" and who ~= "pet" then
		return
	end

	local spellName = described.spellName
	if ns.ValueIsSecret(spellName) then
		spellName = nil
		described.spellName = nil
	end
	local name, icon = ResolveSpell(described)
	if ns.Database.IsIgnoredSpell(described.spellID, name or spellName) then
		return
	end
	local target = ns.PlainString(destName)
	if target and ns.Database.IsIgnoredTarget(target) then
		return
	end

	local key = ns.Logic.RecordKey(described.spellID, who == "pet")
	local existing = ns.char.records[key]
	local scratch = existing and BucketFor(existing, described.kind) or ns.Logic.NewBucket()
	local _, outcome = ns.Logic.ApplyHit(scratch, {
		kind = described.kind,
		isCrit = described.critical,
		amount = described.amount,
		over = described.over,
		target = target,
		now = ns.Now(),
	}, ns.Database.Settings())
	local kept = (scratch.crit or 0) > 0 or (scratch.hit or 0) > 0 or (scratch.critCount or 0) > 0 or (scratch.hitCount or 0) > 0
	if not existing and not kept then
		return
	end
	local record = ns.Database.EnsureRecord(described.spellID, who == "pet", name, icon)
	if described.kind == "heal" then
		record.heal = scratch
	else
		record.damage = scratch
	end
	ns.Recorder.Celebrate(record, outcome)
end

function ns.Recorder.OnCombatLog()
	if type(CombatLogGetCurrentEventInfo) ~= "function" then
		return
	end
	ns.Guard("CombatLog", function()
		local _, subevent, _, sourceGUID, _, sourceFlags, _, _, destName, _, _, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 =
			CombatLogGetCurrentEventInfo()
		ns.Recorder.HandleEvent(subevent, sourceGUID, sourceFlags, destName, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
	end)
end

local function MeterType(kind)
	local enum = Enum and Enum.DamageMeterType
	if kind == "heal" then
		return enum and enum.HealingDone or 2
	end
	return enum and enum.DamageDone or 0
end

local function SessionCandidates()
	local enum = Enum and Enum.DamageMeterSessionType
	return {
		enum and enum.Current or 1,
		enum and enum.Expired or 2,
	}
end

local function ConsumeSource(into, source, isPet, kind)
	if source == nil then
		return true, 0
	end
	if ns.TableIsSecret(source) then
		return false, 0
	end
	local spells = source.combatSpells
	if spells == nil then
		return true, 0
	end
	if ns.TableIsSecret(spells) then
		return false, 0
	end
	local hidden = 0
	local readable = 0
	for index = 1, #spells do
		local spell = spells[index]
		if type(spell) == "table" and not ns.TableIsSecret(spell) then
			local spellID = spell.spellID
			local total = spell.totalAmount
			if ns.ValueIsSecret(spellID) or ns.ValueIsSecret(total) then
				hidden = hidden + 1
			elseif type(spellID) == "number" and type(total) == "number" and total > 0 then
				readable = readable + 1
				local name, icon = ns.SpellInfo(spellID)
				into[spellID] = {
					total = total,
					name = name,
					icon = icon,
					isPet = isPet and true or false,
				}
				if not ns.Database.IsIgnoredSpell(spellID, name) and ns.Database.Get("trackFight") then
					local record = ns.Database.EnsureRecord(spellID, isPet, name, icon)
					local _, outcome = ns.Logic.ApplyFightTotal(BucketFor(record, kind), total, ns.Now(), kind)
					ns.Recorder.Celebrate(record, outcome)
				end
			end
		end
	end
	if readable == 0 and hidden > 0 then
		return false, 0
	end
	return true, readable
end

-- Current is the live pull. Expired is the fight that just ended. Try both.
local function ReadSource(into, kind, isPet, guid)
	if type(guid) ~= "string" or ns.ValueIsSecret(guid) then
		return false
	end
	local meterType = MeterType(kind)
	local sawSecret = false
	for _, sessionType in ipairs(SessionCandidates()) do
		local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, guid)
		if ok then
			local readableBefore = 0
			for _ in pairs(into) do
				readableBefore = readableBefore + 1
			end
			local allowed, added = ConsumeSource(into, source, isPet, kind)
			if not allowed then
				sawSecret = true
			elseif added > 0 or readableBefore > 0 then
				return true
			end
		end
	end
	return not sawSecret
end

function ns.Recorder.ReadMeter()
	local session = ns.Recorder.session
	if not C_DamageMeter or type(C_DamageMeter.GetCombatSessionSourceFromType) ~= "function" then
		session.available = false
		return
	end
	session.available = true
	local playerGUID = UnitGUID("player")
	local damage = {}
	local healing = {}
	local damageOk = ReadSource(damage, "damage", false, playerGUID)
	local healOk = ReadSource(healing, "heal", false, playerGUID)
	if damageOk then
		session.damage = damage
	end
	if healOk then
		session.healing = healing
	end

	session.petDamage = {}
	session.petHealing = {}
	if ns.Database.Get("trackPet") and UnitExists("pet") then
		local possessed = type(UnitIsPossessed) == "function" and UnitIsPossessed("pet")
		local petGUID = UnitGUID("pet")
		if not possessed and petGUID and not ns.ValueIsSecret(petGUID) then
			local petDamage, petHealing = {}, {}
			if ReadSource(petDamage, "damage", true, petGUID) then
				session.petDamage = petDamage
			end
			if ReadSource(petHealing, "heal", true, petGUID) then
				session.petHealing = petHealing
			end
		end
	end

	session.secret = not damageOk or not healOk
	session.updated = ns.Now()
	if ns.CritLog and ns.CritLog.IsShown and ns.CritLog.IsShown() then
		ns.CritLog.Refresh()
	end
end

function ns.Recorder.ScheduleMeterRead()
	local tries = 0
	local function tick()
		tries = tries + 1
		local ok = ns.Guard("DamageMeter", ns.Recorder.ReadMeter)
		if (not ok or ns.Recorder.session.secret) and tries < 8 and C_Timer and C_Timer.After then
			C_Timer.After(0.4, tick)
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, tick)
	else
		ns.Guard("DamageMeter", ns.Recorder.ReadMeter)
	end
end

-- Registering COMBAT_LOG_EVENT_UNFILTERED is itself a protected action on Forever.
-- A working Forever addon (XToLevelF) refuses the name before RegisterEvent, because
-- pcall does not stop the ADDON_ACTION_FORBIDDEN notice.
function ns.Recorder.SetCombatLog(enabled)
	ns.Database.Set("attemptCombatLog", false)
	ns.Recorder.combatLogEnabled = false
	if enabled then
		ns.Recorder.combatLogError = "COMBAT_LOG_EVENT_UNFILTERED"
		ns.Print(string.format(ns.L.STATUS_CLEU_FAILED, "COMBAT_LOG_EVENT_UNFILTERED"))
	else
		ns.Recorder.combatLogError = nil
		ns.Print(ns.L.STATUS_CLEU_OFF)
	end
end

function ns.Recorder.Init()
	ns.Recorder.combatFrame = CreateFrame("Frame")
	ns.Recorder.combatFrame:SetScript("OnEvent", function()
		ns.Recorder.OnCombatLog()
	end)
	ns.Database.Set("attemptCombatLog", false)
	ns.Recorder.combatLogEnabled = false
	ns.Recorder.combatLogError = nil

	local meter = CreateFrame("Frame")
	ns.Recorder.meterFrame = meter
	meter:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			ns.Recorder.inCombat = true
			ns.Recorder.pending = {}
			ns.Recorder.fightFeed = {}
		elseif event == "PLAYER_REGEN_ENABLED" then
			ns.Recorder.inCombat = false
			ns.Recorder.FlushPending()
			ns.Recorder.ScheduleMeterRead()
		elseif not ns.Recorder.inCombat then
			ns.Recorder.ScheduleMeterRead()
		end
	end)
	meter:RegisterEvent("PLAYER_REGEN_DISABLED")
	meter:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(meter.RegisterEvent, meter, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
	pcall(meter.RegisterEvent, meter, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
end

function ns.Recorder.OnLogin()
	if not ns.char.welcomed then
		ns.Print(ns.L.WELCOME)
		ns.char.welcomed = true
	end
	if not InCombatLockdown or not InCombatLockdown() then
		ns.Recorder.ScheduleMeterRead()
	end
end
