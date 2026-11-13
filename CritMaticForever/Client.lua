local _, ns = ...

local widgetSerial = 0

function ns.WidgetName(prefix)
	widgetSerial = widgetSerial + 1
	return "CritMaticForever" .. (prefix or "Widget") .. widgetSerial
end

-- canaccessvalue() is false during combat even for an ordinary number, so it must
-- not run first. A value is hidden only when the client marks that value secret.
local function SecretAccessDenied(value, access)
	if type(access) ~= "function" then
		return true
	end
	local ok, allowed = pcall(access, value)
	if ok and allowed then
		return false
	end
	return true
end

local function ValueIsRestricted(value)
	if value == nil then
		return false
	end
	if type(value) ~= "table" and type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, value)
		if ok and not secret then
			return false
		end
		if ok and secret then
			return SecretAccessDenied(value, canaccessvalue)
		end
	end
	if type(value) == "table" and type(issecrettable) == "function" then
		local ok, secret = pcall(issecrettable, value)
		if ok and not secret then
			return false
		end
		if ok and secret then
			return SecretAccessDenied(value, canaccesstable)
		end
	end
	return false
end

function ns.ValueIsSecret(value)
	return ValueIsRestricted(value)
end

function ns.TableIsSecret(value)
	if type(value) ~= "table" then
		return false
	end
	return ValueIsRestricted(value)
end

function ns.PlainString(value)
	if type(value) ~= "string" then
		return nil
	end
	-- Check secrecy before any comparison: comparing a secret string raises an error.
	if ns.ValueIsSecret(value) or value == "" then
		return nil
	end
	return value
end

-- A step curve that stays 0 until the threshold, then 1.
function ns.CurveStepReady()
	if ns.curveStepReady ~= nil then
		return ns.curveStepReady
	end
	ns.curveStepReady = false
	if not C_CurveUtil or not C_CurveUtil.CreateCurve then
		return false
	end
	local ok, ready = pcall(function()
		local curve = C_CurveUtil.CreateCurve()
		if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
			curve:SetType(Enum.LuaCurveType.Step)
		end
		curve:AddPoint(0, 0)
		curve:AddPoint(100, 1)
		local low = curve:Evaluate(50)
		local high = curve:Evaluate(150)
		return type(low) == "number" and not ns.ValueIsSecret(low)
			and type(high) == "number" and not ns.ValueIsSecret(high)
			and low < 1 and high >= 1
	end)
	ns.curveStepReady = ok and ready and true or false
	return ns.curveStepReady
end

-- true: amount is below the step. false: amount reaches it. nil: not comparable.
function ns.SecretIsBelow(amount, stepAt)
	if not ns.CurveStepReady() or stepAt == nil or type(amount) ~= "number" then
		return nil
	end
	local ok, y = pcall(function()
		local curve = C_CurveUtil.CreateCurve()
		if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
			curve:SetType(Enum.LuaCurveType.Step)
		end
		curve:AddPoint(0, 0)
		curve:AddPoint(stepAt, 1)
		return curve:Evaluate(amount)
	end)
	if not ok or type(y) ~= "number" or ns.ValueIsSecret(y) then
		return nil
	end
	return y < 1
end

-- true only when amount is strictly greater than baseline.
function ns.SecretIsGreater(amount, baseline)
	if baseline == nil or type(amount) ~= "number" then
		return nil
	end
	-- A saved record is a plain number. Compare the hidden hit against that
	-- number directly, instead of using the hit as a curve threshold.
	if type(baseline) == "number" and not ns.ValueIsSecret(baseline) then
		if not ns.ValueIsSecret(amount) then
			return amount > baseline
		end
		local below = ns.SecretIsBelow(amount, baseline + 1)
		if below == nil then
			return nil
		end
		return below == false
	end
	-- A secret threshold the curve dropped is treated as 0, and then every
	-- later hit looks like a new record. A real record ranks above 1.
	if ns.ValueIsSecret(baseline) and ns.SecretIsBelow(1, baseline) ~= true then
		return nil
	end
	local amountBelow = ns.SecretIsBelow(amount, baseline)
	if amountBelow == nil then
		return nil
	end
	if amountBelow then
		return false
	end
	local baselineBelow = ns.SecretIsBelow(baseline, amount)
	if baselineBelow == nil then
		return nil
	end
	return baselineBelow == true
end

