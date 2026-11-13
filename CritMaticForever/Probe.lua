-- /cmf probe: shows what this client hands to addons, so single-hit records can be
-- built on a source that really works. Prints only; it saves nothing.
local _, ns = ...

ns.Probe = {}

local WATCH_SECONDS = 60
local MAX_LINES = 20
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
			local first = type(spells) == "table" and not ns.TableIsSecret(spells) and spells[1] or nil
			if type(first) == "table" then
				Say("meter " .. info[1] .. " spell[1]: " .. Keys(first))
				for key, value in pairs(first) do
					if type(value) == "table" and not ns.TableIsSecret(value) then
						Say("  ." .. tostring(key) .. ": " .. Keys(value))
						if type(value[1]) == "table" then
							Say("  ." .. tostring(key) .. "[1]: " .. Keys(value[1]))
						end
					end
				end
				return
			end
		end
	end
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
	Say("client " .. Show(select(4, GetBuildInfo and GetBuildInfo())))
	Say("C_DamageMeter: " .. (C_DamageMeter and Keys(C_DamageMeter) or "nil"))
	Say("C_CombatLog: " .. (C_CombatLog and Keys(C_CombatLog) or "nil"))
	Say("CombatLogGetCurrentEventInfo: " .. type(CombatLogGetCurrentEventInfo))
	ns.Guard("Probe", MeterShape)

	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function(_, _, unit, action, flag, amount, school)
			ns.Guard("Probe", function()
				OnUnitCombat(unit, action, flag, amount, school)
			end)
		end)
	end
	local ok, err = pcall(frame.RegisterEvent, frame, "UNIT_COMBAT")
	if not ok then
		Say("UNIT_COMBAT register failed: " .. tostring(err))
		running = false
		return
	end
	Say(string.format("watching UNIT_COMBAT for %d s. Attack a target now (crits too).", WATCH_SECONDS))
	local function stop()
		frame:UnregisterEvent("UNIT_COMBAT")
		running = false
		Say(string.format("done, %d UNIT_COMBAT line(s). Fight once more, then /cmf probe again for the meter fields.", lines))
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(WATCH_SECONDS, stop)
	end
end
