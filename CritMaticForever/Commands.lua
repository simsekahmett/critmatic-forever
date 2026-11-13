local _, ns = ...

ns.Commands = {}

local function ListNames(title, list)
	if #list == 0 then
		ns.Print(title .. " " .. ns.L.NO_IGNORES)
		return
	end
	ns.Print(title .. " " .. table.concat(list, ", "))
end

function ns.Commands.Demo()
	local amount = ns.FormatNumber(1523)
	local previous = ns.FormatNumber(1100)
	ns.Alerts.Show({
		name = "Fireball",
		label = ns.L.NEW_CRIT,
		amount = amount,
		previous = previous,
		colorKey = "crit",
		sound = ns.Database.Get("soundCrit"),
		chat = string.format(ns.L.CHAT_RECORD_PREV, ns.L.NEW_CRIT, "Fireball", amount, previous),
	}, true)
	if ns.Database.Get("chat") then
		ns.Print(string.format(ns.L.CHAT_RECORD_PREV, ns.L.NEW_CRIT, "Fireball", amount, previous))
	end
end

function ns.Commands.Status()
	ns.Print(string.format(ns.L.VERSION, ns.version or "?"))
	ns.Print(string.format(ns.L.CHARACTER, ns.charKey or "?"))
	ns.Print(string.format(ns.L.RECORD_COUNT, ns.Database.RecordCount()))
	if ns.Recorder.combatLogEnabled then
		ns.Print(ns.L.STATUS_CLEU_ON)
	elseif ns.Recorder.combatLogError then
		ns.Print(string.format(ns.L.STATUS_CLEU_FAILED, ns.Recorder.combatLogError))
	else
		ns.Print(ns.L.STATUS_CLEU_OFF)
	end
	if ns.Recorder.hidden and ns.Recorder.hidden > 0 then
		ns.Print(string.format(ns.L.HIDDEN_HITS, ns.Recorder.hidden))
	end
	if ns.Recorder.session.secret then
		ns.Print(ns.L.METER_SECRET)
	elseif ns.Recorder.session.updated then
		ns.Print(ns.L.METER_READY)
	elseif not C_DamageMeter then
		ns.Print(ns.L.METER_UNAVAILABLE)
	end
end

function ns.Commands.Handle(message)
	local raw = message or ""
	local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
	local command, rest = trimmed:match("^(%S+)%s*(.*)$")
	if not command or command == "" or command == "options" or command == "config" then
		ns.Options.Toggle()
		return
	end
	command = command:lower()
	rest = rest or ""

	if command == "log" or command == "critlog" then
		ns.CritLog.Toggle()
	elseif command == "changelog" then
		ns.Options.ShowChangelog()
	elseif command == "help" then
		for line in ns.L.HELP:gmatch("[^\n]+") do
			ns.Print(line)
		end
	elseif command == "ignore" then
		local clean = ns.Database.IgnoreSpell(rest)
		if clean then
			ns.Print(string.format(ns.L.IGNORE_ADDED, clean))
		else
			ns.Print(ns.L.IGNORE_USAGE)
		end
	elseif command == "unignore" or command == "removeignoredspell" then
		local clean = ns.Logic.NormalizeName(rest)
		if clean then
			ns.Database.ForgetSpell(clean)
			ns.Print(string.format(ns.L.FORGOT, clean))
		else
			ns.Print(ns.L.IGNORE_USAGE)
		end
	elseif command == "ignores" or command == "ignoredspells" then
		ListNames(ns.L.IGNORED_SPELLS, ns.Database.IgnoredSpellList())
	elseif command == "ignoretarget" then
		local clean = ns.Database.IgnoreTarget(rest)
		if clean then
			ns.Print(string.format(ns.L.TARGET_ADDED, clean))
		else
			ns.Print(ns.L.TARGET_USAGE)
		end
	elseif command == "unignoretarget" then
		local clean = ns.Logic.NormalizeName(rest)
		if clean then
			ns.Database.ForgetTarget(clean)
			ns.Print(string.format(ns.L.FORGOT, clean))
		end
	elseif command == "targets" or command == "ignoredtargets" then
		ListNames(ns.L.IGNORED_TARGETS, ns.Database.IgnoredTargetList())
	elseif command == "wipesells" or command == "wipespells" or command == "wipeignoredspells" then
		ns.Database.WipeSpells()
		ns.Print(ns.L.WIPED)
	elseif command == "wipetargets" or command == "wipeignoredtargets" then
		ns.Database.WipeTargets()
		ns.Print(ns.L.WIPED)
	elseif command == "reset" then
		if StaticPopup_Show then
			StaticPopup_Show("CRITMATICFOREVER_RESET")
		end
	elseif command == "resetpos" or command == "critlogdefaultpos" then
		ns.Database.ResetPositions()
		if ns.CritLog.frame then
			ns.Database.ApplyPoint(ns.CritLog.frame, "log", { "CENTER", "CENTER", 0, 30 })
			ns.Database.ApplySize(ns.CritLog.frame, "log", 520, 420)
		end
		if ns.Options.frame then
			ns.Database.ApplyPoint(ns.Options.frame, "options", { "CENTER", "CENTER", 0, 0 })
		end
		if ns.Minimap.Place then
			ns.Minimap.Place()
		end
		ns.Print(ns.L.RESET_POS_DONE)
	elseif command == "demo" or command == "preview" then
		ns.Commands.Demo()
	elseif command == "status" then
		ns.Commands.Status()
	elseif command == "probe" then
		if rest:lower() == "refilter" then
			ns.Probe.Refilter()
		else
			ns.Probe.Run()
		end
	else
		ns.Print(ns.L.UNKNOWN)
	end