-- The hidden hit cannot be written to disk. A step curve answers "is it below N?"
-- with a plain yes or no, so the integer can be recovered and saved.
function ns.RecoverSecret(value)
	if type(value) ~= "number" or not ns.ValueIsSecret(value) then
		return nil
	end
	local probe = ns.SecretIsBelow(value, 1)
	if probe == nil then
		return nil
	end
	if probe then
		return nil
	end
	local low, high = 1, 2
	local guard = 0
	while guard < 24 do
		local below = ns.SecretIsBelow(value, high)
		if below == nil then
			return nil
		end
		if below then
			break
		end
		low = high
		if high > 500000000 then
			return nil
		end
		high = high * 2
		guard = guard + 1
	end
	while high - low > 1 do
		local mid = math.floor((low + high) / 2)
		local below = ns.SecretIsBelow(value, mid)
		if below == nil then
			return nil
		end
		if below then
			high = mid
		else
			low = mid
		end
	end
	return low
end

-- string.format of a secret can come back as ordinary text. tonumber of that text
-- is a real number the saved file can keep. A secret itself cannot.
function ns.PlainAmount(value)
	if type(value) ~= "number" then
		return nil
	end
	if not ns.ValueIsSecret(value) and value > 0 then
		return math.floor(value + 0.5)
	end
	local patterns = { "%.0f", "%d" }
	for index = 1, #patterns do
		local ok, text = pcall(string.format, patterns[index], value)
		if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
			local digits = text:match("%d+")
			local number = digits and tonumber(digits)
			if type(number) == "number" and number > 0 then
				return math.floor(number + 0.5)
			end
		end
	end
	local converted, number = pcall(tonumber, value)
	if converted and type(number) == "number" and not ns.ValueIsSecret(number) and number > 0 then
		return math.floor(number + 0.5)
	end
	return ns.RecoverSecret(value)
end

local function SpellFlag(reader)
	if type(reader) ~= "function" then
		return nil
	end
	local ok, value = pcall(reader)
	if ok and type(value) == "boolean" then
		return value
	end
	return nil
end

local function WithoutPhrases(text, phrases)
	local stripped = text
	for index = 1, #phrases do
		stripped = stripped:gsub(phrases[index], " ")
	end
	return stripped
end

local function NameHas(name, word)
	return name ~= "" and name:find(word, 1, true) ~= nil
end

local UTILITY_NAMES = {
	"form", "dash", "cocoon", "prowl", "innervate", "rebirth",
	"mark of the wild", "gift of the wild", "vahşi işaret",
	"teleport", "portal", "barkskin", "nature's grasp",
	"abolish", "remove curse", "cure poison", "tiger", "fury", "enrage",
	"atılma", "hızlı koşu", "koza",
}

local HEAL_NAMES = {
	"regrowth", "rejuvenation", "healing touch", "tranquility", "lifebloom",
	"nourish", "swiftmend", "wild growth",
	"yeniden büyüme", "gençleştirme", "iyileştirme dokunuşu",
}

local AURA_NAMES = {
	"thorn", "diken",
}

local NATURE_NAMES = {
	"thorn", "diken", "wrath", "moonfire", "hurricane", "insect",
	"gazap", "ay ateşi", "kasırga",
}

local ARCANE_NAMES = {
	"starfire", "yıldız ateşi",
}

local PHYSICAL_NAMES = {
	"claw", "shred", "swipe", "maul", "rake", "rip", "bite", "pounce", "ravage", "mangle",
	"pençe", "parçala", "savurma", "ezme", "tırmık", "yırtma", "ısırık",
}

local function ListHas(name, list)
	for index = 1, #list do
		if NameHas(name, list[index]) then
			return true
		end
	end
	return false
end

function ns.SpellSchool(spellID)
	local schools = ns.spellSchool
	if type(schools) ~= "table" then
		return nil
	end
	return schools[spellID]
end

local function RememberSchool(spellID, school)
	if type(school) ~= "number" then
		return
	end
	if not ns.spellSchool then
		ns.spellSchool = {}
	end
	ns.spellSchool[spellID] = school
end

local function SchoolFromText(name, desc)
	if ListHas(name, NATURE_NAMES) or desc:find("nature", 1, true) or desc:find("doğa", 1, true) then
		return 8
	end
	if ListHas(name, ARCANE_NAMES) or desc:find("arcane", 1, true) or desc:find("gizem", 1, true) then
		return 64
	end
	if desc:find("fire", 1, true) or desc:find("ateş", 1, true) or desc:find("flame", 1, true) then
		return 4
	end
	if desc:find("frost", 1, true) or desc:find("buz", 1, true) then
		return 16
	end
	if desc:find("shadow", 1, true) or desc:find("gölge", 1, true) then
		return 32
	end
	if desc:find("holy", 1, true) or desc:find("kutsal", 1, true) then
		return 2
	end
	if ListHas(name, PHYSICAL_NAMES) then
		return 1
	end
	return nil
end

