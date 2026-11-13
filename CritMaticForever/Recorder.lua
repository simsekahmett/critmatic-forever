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
	-- Fight totals are kept and shown in the Fight tab; they are announced only on request.
	if outcome.field == "fight" and not ns.Database.Get("alertFight") then
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
end

local fightSerial = 0

-- Unique across reloads, because the id is saved on the bucket that holds the best.
function ns.Recorder.NewFightID(prefix)
	fightSerial = fightSerial + 1
	ns.Recorder.fightID = (prefix or "fight") .. ":" .. tostring(ns.Now()) .. ":" .. tostring(fightSerial)
	return ns.Recorder.fightID
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
	ns.Recorder.RecordHit({
		spellID = described.spellID,
		isPet = who == "pet",
		kind = described.kind,
		isCrit = described.critical,
		amount = described.amount,
		over = described.over,
		target = ns.PlainString(destName),
		name = name or spellName,
		icon = icon,
	})
end

-- One hit from any source: the combat log event, or a Combat Log tab line.
function ns.Recorder.RecordHit(hit)
	if ns.Database.IsIgnoredSpell(hit.spellID, hit.name) then
		return
	end
	if hit.target and ns.Database.IsIgnoredTarget(hit.target) then
		return
	end
	local key = ns.Logic.RecordKey(hit.spellID, hit.isPet)
	local existing = ns.char.records[key]
	local scratch = existing and BucketFor(existing, hit.kind) or ns.Logic.NewBucket()
	local _, outcome = ns.Logic.ApplyHit(scratch, {
		kind = hit.kind,
		isCrit = hit.isCrit,
		amount = hit.amount,
		over = hit.over,
		target = hit.target,
		now = ns.Now(),
	}, ns.Database.Settings())
	if not existing and not outcome then
		return
	end
	local record = ns.Database.EnsureRecord(hit.spellID, hit.isPet, hit.name, hit.icon)
	if hit.kind == "heal" then
		record.heal = scratch
	else
		record.damage = scratch
	end
	ns.Recorder.Celebrate(record, outcome)
end

-- Combat Log tab --------------------------------------------------------------

function ns.Recorder.LogTabStatus()
	if not ns.Recorder.logTabRead then
		return nil
	end
	return string.format(ns.L.LOGTAB_READ, ns.Recorder.logTabLines or 0, ns.Recorder.logTabNew or 0,
		ns.Recorder.logTabParsed or 0, ns.Recorder.logTabTotal or 0)
end

local TAIL_SIZE = 4

function ns.Recorder.CombatLogFrame()
	if type(COMBATLOG) == "table" and COMBATLOG.GetNumMessages then
		return COMBATLOG
	end
	if type(GetChatWindowInfo) ~= "function" then
		return nil
	end
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local chat = _G["ChatFrame" .. index]
		local ok, name = pcall(GetChatWindowInfo, index)
		if chat and ok and type(name) == "string" and not ns.ValueIsSecret(name) and (name == COMBAT_LOG or name == "Combat Log") then
			return chat
		end
	end
	return nil
end

local function SpellFromName(name)
	if type(name) ~= "string" or not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then
		return nil
	end
	local ok, info = pcall(C_Spell.GetSpellInfo, name)
	if ok and type(info) == "table" and not ns.TableIsSecret(info) then
		local spellID = info.spellID
		if type(spellID) == "number" and not ns.ValueIsSecret(spellID) then
			return spellID
		end
	end
	return nil
end

-- Shows a line with its escape codes visible, once per kind of problem, so a line
-- format this parser does not know can be reported and fixed.
local function TellOnce(key, label, raw)
	ns.Recorder.told = ns.Recorder.told or {}
	if ns.Recorder.told[key] then
		return
	end
	ns.Recorder.told[key] = true
	ns.Print(label .. " " .. ns.Logic.VisibleBytes(raw))
end

