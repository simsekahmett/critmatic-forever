local _, ns = ...

ns.Recorder = {
	hidden = 0,
	pending = {},
	fightFeed = {},
}

local function BucketFor(record, kind)
	if kind == "heal" then
		return record.heal
	end
	return record.damage
end

local function AnnounceKey(spellID, isPet, kind, field)
	return ns.Logic.RecordKey(spellID, isPet) .. ":" .. (kind or "damage") .. ":" .. (field or "hit")
end

local function NoteAnnounced(spellID, isPet, kind, field, amount)
	if type(spellID) ~= "number" or type(amount) ~= "number" then
		return
	end
	if not ns.Recorder.announced then
		ns.Recorder.announced = {}
	end
	ns.Recorder.announced[AnnounceKey(spellID, isPet, kind, field)] = amount
end

local function ReadAnnounced(spellID, isPet, kind, field)
	local saved = ns.Recorder.announced and ns.Recorder.announced[AnnounceKey(spellID, isPet, kind, field)]
	if ns.ValueIsSecret(saved) or (type(saved) == "number" and saved > 0) then
		return saved
	end
	return nil
end

function ns.Recorder.BuildPayload(record, outcome)
	local L = ns.L
	local name = record.name or ("#" .. tostring(record.spellID))
	if record.isPet then
		name = L.PET .. ": " .. name
	end

	local label, colorKey, soundKey
	if outcome.kind == "heal" and outcome.field == "crit" then
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
	local secretPrevious
	local chat = ns.FormatLine(L.CHAT_RECORD, label, name, amount)
	if ns.ValueIsSecret(outcome.previous) then
		secretPrevious = outcome.previous
		local suffix = ns.FormatLine(L.CHAT_PREVIOUS, outcome.previous)
		chat = ns.JoinText(chat, suffix)
	elseif type(outcome.previous) == "number" and outcome.previous > 0 then
		previous = ns.FormatNumber(outcome.previous)
		local suffix = ns.FormatLine(L.CHAT_PREVIOUS, previous)
		chat = ns.JoinText(chat, suffix)
	end

	return {
		name = name,
		label = label,
		amount = amount,
		previous = previous,
		secretPrevious = secretPrevious,
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
	if outcome and not ns.ValueIsSecret(outcome.previous) and (type(outcome.previous) ~= "number" or outcome.previous <= 0) then
		if ns.ValueIsSecret(hit.previous) or (type(hit.previous) == "number" and hit.previous > 0) then
			outcome.previous = hit.previous
		end
	end
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
	if outcome then
		NoteAnnounced(hit.spellID, hit.isPet, hit.kind, hit.isCrit and "crit" or "hit", hit.amount)
	end
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

-- UNIT_COMBAT reports the hit as it lands. The amount is secret, so it is shown
-- directly and compared with a curve. The spell name is the cast that just finished.
local function IncomingUnit(unit)
	if type(unit) ~= "string" or ns.ValueIsSecret(unit) then
		return false
	end
	if unit == "player" or unit == "pet" then
		return true
	end
	return unit:find("^party") ~= nil or unit:find("^raid") ~= nil
end

local function EventSchool(school)
	if type(school) == "number" and not ns.ValueIsSecret(school) then
		return school
	end
	return nil
end

local function SameSchool(left, right)
	if type(left) ~= "number" or type(right) ~= "number" then
		return false
	end
	if bit and bit.band then
		return bit.band(left, right) ~= 0
	end
	return left == right
end

local function PlayerHasAura(spellID)
	if type(spellID) ~= "number" then
		return nil
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
		if ok then
			if aura == nil then
				if ns.Recorder.inCombat then
					return nil
				end
				return false
			end
			if ns.ValueIsSecret(aura) or ns.TableIsSecret(aura) then
				return nil
			end
			return true
		end
	end
	return nil
end

local function AuraLive(cast, now)
	local up = PlayerHasAura(cast.spellID)
	if up == true then
		return true
	end
	if up == false then
		return false
	end
	return (now - (cast.time or 0)) <= 600
end

local MELEE_WINDOW = 0.4
local MATCH_WINDOW = 5
local REACTIVE_WINDOW = 0.2

local function LearnedSchool(spellID)
	local book = ns.char and ns.char.castLearn
	local stats = type(book) == "table" and book[spellID] or nil
	local votes = stats and stats.dmg
	if type(votes) ~= "table" then
		return nil
	end
	local best, bestCount
	for mask, count in pairs(votes) do
		if type(mask) == "number" and type(count) == "number" and (not bestCount or count > bestCount) then
			best, bestCount = mask, count
		end
	end
	return best
end

local function VoteSchool(spellID, schoolMask)
	if type(spellID) ~= "number" or type(schoolMask) ~= "number" or type(ns.char) ~= "table" then
		return
	end
	local book = ns.char.castLearn
	if type(book) ~= "table" then
		book = {}
		ns.char.castLearn = book
	end
	local stats = book[spellID]
	if type(stats) ~= "table" then
		stats = {}
		book[spellID] = stats
	end
	local votes = stats.dmg
	if type(votes) ~= "table" then
		votes = {}
		stats.dmg = votes
	end
	votes[schoolMask] = (votes[schoolMask] or 0) + 1
end

local function PruneDamageCasts(now)
	local queue = ns.Recorder.damageCasts
	if type(queue) ~= "table" then
		return
	end
	while queue[1] and (queue[1].used or now - (queue[1].time or 0) > MATCH_WINDOW) do
		table.remove(queue, 1)
	end
end

-- Oldest unused cast whose learned school matches. A physical swing while you
-- are attacking only belongs to a spell cast in the last 0.4s; anything later is an auto attack.
local function MatchDamage(eventSchool)
	local now = GetTime and GetTime() or 0
	PruneDamageCasts(now)
	local melee = ns.Recorder.meleeActive or ns.Recorder.autoRepeat
	local maxAge = MATCH_WINDOW
	if melee and (eventSchool == nil or eventSchool == 1) then
		maxAge = MELEE_WINDOW
	end
	local queue = ns.Recorder.damageCasts
	local exact, unknown
	if type(queue) == "table" then
		for index = 1, #queue do
			local cast = queue[index]
			local age = now - (cast.time or 0)
			if not cast.used and age >= 0 and age <= maxAge then
				local school = LearnedSchool(cast.spellID) or cast.school
				if eventSchool ~= nil and school ~= nil and school ~= eventSchool then
					-- a physical cast cannot take a nature hit
				elseif eventSchool ~= nil and school == eventSchool then
					exact = cast
					break
				elseif not unknown then
					unknown = cast
				end
			end
		end
	end
	local cast = exact or unknown
	if not cast then
		local channel = ns.Recorder.channelCast
		if channel then
			local school = LearnedSchool(channel.spellID)
			if eventSchool == nil or school == nil or school == eventSchool then
				cast = channel
			end
		end
	end
	if cast then
		cast.used = true
		if eventSchool ~= nil then
			VoteSchool(cast.spellID, eventSchool)
		end
		PruneDamageCasts(now)
		return cast.spellID, cast.pet and true or false
	end
	local hurtAge = now - (ns.Recorder.lastHurt or -100)
	local justHurt = hurtAge >= 0 and hurtAge <= REACTIVE_WINDOW
	local reactive = ns.Recorder.reactiveSpell
	if reactive and eventSchool ~= 1 and (justHurt or eventSchool == 8 or (eventSchool ~= nil and SameSchool(reactive.school, eventSchool))) then
		if AuraLive(reactive, now) then
			return reactive.spellID, false
		end
	end
	if eventSchool == nil or eventSchool == 1 then
		return ns.Logic.AutoAttackID(), false
	end
	return nil, false
end

local function RecentSpell(kind, eventSchool)
	local history = ns.Recorder.castHistory
	if kind == "heal" then
		local now = GetTime and GetTime() or 0
		if type(history) == "table" then
			for index = #history, 1, -1 do
				local cast = history[index]
				local age = now - (cast.time or 0)
				if age > 21 then
					break
				end
				if age >= 0 and cast.role == "heal" then
					return cast.spellID, cast.pet
				end
			end
		end
		return nil, false
	end
	return MatchDamage(eventSchool)
end

local function MemoryKey(spellID, isPet, kind, field)
	local suffix = (kind or "damage") .. ":" .. (field or "crit")
	if type(spellID) ~= "number" then
		return suffix
	end
	return ns.Logic.RecordKey(spellID, isPet) .. ":" .. suffix
end

local function SavedCrit(spellID, isPet, kind, field)
	if type(spellID) ~= "number" or type(ns.char) ~= "table" or type(ns.char.records) ~= "table" then
		return 0
	end
	local record = ns.char.records[ns.Logic.RecordKey(spellID, isPet)]
	if type(record) ~= "table" then
		return 0
	end
	local bucket = kind == "heal" and record.heal or record.damage
	local value = type(bucket) == "table" and bucket[field or "crit"] or nil
	if type(value) == "number" and not ns.ValueIsSecret(value) and value > 0 then
		return value
	end
	return 0
end

-- Writes one plain record into the character saved vars. A secret must never land
-- in that table: the client drops it on logout and the log looks session-only.
function ns.Recorder.StorePlain(spellID, isPet, kind, field, number)
	if type(spellID) ~= "number" or type(number) ~= "number" or ns.ValueIsSecret(number) or number <= 0 then
		return false
	end
	number = math.floor(number + 0.5)
	local name, icon = ns.SpellInfo(spellID)
	if ns.ValueIsSecret(name) then
		name = nil
	end
	if ns.ValueIsSecret(icon) then
		icon = nil
	end
	local record = ns.Database.EnsureRecord(spellID, isPet, name, icon)
	local bucket = kind == "heal" and record.heal or record.damage
	local slot = field == "crit" and "crit" or "hit"
	local previous = bucket[slot]
	if type(previous) ~= "number" or ns.ValueIsSecret(previous) then
		previous = 0
	end
	if number <= previous then
		return true
	end
	bucket[slot] = number
	if slot == "crit" then
		bucket.critTime = ns.Now()
	else
		bucket.hitTime = ns.Now()
	end
	local key = MemoryKey(spellID, isPet, kind, slot)
	if ns.Recorder.combatBest then
		ns.Recorder.combatBest[key] = nil
	end
	if ns.Recorder.secretBest then
		ns.Recorder.secretBest[key] = nil
	end
	if ns.CritLog and ns.CritLog.IsShown and ns.CritLog.IsShown() then
		ns.CritLog.Refresh()
	end
	return true
end

local function QueueSave(spellID, isPet, kind, field, amount)
	if type(spellID) ~= "number" or type(amount) ~= "number" then
		return
	end
	local number = ns.PlainAmount(amount)
	if number and ns.Recorder.StorePlain(spellID, isPet, kind, field, number) then
		return
	end
	if not ns.ValueIsSecret(amount) then
		return
	end
	if not ns.Recorder.toSave then
		ns.Recorder.toSave = {}
	end
	local key = MemoryKey(spellID, isPet, kind, field)
	local row = ns.Recorder.toSave[key]
	if type(row) ~= "table" then
		row = {
			spellID = spellID,
			isPet = isPet and true or false,
			kind = kind,
			field = field,
			amounts = {},
		}
		ns.Recorder.toSave[key] = row
	end
	local amounts = row.amounts
	amounts[#amounts + 1] = amount
	if #amounts > 40 then
		table.remove(amounts, 1)
	end
	ns.Recorder.ScheduleSave()
end

local saveSerial = 0

function ns.Recorder.FlushSavedRecords()
	local pending = ns.Recorder.toSave
	if type(pending) ~= "table" then
		return
	end
	local left = {}
	for key, row in pairs(pending) do
		local best
		local waiting = {}
		local amounts = row.amounts or { row.amount }
		for index = 1, #amounts do
			local number = ns.PlainAmount(amounts[index])
			if number and (not best or number > best) then
				best = number
			elseif not number then
				waiting[#waiting + 1] = amounts[index]
			end
		end
		if best then
			ns.Recorder.StorePlain(row.spellID, row.isPet, row.kind, row.field, best)
		end
		if #waiting > 0 then
			row.amounts = waiting
			left[key] = row
		end
	end
	ns.Recorder.toSave = left
end

function ns.Recorder.ScheduleSave()
	saveSerial = saveSerial + 1
	local serial = saveSerial
	local delays = { 0.4, 1.5, 4 }
	local function step(index)
		if not C_Timer or not C_Timer.After then
			return
		end
		local delay = delays[index]
		if not delay then
			return
		end
		C_Timer.After(delay, function()
			if serial ~= saveSerial then
				return
			end
			ns.Recorder.FlushSavedRecords()
			if ns.Recorder.toSave and next(ns.Recorder.toSave) then
				step(index + 1)
			end
		end)
	end
	step(1)
end

function ns.Recorder.NoteCast(unit, _, spellID)
	if unit ~= "player" and unit ~= "pet" then
		return
	end
	if ns.ValueIsSecret(spellID) or type(spellID) ~= "number" then
		return
	end
	local now = GetTime and GetTime() or 0
	local role = ns.SpellRole(spellID)
	local entry = {
		spellID = spellID,
		pet = unit == "pet",
		time = now,
		role = role,
		school = ns.SpellSchool(spellID),
	}
	ns.Recorder.lastCast = entry
	if spellID ~= ns.Logic.AutoAttackID() and unit == "player" then
		if role == "aura" then
			ns.Recorder.reactiveSpell = entry
		elseif role == "damage" then
			PruneDamageCasts(now)
			local queue = ns.Recorder.damageCasts
			if type(queue) ~= "table" then
				queue = {}
				ns.Recorder.damageCasts = queue
			end
			queue[#queue + 1] = {
				spellID = spellID,
				pet = false,
				time = now,
				school = entry.school,
				used = false,
			}
		end
	end
	local history = ns.Recorder.castHistory
	if type(history) ~= "table" then
		history = {}
		ns.Recorder.castHistory = history
	end
	history[#history + 1] = entry
	if #history > 20 then
		table.remove(history, 1)
	end
end

local function ShareCrit(name, amount)
	local party = ns.Database.Get("shareParty")
	local guild = ns.Database.Get("shareGuild")
	local raid = ns.Database.Get("shareRaid")
	if not party and not guild and not raid then
		return
	end
	local line = ns.FormatLine(ns.L.CRIT_SHARE, name, amount)
	if line == nil then
		return
	end
	local function send(channel, enabled, present)
		if not enabled or not present then
			return
		end
		if type(SendChatMessage) == "function" then
			pcall(SendChatMessage, line, channel)
		elseif C_ChatInfo and C_ChatInfo.SendChatMessage then
			pcall(C_ChatInfo.SendChatMessage, line, channel)
		end
	end
	send("PARTY", party, IsInGroup and IsInGroup())
	send("RAID", raid, IsInRaid and IsInRaid())
	send("GUILD", guild, IsInGuild and IsInGuild())
end

function ns.Recorder.ShowCrit(kind, amount, spellID, isPet)
	local name, icon
	if type(spellID) == "number" then
		name, icon = ns.SpellInfo(spellID)
	end
	if isPet and name then
		name = ns.L.PET .. ": " .. name
	end
	if not name then
		name = kind == "heal" and ns.L.HEAL or ns.L.AUTO_ATTACK
	end
	if ns.Database.IsIgnoredSpell(spellID, name) then
		return
	end
	local colorKey = kind == "heal" and "critHeal" or "crit"
	local soundKey = kind == "heal" and "soundHealCrit" or "soundCrit"
	if ns.Database.Get("alert") then
		ns.Alerts.Show({
			name = name,
			critFeed = true,
			secretAmount = amount,
			icon = icon,
			colorKey = colorKey,
			sound = ns.Database.Get(soundKey),
		}, false)
	end
	if ns.Database.Get("chat") then
		local line = ns.FormatLine(ns.L.CRIT_LINE, name, amount)
		if line ~= nil then
			ns.Print(line)
		end
	end
	ShareCrit(name, amount)
end

function ns.Recorder.ShowSecretHit(kind, isCrit, amount, spellID, isPet, previous)
	local now = GetTime and GetTime() or 0
	if not isCrit and (now - (ns.Recorder.lastSecretAt or 0)) < 0.05 then
		return
	end
	ns.Recorder.lastSecretAt = now
	if type(spellID) ~= "number" then
		spellID, isPet = RecentSpell(kind)
	end
	local name, icon
	if type(spellID) == "number" then
		name, icon = ns.SpellInfo(spellID)
	end
	if isPet and name then
		name = ns.L.PET .. ": " .. name
	end
	if not name then
		name = kind == "heal" and ns.L.NEW_HEAL or ns.L.AUTO_ATTACK
	end
	if ns.Database.IsIgnoredSpell(spellID, name) then
		return
	end
	local label, colorKey, soundKey
	if kind == "heal" and isCrit then
		label, colorKey, soundKey = ns.L.NEW_HEAL_CRIT, "critHeal", "soundHealCrit"
	elseif kind == "heal" then
		label, colorKey, soundKey = ns.L.NEW_HEAL, "heal", "soundHeal"
	elseif isCrit then
		label, colorKey, soundKey = ns.L.NEW_CRIT, "crit", "soundCrit"
	else
		label, colorKey, soundKey = ns.L.NEW_HIT, "hit", "soundHit"
	end
	local previousSecret
	local previousPlain
	if ns.ValueIsSecret(previous) then
		local recovered = ns.PlainAmount(previous)
		if type(recovered) == "number" and not ns.ValueIsSecret(recovered) and recovered > 0 then
			previousPlain = ns.FormatNumber(recovered)
		else
			previousSecret = previous
		end
	elseif type(previous) == "number" and previous > 0 then
		previousPlain = ns.FormatNumber(previous)
	end
	local hasPrevious = previousPlain ~= nil or ns.ValueIsSecret(previousSecret)
	if ns.Database.Get("alert") then
		ns.Alerts.Show({
			name = name,
			label = label,
			secretAmount = amount,
			previous = previousPlain,
			secretPrevious = previousSecret,
			icon = icon,
			colorKey = colorKey,
			sound = ns.Database.Get(soundKey),
		}, false)
	end
	if ns.Database.Get("chat") then
		local line = ns.FormatLine(ns.L.CHAT_RECORD, label, name, amount)
		if hasPrevious then
			local shownPrevious = previousPlain
			if shownPrevious == nil then
				shownPrevious = previousSecret
			end
			local suffix = ns.FormatLine(ns.L.CHAT_PREVIOUS, shownPrevious)
			line = ns.JoinText(line, suffix)
		end
		if line ~= nil then
			ns.Print(line)
		end
	end
	NoteAnnounced(spellID, isPet, kind, isCrit and "crit" or "hit", amount)
	ns.Recorder.shownSecret = (ns.Recorder.shownSecret or 0) + 1
end

local IGNORE_ACTION = {
	MISS = true,
	DODGE = true,
	PARRY = true,
	RESIST = true,
	ABSORB = true,
	DEFLECT = true,
	IMMUNE = true,
	EVADE = true,
	REFLECT = true,
	ENERGIZE = true,
}

function ns.Recorder.OnUnitCombat(unit, action, flagText, amount, school)
	local actionText
	if type(action) == "string" and not ns.ValueIsSecret(action) then
		actionText = action
	end
	if actionText and IGNORE_ACTION[actionText] then
		return
	end
	if type(amount) ~= "number" then
		return
	end
	local crit = false
	local flagSecret = flagText ~= nil and ns.ValueIsSecret(flagText)
	if not flagSecret then
		if type(flagText) == "boolean" then
			crit = flagText == true
		elseif type(flagText) == "string" then
			crit = flagText:find("CRIT") ~= nil
		end
	end
	local incoming = IncomingUnit(unit)
	local kind
	if actionText == "HEAL" then
		if not incoming then
			return
		end
		kind = "heal"
	elseif incoming then
		if actionText ~= "HEAL" then
			ns.Recorder.lastHurt = GetTime and GetTime() or 0
		end
		return
	else
		if unit ~= "target" then
			return
		end
		kind = "damage"
	end
	if kind == "damage" and ns.Database.Get("trackDamage") == false then
		return
	end
	if kind == "heal" and ns.Database.Get("trackHealing") == false then
		return
	end
	-- The crit flag is a plain string on this client. A hidden flag is not treated as a crit.
	if flagSecret or not crit then
		return
	end
	if ns.Database.Get("trackCrit") == false then
		return
	end
	local spellID, isPet = RecentSpell(kind, EventSchool(school))
	if type(spellID) ~= "number" then
		return
	end
	-- Ticks and heal over time show only when they crit. Direct hits use that same rule.
	if ns.SpellPeriodic(spellID) and not crit then
		return
	end
	pcall(ns.Recorder.ShowCrit, kind, amount, spellID, isPet)
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

	local combat = CreateFrame("Frame")
	ns.Recorder.combatState = combat
	combat:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			ns.Recorder.inCombat = true
			ns.Recorder.pending = {}
			ns.Recorder.fightFeed = {}
		elseif event == "PLAYER_REGEN_ENABLED" then
			ns.Recorder.inCombat = false
			ns.Recorder.FlushPending()
			ns.Recorder.FlushSavedRecords()
			ns.Recorder.ScheduleSave()
			ns.Recorder.PrintSummary()
		elseif event == "PLAYER_LOGOUT" then
			ns.Recorder.FlushSavedRecords()
		end
	end)
	combat:RegisterEvent("PLAYER_REGEN_DISABLED")
	combat:RegisterEvent("PLAYER_REGEN_ENABLED")
	combat:RegisterEvent("PLAYER_LOGOUT")
	local live = CreateFrame("Frame")
	ns.Recorder.liveFrame = live
	live:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			ns.Recorder.NoteCast(...)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
			local unit, _, channelID = ...
			if unit == "player" and type(channelID) == "number" then
				ns.Recorder.channelCast = {
					spellID = channelID,
					time = GetTime and GetTime() or 0,
					used = false,
				}
			end
		elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			local cast = ns.Recorder.channelCast
			if cast and C_Timer and C_Timer.After then
				C_Timer.After(0.5, function()
					if ns.Recorder.channelCast == cast then
						ns.Recorder.channelCast = nil
					end
				end)
			else
				ns.Recorder.channelCast = nil
			end
		elseif event == "PLAYER_ENTER_COMBAT" then
			ns.Recorder.meleeActive = true
		elseif event == "PLAYER_LEAVE_COMBAT" then
			ns.Recorder.meleeActive = false
		elseif event == "START_AUTOREPEAT_SPELL" then
			ns.Recorder.autoRepeat = true
		elseif event == "STOP_AUTOREPEAT_SPELL" then
			ns.Recorder.autoRepeat = false
		elseif event == "UNIT_COMBAT" then
			ns.Recorder.OnUnitCombat(...)
		end
	end)
	local function listen(event)
		pcall(live.RegisterEvent, live, event)
	end
	listen("UNIT_COMBAT")
	listen("UNIT_SPELLCAST_SUCCEEDED")
	listen("UNIT_SPELLCAST_CHANNEL_START")
	listen("UNIT_SPELLCAST_CHANNEL_STOP")
	listen("PLAYER_ENTER_COMBAT")
	listen("PLAYER_LEAVE_COMBAT")
	listen("START_AUTOREPEAT_SPELL")
	listen("STOP_AUTOREPEAT_SPELL")

end

function ns.Recorder.OnLogin()
	if not ns.char.welcomed then
		ns.Print(ns.L.WELCOME)
		ns.char.welcomed = true
	end
	-- A /reload inside combat skips PLAYER_REGEN_DISABLED, so take the state from the client.
	ns.Recorder.inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
end