function ns.SpellRole(spellID)
	if type(spellID) ~= "number" then
		return "other"
	end
	if not ns.spellRole then
		ns.spellRole = {}
	end
	if ns.spellRole[spellID] then
		return ns.spellRole[spellID]
	end
	local name, desc = "", ""
	local spellName = ns.SpellInfo and ns.SpellInfo(spellID) or nil
	if type(spellName) == "string" then
		name = spellName:lower()
	end
	if C_Spell and C_Spell.GetSpellDescription then
		local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
		if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
			desc = text:lower()
		end
	end
	if desc == "" and type(GetSpellDescription) == "function" then
		local ok, text = pcall(GetSpellDescription, spellID)
		if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
			desc = text:lower()
		end
	end
	local described = desc ~= ""
	local school = SchoolFromText(name, desc)
	RememberSchool(spellID, school)
	local function remember(role, roleSchool)
		RememberSchool(spellID, roleSchool or school)
		ns.spellRole[spellID] = role
		return role
	end
	local reflect = described and (desc:find("when hit", 1, true) or desc:find("attacker", 1, true))
	if ListHas(name, AURA_NAMES) or (reflect and (desc:find("damage", 1, true) or desc:find("hasar", 1, true))) then
		return remember("aura", school or 8)
	end
	if name:find("form", 1, true) or desc:find("shapeshift", 1, true) or desc:find("formuna", 1, true) or ListHas(name, UTILITY_NAMES) then
		return remember("other")
	end
	if ListHas(name, HEAL_NAMES) then
		return remember("heal")
	end
	if ListHas(name, PHYSICAL_NAMES) then
		return remember("damage", 1)
	end
	if ListHas(name, NATURE_NAMES) or ListHas(name, ARCANE_NAMES) then
		return remember("damage", school)
	end
	local harmful = nil
	if C_Spell and C_Spell.IsSpellHarmful then
		harmful = SpellFlag(function()
			return C_Spell.IsSpellHarmful(spellID)
		end)
	end
	if harmful == nil and type(IsHarmfulSpell) == "function" then
		harmful = SpellFlag(function()
			return IsHarmfulSpell(spellID)
		end)
	end
	local healText = WithoutPhrases(desc, { "health" })
	local damageText = WithoutPhrases(desc, {
		"damage taken", "damage done", "increases damage", "increase damage", "increased damage",
		"reduces damage", "reduce damage", "reduced damage", "all damage",
		"alınan hasar", "hasarı azalt", "hasar azalt",
	})
	local heals = healText:find("heal", 1, true) or healText:find("iyile", 1, true)
	local hurts = damageText:find("damage", 1, true) or damageText:find("hasar", 1, true)
	if described and heals and not hurts then
		return remember("heal")
	end
	if described and hurts then
		if school == nil then
			school = 1
			RememberSchool(spellID, 1)
		end
		return remember("damage", school)
	end
	if harmful == true then
		return remember("damage", school or 1)
	end
	if described or harmful == false then
		return remember("other")
	end
	return "damage"
end

local PERIODIC_NAMES = {
	"rip", "rake", "moonfire", "insect", "rejuvenation", "lifebloom", "regrowth",
	"thorn", "renew", "immolate", "corruption", "garrote",
	"yırtma", "tırmık", "ay ateşi", "böcek", "gençleştirme", "diken", "yeniden büyüme",
}

-- Damage ticks and heal-over-time spells. A direct hit such as Claw is not periodic.
function ns.SpellPeriodic(spellID)
	if type(spellID) ~= "number" then
		return false
	end
	if not ns.spellPeriodic then
		ns.spellPeriodic = {}
	end
	if ns.spellPeriodic[spellID] ~= nil then
		return ns.spellPeriodic[spellID]
	end
	if ns.SpellRole(spellID) == "aura" then
		ns.spellPeriodic[spellID] = true
		return true
	end
	local name = ""
	local spellName = ns.SpellInfo and ns.SpellInfo(spellID) or nil
	if type(spellName) == "string" and not ns.ValueIsSecret(spellName) then
		name = spellName:lower()
	end
	local periodic = ListHas(name, PERIODIC_NAMES)
	if not periodic then
		local desc = ""
		if C_Spell and C_Spell.GetSpellDescription then
			local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
			if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
				desc = text:lower()
			end
		end
		if desc == "" and type(GetSpellDescription) == "function" then
			local ok, text = pcall(GetSpellDescription, spellID)
			if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
				desc = text:lower()
			end
		end
		periodic = desc:find("over %d", 1) ~= nil
			or desc:find("every %d", 1) ~= nil
			or desc:find("per second", 1, true) ~= nil
			or desc:find("saniye boyunca", 1, true) ~= nil
			or desc:find("saniyede", 1, true) ~= nil
	end
	ns.spellPeriodic[spellID] = periodic and true or false
	return ns.spellPeriodic[spellID]
end

