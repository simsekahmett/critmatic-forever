local _, ns = ...

local widgetSerial = 0

function ns.WidgetName(prefix)
	widgetSerial = widgetSerial + 1
	return "CritMaticForever" .. (prefix or "Widget") .. widgetSerial
end

-- Same order as other Forever addons: canaccessvalue first, then the secret
-- predicates, each inside pcall. A raw call can itself raise on a restricted value.
local function ValueIsRestricted(value)
	if type(canaccessvalue) == "function" then
		local ok, accessible = pcall(canaccessvalue, value)
		if ok then
			return not accessible
		end
	end
	if type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, value)
		if ok and secret then
			return true
		end
	end
	if type(value) == "table" and type(issecrettable) == "function" then
		local ok, secretTable = pcall(issecrettable, value)
		if ok and secretTable then
			return true
		end
	end
	if type(value) == "table" and type(canaccesstable) == "function" then
		local ok, accessible = pcall(canaccesstable, value)
		if ok then
			return not accessible
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

function ns.Print(message)
	local text = "|cffff8010CritMatic Forever|r " .. tostring(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(text)
	elseif type(print) == "function" then
		print(text)
	end
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