local function ApplyLine(raw)
	local parsed = ns.Logic.ParseCombatLine(raw)
	if not parsed then
		local clean = ns.Logic.CleanCombatLine(raw) or ""
		if clean:find("^Your ") and (clean:find(" hit ", 1, true) or clean:find(" healed ", 1, true)) then
			TellOnce("parse", ns.L.LOGTAB_UNPARSED, raw)
		end
		return false
	end
	ns.Recorder.logTabParsed = (ns.Recorder.logTabParsed or 0) + 1
	local spellID = parsed.spellID or SpellFromName(parsed.spellName)
	if not spellID then
		ns.Recorder.unresolved = (ns.Recorder.unresolved or 0) + 1
		TellOnce("spell:" .. tostring(parsed.spellName), ns.L.LOGTAB_UNKNOWN_SPELL, parsed.spellName)
		return false
	end
	local name, icon = ns.SpellInfo(spellID)
	ns.Recorder.RecordHit({
		spellID = spellID,
		isPet = false,
		kind = parsed.kind,
		isCrit = parsed.isCrit,
		amount = parsed.amount,
		over = parsed.over,
		target = parsed.target,
		name = name or parsed.spellName,
		icon = icon,
	})
	return true
end

-- Forever keeps hit numbers secret for addons, but the client's Combat Log tab can be
-- refilled after combat and its lines read back as plain text. RefilterEntries
-- rebuilds the tab from the start, so only lines after the last seen tail count.
function ns.Recorder.ReadCombatLogTab(done)
	local function finish()
		if done then
			done()
		end
	end
	-- One read at a time. A read already under way covers the same lines.
	if ns.Recorder.tabReading then
		finish()
		return
	end
	local chat = ns.Recorder.CombatLogFrame()
	if not chat or not C_CombatLog or type(C_CombatLog.RefilterEntries) ~= "function" then
		if not ns.Recorder.toldNoTab then
			ns.Recorder.toldNoTab = true
			ns.Print(ns.L.LOGTAB_MISSING)
		end
		finish()
		return
	end
	if not pcall(C_CombatLog.RefilterEntries) then
		finish()
		return
	end
	ns.Recorder.tabReading = true
	ns.Recorder.lastTabRead = GetTime and GetTime() or 0
	local function harvest()
		ns.Recorder.tabReading = false
		ns.Guard("CombatLogTab", function()
			local okCount, count = pcall(chat.GetNumMessages, chat)
			if not okCount or type(count) ~= "number" or ns.ValueIsSecret(count) then
				return
			end
			local raws, cleaned = {}, {}
			for index = 1, count do
				local okInfo, text = pcall(chat.GetMessageInfo, chat, index)
				if okInfo and type(text) == "string" and not ns.ValueIsSecret(text) then
					raws[#raws + 1] = text
					cleaned[#cleaned + 1] = ns.Logic.CleanCombatLine(text)
				end
			end
			local applied = 0
			local start = ns.Logic.ResumeIndex(cleaned, ns.Recorder.logTail)
			ns.Recorder.logTabParsed = 0
			for index = start, #raws do
				if ApplyLine(raws[index]) then
					applied = applied + 1
				end
			end
			if #cleaned > 0 then
				ns.Recorder.logTail = ns.Logic.Tail(cleaned, TAIL_SIZE)
			end
			ns.Recorder.logTabHits = applied
			ns.Recorder.logTabLines = #raws
			ns.Recorder.logTabNew = #raws - start + 1
			-- New lines but none understood: show the newest raw line once, byte for byte.
			if ns.Recorder.logTabNew > 0 and (ns.Recorder.logTabParsed or 0) == 0 then
				local sample = raws[#raws]
				for index = #raws, start, -1 do
					if raws[index]:find("hit", 1, true) then
						sample = raws[index]
						break
					end
				end
				TellOnce("raw", ns.L.LOGTAB_UNPARSED, sample)
			end
			-- Session totals, so a quiet last read does not hide earlier ones.
			ns.Recorder.logTabTotal = (ns.Recorder.logTabTotal or 0) + applied
			ns.Recorder.logTabRead = ns.Now()
		end)
		if ns.CritLog and ns.CritLog.IsShown and ns.CritLog.IsShown() then
			ns.CritLog.Refresh()
		end
		finish()
	end
	-- The tab fills newest lines first, then backfills older ones above them.
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, harvest)
	else
		harvest()
	end
end

-- During combat the tab gets no new lines by itself, but a refill does bring the
-- current fight's hits. Each hit asks for a read; reads run at most once a second,
-- so a record shows up about a second after the hit.
local LIVE_INTERVAL = 1.0

function ns.Recorder.RequestLiveRead()
	if ns.Recorder.liveQueued or not (C_Timer and C_Timer.After) then
		return
	end
	ns.Recorder.liveQueued = true
	local now = GetTime and GetTime() or 0
	local wait = LIVE_INTERVAL - (now - (ns.Recorder.lastTabRead or 0))
	if wait < 0.2 then
		wait = 0.2
	end
	C_Timer.After(wait, function()
		ns.Recorder.liveQueued = false
		ns.Guard("CombatLogTab", function()
			ns.Recorder.ReadCombatLogTab()
		end)
	end)
end

local function OnUnitCombat(unit, action)
	if ns.ValueIsSecret(unit) or ns.ValueIsSecret(action) then
		return
	end
	-- Your hits land on the target; your heals usually land on you.
	if (unit == "target" and action == "WOUND") or (unit == "player" and action == "HEAL") then
		ns.Recorder.RequestLiveRead()
	end
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
					local _, outcome = ns.Logic.ApplyFightTotal(BucketFor(record, kind), total, ns.Now(), kind, ns.Recorder.fightID)
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

-- Current is the live pull. Expired is the fight that just ended. Expired is only a
-- fallback for an empty Current. When Current is still hidden, stop and let the caller
-- retry: falling through would save an older fight's totals as this fight and end
-- the retries before the real numbers unlock.
local function ReadSource(into, kind, isPet, guid)
	if type(guid) ~= "string" or ns.ValueIsSecret(guid) then
		return false
	end
	local meterType = MeterType(kind)
	for _, sessionType in ipairs(SessionCandidates()) do
		local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, guid)
		if ok then
			local allowed, added = ConsumeSource(into, source, isPet, kind)
			if not allowed then
				return false
			end
			if added > 0 then
				return true
			end
		end
	end
	return true
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

-- Every meter event used to start its own retry chain. Only the newest chain runs now.
-- withSummary prints the end-of-fight summary after the fight totals are read, so the
-- fight bests found by that read are part of it.
local readSerial = 0

function ns.Recorder.ScheduleMeterRead(withSummary)
	readSerial = readSerial + 1
	local serial = readSerial
	if withSummary then
		ns.Recorder.summaryPending = true
	end
	local tries = 0
	local function finish()
		-- Single hits from the Combat Log tab, then the summary that covers both.
		ns.Recorder.ReadCombatLogTab(function()
			if ns.Recorder.summaryPending then
				ns.Recorder.summaryPending = false
				ns.Recorder.PrintSummary()
			end
		end)
	end
	local function tick()
		if serial ~= readSerial then
			return
		end
		if ns.Recorder.inCombat then
			-- A new pull started. That fight schedules its own read when it ends.
			ns.Recorder.summaryPending = false
			return
		end
		tries = tries + 1
		local ok = ns.Guard("DamageMeter", ns.Recorder.ReadMeter)
		if (not ok or ns.Recorder.session.secret) and tries < 8 and C_Timer and C_Timer.After then
			C_Timer.After(0.4, tick)
			return
		end
		finish()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, tick)
	else
		ns.Guard("DamageMeter", ns.Recorder.ReadMeter)
		finish()
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
			ns.Recorder.NewFightID("fight")
		elseif event == "PLAYER_REGEN_ENABLED" then
			ns.Recorder.inCombat = false
			ns.Recorder.FlushPending()
			ns.Recorder.ScheduleMeterRead(true)
		elseif not ns.Recorder.inCombat then
			ns.Recorder.ScheduleMeterRead()
		end
	end)
	local live = CreateFrame("Frame")
	ns.Recorder.liveFrame = live
	live:SetScript("OnEvent", function(_, _, unit, action)
		OnUnitCombat(unit, action)
	end)
	pcall(live.RegisterEvent, live, "UNIT_COMBAT")

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
	-- A /reload inside combat skips PLAYER_REGEN_DISABLED, so take the state from the client.
	ns.Recorder.inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
	-- Whatever the meter holds at login belongs to one earlier fight.
	ns.Recorder.NewFightID("login")
	if not ns.Recorder.inCombat then
		ns.Recorder.ScheduleMeterRead()
	end
end
