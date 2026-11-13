-- /cmf probe: shows what this client hands to addons, so single-hit records can be
-- built on a source that really works. Prints only; it saves nothing.
local _, ns = ...

ns.Probe = {}

local WATCH_SECONDS = 60
local MAX_LINES = 6
local frame
local lines = 0
local running = false

local function Show(value)
	if value == nil then
		return "nil"
	end
	if ns.ValueIsSecret(value) then
		return "<secret>"
	end
	if type(value) == "table" then
		return "<table>"
	end
	return tostring(value)
end

local function Keys(tbl)
	if type(tbl) ~= "table" then
		return Show(tbl)
	end
	if ns.TableIsSecret(tbl) then
		return "<secret table>"
	end
	local list = {}
	for key, value in pairs(tbl) do
		list[#list + 1] = tostring(key) .. "=" .. (type(value) == "function" and "fn" or Show(value))
	end
	table.sort(list)
	return table.concat(list, ", ")
end

local function Say(text)
	ns.Print("|cff80c0ffprobe|r " .. text)
end

local function MeterShape()
	if not C_DamageMeter or type(C_DamageMeter.GetCombatSessionSourceFromType) ~= "function" then
		Say("meter: no GetCombatSessionSourceFromType")
		return
	end
	local guid = UnitGUID and UnitGUID("player")
	local sessionEnum = Enum and Enum.DamageMeterSessionType
	local typeEnum = Enum and Enum.DamageMeterType
	local sessions = {
		{ "Current", sessionEnum and sessionEnum.Current or 1 },
		{ "Expired", sessionEnum and sessionEnum.Expired or 2 },
	}
	for _, info in ipairs(sessions) do
		local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, info[2], typeEnum and typeEnum.DamageDone or 0, guid)
		if not ok then
			Say("meter " .. info[1] .. ": error " .. tostring(source))
		elseif type(source) ~= "table" then
			Say("meter " .. info[1] .. ": " .. Show(source))
		else
			Say("meter " .. info[1] .. " source: " .. Keys(source))
			local spells = not ns.TableIsSecret(source) and source.combatSpells or nil
			if type(spells) == "table" and not ns.TableIsSecret(spells) then
				Say("meter " .. info[1] .. " spells: " .. tostring(#spells))
				-- Up to three spells, with every field, so a per-spell max hit shows up if it exists.
				for index = 1, math.min(3, #spells) do
					local spell = spells[index]
					if type(spell) == "table" then
						local name = not ns.TableIsSecret(spell) and ns.SpellInfo(spell.spellID) or nil
						Say(string.format("  spell[%d] %s: %s", index, name or "?", Keys(spell)))
						if not ns.TableIsSecret(spell) then
							for key, value in pairs(spell) do
								if type(value) == "table" and not ns.TableIsSecret(value) then
									Say("    ." .. tostring(key) .. ": " .. Keys(value))
									if type(value[1]) == "table" then
										Say("    ." .. tostring(key) .. "[1]: " .. Keys(value[1]))
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Session level: what one session object holds.
	if type(C_DamageMeter.GetCombatSessionFromType) == "function" then
		local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessions[1][2], typeEnum and typeEnum.DamageDone or 0)
		if ok and type(session) == "table" then
			Say("meter session: " .. Keys(session))
			local sources = not ns.TableIsSecret(session) and session.combatSources or nil
			if type(sources) == "table" and not ns.TableIsSecret(sources) and type(sources[1]) == "table" then
				Say("meter session source[1]: " .. Keys(sources[1]))
			end
		else
			Say("meter session: " .. Show(session))
		end
	end
end

-- Other routes to a single hit's size, beside the combat log event:
--  1. the client's own Combat Log chat tab ("Your Claw crits X for 123."),
--  2. the player's casts (UNIT_SPELLCAST_SUCCEEDED), to tie a hit to a spell.
local chatLines, castLines = 0, 0
local MAX_CHAT, MAX_CAST = 8, 4
local hookedChat = {}

local function CombatLogFrames()
	local frames = {}
	if type(COMBATLOG) == "table" then
		frames[#frames + 1] = COMBATLOG
	end
	local count = NUM_CHAT_WINDOWS or 10
	for index = 1, count do
		local chat = _G["ChatFrame" .. index]
		if chat and type(GetChatWindowInfo) == "function" then
			local ok, name = pcall(GetChatWindowInfo, index)
			if ok and type(name) == "string" and not ns.ValueIsSecret(name) and (name == COMBAT_LOG or name == "Combat Log") then
				frames[#frames + 1] = chat
			end
		end
	end
	return frames
end

local function DescribeText(text)
	if text == nil then
		return "nil"
	end
	if ns.ValueIsSecret(text) then
		return "<secret>"
	end
	if type(text) ~= "string" then
		return type(text)
	end
	return '"' .. text:sub(1, 140) .. '"'
end

local function WatchCombatLogChat()
	local frames = CombatLogFrames()
	if #frames == 0 then
		Say("combat log chat: no Combat Log tab found (open one: chat tab menu > New Window > Combat Log)")
		return
	end
	for _, chat in ipairs(frames) do
		local label = chat.GetName and chat:GetName() or "?"
		-- What is already in the tab: the newest line.
		if chat.GetNumMessages and chat.GetMessageInfo then
			local okCount, count = pcall(chat.GetNumMessages, chat)
			if okCount and type(count) == "number" and not ns.ValueIsSecret(count) and count > 0 then
				local okInfo, text = pcall(chat.GetMessageInfo, chat, count)
				Say(string.format("combat log chat %s: %s lines, last=%s", label, tostring(count), okInfo and DescribeText(text) or "error"))
			else
				Say(string.format("combat log chat %s: lines=%s", label, okCount and Show(count) or "error"))
			end
		end
		-- New lines as they arrive.
		if not hookedChat[chat] and type(hooksecurefunc) == "function" then
			hookedChat[chat] = true
			local inside = false
			hooksecurefunc(chat, "AddMessage", function(_, text)
				-- Say() writes to chat too; never react to our own line.
				if inside or not running or chatLines >= MAX_CHAT then
					return
				end
				inside = true
				chatLines = chatLines + 1
				pcall(Say, "combat log line: " .. DescribeText(text))
				inside = false
			end)
		end
	end
end

local function OnCast(unit, castGUID, spellID)
	if castLines >= MAX_CAST then
		return
	end
	castLines = castLines + 1
	local name = not ns.ValueIsSecret(spellID) and ns.SpellInfo(spellID) or nil
	Say(string.format("UNIT_SPELLCAST_SUCCEEDED unit=%s spellID=%s (%s) castGUID=%s",
		Show(unit), Show(spellID), name or "?", ns.ValueIsSecret(castGUID) and "<secret>" or "readable"))
end

local function OnUnitCombat(unit, action, flag, amount, school)
	if lines >= MAX_LINES then
		return
	end
	lines = lines + 1
	Say(string.format("UNIT_COMBAT unit=%s action=%s flag=%s amount=%s (%s) school=%s",
		Show(unit), Show(action), Show(flag), Show(amount), ns.ValueIsSecret(amount) and "secret" or type(amount), Show(school)))
end

function ns.Probe.Run()
	if running then
		Say("already running")
		return
	end
	running = true
	lines = 0
	if type(GetBuildInfo) == "function" then
		local version, build, _, interface = GetBuildInfo()
		Say(string.format("client %s build %s interface %s", Show(version), Show(build), Show(interface)))
	end
	Say("C_DamageMeter: " .. (C_DamageMeter and Keys(C_DamageMeter) or "nil"))
	Say("C_CombatLog: " .. (C_CombatLog and Keys(C_CombatLog) or "nil"))
	Say("CombatLogGetCurrentEventInfo: " .. type(CombatLogGetCurrentEventInfo))
	ns.Guard("Probe", MeterShape)

	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function(_, event, unit, action, flag, amount, school)
			if event == "UNIT_SPELLCAST_SUCCEEDED" then
				ns.Guard("Probe", function()
					OnCast(unit, action, flag)
				end)
				return
			end
			if event == "PLAYER_REGEN_ENABLED" then
				-- The meter fills in a moment after combat. Read it then, once per fight.
				if C_Timer and C_Timer.After then
					C_Timer.After(1.5, function()
						Say("combat ended, meter after the fight:")
						ns.Guard("Probe", MeterShape)
					end)
				end
				return
			end
			ns.Guard("Probe", function()
				OnUnitCombat(unit, action, flag, amount, school)
			end)
		end)
	end
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	chatLines, castLines = 0, 0
	if frame.RegisterUnitEvent then
		pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
	end
	ns.Guard("Probe", WatchCombatLogChat)
	local ok, err = pcall(frame.RegisterEvent, frame, "UNIT_COMBAT")
	if not ok then
		Say("UNIT_COMBAT register failed: " .. tostring(err))
		running = false
		return
	end
	Say(string.format("watching UNIT_COMBAT for %d s. Attack a target now (crits too).", WATCH_SECONDS))
	local function stop()
		frame:UnregisterEvent("UNIT_COMBAT")
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		pcall(frame.UnregisterEvent, frame, "UNIT_SPELLCAST_SUCCEEDED")
		running = false
		Say(string.format("done, %d UNIT_COMBAT line(s). Fight once more, then /cmf probe again for the meter fields.", lines))
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(WATCH_SECONDS, stop)
	end
end