function ns.FormatNumber(amount)
	if type(BreakUpLargeNumbers) == "function" then
		local rounded = math.floor((tonumber(amount) or 0) + 0.5)
		local ok, text = pcall(BreakUpLargeNumbers, rounded)
		if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
			return text
		end
	end
	return ns.Logic.FormatNumber(amount)
end

local function LineFont()
	if ns.lineText or not CreateFrame then
		return ns.lineText
	end
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -2000, -200)
	holder:SetAlpha(0)
	holder:Show()
	ns.lineText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ns.lineText:SetPoint("LEFT")
	ns.lineText:SetWordWrap(false)
	return ns.lineText
end

function ns.FormatLine(pattern, ...)
	if type(pattern) ~= "string" then
		return nil
	end
	local ok, text = pcall(string.format, pattern, ...)
	if ok and type(text) == "string" and not ns.ValueIsSecret(text) then
		return text
	end
	local font = LineFont()
	if font and pcall(font.SetFormattedText, font, pattern, ...) then
		local readOk, shown = pcall(font.GetText, font)
		if readOk and shown ~= nil then
			return shown
		end
	end
	if ok and text ~= nil then
		return text
	end
	return nil
end

function ns.JoinText(left, right)
	if left == nil then
		return right
	end
	if right == nil then
		return left
	end
	local font = LineFont()
	if font and pcall(font.SetFormattedText, font, "%s %s", left, right) then
		local ok, text = pcall(font.GetText, font)
		if ok and text ~= nil then
			return text
		end
	end
	local ok, text = pcall(function()
		return left .. " " .. right
	end)
	if ok and text ~= nil then
		return text
	end
	return left
end

function ns.Print(message)
	if message == nil then
		return
	end
	local frame = DEFAULT_CHAT_FRAME
	if not frame or not frame.AddMessage then
		if type(print) == "function" and not ns.ValueIsSecret(message) then
			print(tostring(message))
		end
		return
	end
	if not ns.ValueIsSecret(message) then
		frame:AddMessage("|cffff8010CritMatic Forever|r " .. tostring(message))
		return
	end
	local font = LineFont()
	if font and pcall(font.SetFormattedText, font, "|cffff8010CritMatic Forever|r %s", message) then
		local ok, text = pcall(font.GetText, font)
		if ok and text ~= nil then
			pcall(frame.AddMessage, frame, text)
			return
		end
	end
	pcall(frame.AddMessage, frame, message)
end

function ns.Paint(texture, r, g, b, a)
	a = a or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(r, g, b, a)
	else
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
		texture:SetVertexColor(r, g, b, a)
	end
end

function ns.AddonVersion()
	local name = ns.addonName
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local version = C_AddOns.GetAddOnMetadata(name, "Version")
		if type(version) == "string" and version ~= "" then
			return version
		end
	end
	if type(GetAddOnMetadata) == "function" then
		local version = GetAddOnMetadata(name, "Version")
		if type(version) == "string" and version ~= "" then
			return version
		end
	end
	return "1.0.0"
end

function ns.SpellInfo(spellID)
	if type(spellID) ~= "number" then
		return nil, nil
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" and not ns.TableIsSecret(info) then
			local name = ns.PlainString(info.name)
			local icon = info.iconID
			if ns.ValueIsSecret(icon) then
				icon = nil
			end
			if name then
				return name, icon
			end
		end
	end
	if spellID == ns.Logic.AutoAttackID() then
		return ns.L.AUTO_ATTACK, nil
	end
	return nil, nil
end

function ns.Now()
	if type(GetServerTime) == "function" then
		local ok, value = pcall(GetServerTime)
		if ok and type(value) == "number" and not ns.ValueIsSecret(value) then
			return value
		end
	end
	if type(time) == "function" then
		return time()
	end
	return 0
end

function ns.Guard(label, fn)
	local ok, err = pcall(fn)
	if not ok and ns.lastError ~= err then
		ns.lastError = err
		ns.Print("|cffff6060" .. label .. ":|r " .. tostring(err))
	end
	return ok, err
end

local SOUND_KEYS = {
	raid = "RAID_WARNING",
	ready = "READY_CHECK",
	level = "LEVELUP",
	quest = "ALARM_CLOCK_WARNING_3",
}

local SOUND_FALLBACK = {
	raid = 8959,
	ready = 8960,
	level = 888,
	quest = 12889,
}

function ns.ResolveSound(key)
	local constant = SOUND_KEYS[key]
	if constant and type(SOUNDKIT) == "table" and SOUNDKIT[constant] then
		return SOUNDKIT[constant]
	end
	return SOUND_FALLBACK[key]
end

function ns.ApplyBackdrop(frame, r, g, b, a)
	if not frame.SetBackdrop then
		return
	end
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(r or 0.05, g or 0.045, b or 0.06, a or 0.94)
	frame:SetBackdropBorderColor(0.78, 0.58, 0.2, 1)
end