end

local function Alias(key, slash, command)
	_G["SLASH_" .. key .. "1"] = slash
	SlashCmdList[key] = function(message)
		ns.Commands.Handle(command .. (message and message ~= "" and (" " .. message) or ""))
	end
end

function ns.Commands.Init()
	SLASH_CRITMATICFOREVER1 = "/cmf"
	SLASH_CRITMATICFOREVER2 = "/critmaticforever"
	SLASH_CRITMATICFOREVER3 = "/cm"
	SLASH_CRITMATICFOREVER4 = "/critmatic"
	SlashCmdList.CRITMATICFOREVER = function(message)
		ns.Commands.Handle(message)
	end

	Alias("CMFLOG", "/cmlog", "log")
	Alias("CMFCRITLOG", "/cmcritlog", "log")
	Alias("CMFCHANGELOG", "/cmchangelog", "changelog")
	Alias("CMFHELP", "/cmhelp", "help")
	Alias("CMFRESET", "/cmreset", "reset")
	Alias("CMFRESETPOS", "/cmcritlogdefaultpos", "resetpos")
	Alias("CMFIGNORE", "/cmignore", "ignore")
	Alias("CMFUNIGNORE", "/cmremoveignoredspell", "unignore")
	Alias("CMFIGNORES", "/cmignoredspells", "ignores")
	Alias("CMFIGNORETARGET", "/cmignoretarget", "ignoretarget")
	Alias("CMFWIPESPELLS", "/cmwipeignoredspells", "wipespells")
	Alias("CMFWIPETARGETS", "/cmwipeignoredtargets", "wipetargets")

	if not StaticPopupDialogs then
		return
	end
	StaticPopupDialogs.CRITMATICFOREVER_RESET = {
		text = ns.L.RESET_CONFIRM,
		button1 = YES or ns.L.YES,
		button2 = NO or ns.L.NO,
		OnAccept = function()
			ns.Database.ResetRecords()
			ns.Print(ns.L.RESET_DONE)
			if ns.CritLog.IsShown() then
				ns.CritLog.Refresh()
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopupDialogs.CRITMATICFOREVER_WHISPER = {
		text = ns.L.WHISPER_PROMPT,
		button1 = ACCEPT or ns.L.YES,
		button2 = CANCEL or ns.L.NO,
		hasEditBox = true,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		OnAccept = function(self)
			local edit = self.editBox or (self.GetEditBox and self:GetEditBox())
			local name = edit and edit:GetText() or ""
			ns.SendShare("WHISPER", ns.pendingShare, name)
		end,
		EditBoxOnEnterPressed = function(self)
			local popup = self:GetParent()
			local name = self:GetText()
			ns.SendShare("WHISPER", ns.pendingShare, name)
			if popup and popup.Hide then
				popup:Hide()
			end
		end,
	}
end
