local _, ns = ...

ns.Options = {}

local SOUND_ORDER = { "none", "raid", "ready", "level", "quest" }
local pages = {}
local ignoreButtons = {}

local function SoundLabel(key)
	local labels = {
		none = ns.L.SOUND_NONE,
		raid = ns.L.SOUND_RAID,
		ready = ns.L.SOUND_READY,
		level = ns.L.SOUND_LEVEL,
		quest = ns.L.SOUND_QUEST,
	}
	return labels[key] or ns.L.SOUND_NONE
end

local function NextSound(key)
	for index, name in ipairs(SOUND_ORDER) do
		if name == key then
			return SOUND_ORDER[index % #SOUND_ORDER + 1]
		end
	end
	return SOUND_ORDER[1]
end

local function MakePage(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetPoint("TOPLEFT", 0, 0)
	page:SetPoint("TOPRIGHT", 0, 0)
	page.y = -4
	page.height = 8
	function page:Row(height)
		local current = self.y
		self.y = self.y - height - 8
		self.height = -self.y + 8
		return current
	end
	page:Hide()
	return page
end

local function Checkbox(page, key, text, onChanged)
	local y = page:Row(26)
	local box = CreateFrame("CheckButton", ns.WidgetName("Check"), page, "UICheckButtonTemplate")
	box:SetSize(26, 26)
	box:SetPoint("TOPLEFT", 4, y)
	box:SetChecked(ns.Database.Get(key) and true or false)
	local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", box, "RIGHT", 4, 0)
	label:SetPoint("RIGHT", -8, 0)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	box:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		ns.Database.Set(key, checked)
		if onChanged then
			onChanged(checked)
		end
	end)
	return box
end

local function Section(page, text)
	local y = page:Row(18)
	local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", 4, y)
	label:SetText(text)
	return label
end

local function Button(page, text, width, onClick)
	local y = page:Row(24)
	local button = CreateFrame("Button", ns.WidgetName("Button"), page, "UIPanelButtonTemplate")
	button:SetSize(width or 180, 22)
	button:SetPoint("TOPLEFT", 4, y)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Slider(page, key, text, minValue, maxValue, step)
	local y = page:Row(36)
	local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 4, y)
	local slider = CreateFrame("Slider", "CritMaticForeverSlider" .. key, page, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", 4, y - 16)
	slider:SetWidth(240)
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	local function paint(value)
		label:SetText(text .. ": " .. tostring(math.floor(value + 0.5)))
	end
	slider.silent = true
	slider:SetValue(ns.Database.Get(key) or minValue)
	slider.silent = false
	paint(slider:GetValue())
	slider:SetScript("OnValueChanged", function(self, value)
		if self.silent then
			return
		end
		local rounded = math.floor(value / step + 0.5) * step
		ns.Database.Set(key, rounded)
		paint(rounded)
	end)
	if slider.Text then
		slider.Text:SetText("")
	end
	return slider
end

local function CycleButton(page, key, caption)
	local button
	local function paint()
		button:SetText(caption .. ": " .. SoundLabel(ns.Database.Get(key)))
	end
	button = Button(page, caption, 280, function()
		ns.Database.Set(key, NextSound(ns.Database.Get(key)))
		paint()
		ns.Alerts.Play(ns.Database.Get(key), true)
	end)
	paint()
	return button
end

local function PaintSwatch(swatch, key)
	local r, g, b = ns.Database.Color(key)
	ns.Paint(swatch.tex, r, g, b, 1)
end

local function OpenPicker(key, swatch)
	local r, g, b = ns.Database.Color(key)
	local function apply(nr, ng, nb)
		if type(nr) ~= "number" then
			return
		end
		ns.Database.SetColor(key, nr, ng, nb)
		PaintSwatch(swatch, key)
		if ns.CritLog.IsShown() then
			ns.CritLog.Refresh()
		end
	end
	if not ColorPickerFrame then
		return
	end
	local info = {
		r = r,
		g = g,
		b = b,
		hasOpacity = false,
		swatchFunc = function()
			if ColorPickerFrame.GetColorRGB then
				apply(ColorPickerFrame:GetColorRGB())
			end
		end,
		cancelFunc = function(previous, g2, b2)
			if type(previous) == "table" then
				apply(previous.r, previous.g, previous.b)
			else
				apply(previous, g2, b2)
			end
		end,
	}
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow(info)
	else
		ColorPickerFrame.previousValues = { r = r, g = g, b = b }
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = info.swatchFunc
		ColorPickerFrame.cancelFunc = info.cancelFunc
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end
end

local function ColorRow(page, key, text)
	local y = page:Row(22)
	local swatch = CreateFrame("Button", nil, page)
	swatch:SetSize(18, 18)
	swatch:SetPoint("TOPLEFT", 6, y)
	swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
	swatch.tex:SetAllPoints()
	PaintSwatch(swatch, key)
	local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	label:SetText(text)
	swatch:SetScript("OnClick", function()
		OpenPicker(key, swatch)
	end)
end

function ns.Options.RefreshIgnore()
	local page = pages.ignore
	if not page then
		return
	end
	for index = 1, #ignoreButtons do
		ignoreButtons[index]:Hide()
	end
	local entries = {}
	for _, name in ipairs(ns.Database.IgnoredSpellList()) do
		entries[#entries + 1] = { kind = "spell", name = name }
	end
	for _, name in ipairs(ns.Database.IgnoredTargetList()) do
		entries[#entries + 1] = { kind = "target", name = name }
	end
	if #entries == 0 then
		page.empty:SetText(ns.L.NO_IGNORES)
		page.empty:Show()
		return
	end
	page.empty:Hide()
	for index, entry in ipairs(entries) do
		local button = ignoreButtons[index]
		if not button then
			button = CreateFrame("Button", ns.WidgetName("Ignore"), page, "UIPanelButtonTemplate")
			button:SetSize(280, 20)
			ignoreButtons[index] = button
		end
		local prefix = entry.kind == "target" and (ns.L.TARGET .. ": ") or ""
		button:SetText(prefix .. entry.name .. "  ×")
		button:SetPoint("TOPLEFT", 4, page.listTop - (index - 1) * 24)
		button:SetScript("OnClick", function()
			if entry.kind == "target" then
				ns.Database.ForgetTarget(entry.name)
			else
				ns.Database.ForgetSpell(entry.name)
			end
			ns.Options.RefreshIgnore()
			if ns.CritLog.IsShown() then
				ns.CritLog.Refresh()
			end
		end)
		button:Show()
	end
	if ns.Options.content and page:IsShown() then
		ns.Options.content:SetHeight(math.max((page.height or 0) + #entries * 24, 400))
	end
end

function ns.Options.RefreshStatus()
	local page = pages.about
	if not page or not page.status then
		return
	end
	local lines = {
		string.format(ns.L.VERSION, ns.version or ns.AddonVersion()),
		string.format(ns.L.RECORD_COUNT, ns.Database.RecordCount()),
	}
	if ns.Recorder.combatLogEnabled then
		lines[#lines + 1] = ns.L.STATUS_CLEU_ON
	elseif ns.Recorder.combatLogError then
		lines[#lines + 1] = string.format(ns.L.STATUS_CLEU_FAILED, ns.Recorder.combatLogError)
	else
		lines[#lines + 1] = ns.L.STATUS_CLEU_OFF
	end
	if ns.Recorder.hidden and ns.Recorder.hidden > 0 then
		lines[#lines + 1] = string.format(ns.L.HIDDEN_HITS, ns.Recorder.hidden)
	end
	if not C_DamageMeter then
		lines[#lines + 1] = ns.L.METER_UNAVAILABLE
	elseif ns.Recorder.session.secret then
		lines[#lines + 1] = ns.L.METER_SECRET
	elseif ns.Recorder.session.updated then
		lines[#lines + 1] = ns.L.METER_READY
	end
	page.status:SetText(table.concat(lines, "\n"))
end

function ns.Options.ShowPage(name)
	for key, page in pairs(pages) do
		page:SetShown(key == name)
	end
	local page = pages[name]
	if page and ns.Options.content then
		ns.Options.content:SetHeight(math.max(page.height or 400, 400))
		if ns.Options.scroll then
			ns.Options.scroll:SetVerticalScroll(0)
		end
	end
	if name == "ignore" then
		ns.Options.RefreshIgnore()
	elseif name == "about" then
		ns.Options.RefreshStatus()
	end
	for key, button in pairs(ns.Options.tabButtons or {}) do
		button:SetAlpha(key == name and 1 or 0.55)
	end
end

function ns.Options.ShowChangelog()
	local frame = ns.Options.changelog
	if not frame then
		return
	end
	frame.body:SetText(ns.L.CHANGELOG_BODY)
	frame:Show()
end

function ns.Options.Toggle()
	local frame = ns.Options.frame
	if not frame then
		return
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		ns.Options.ShowPage("general")
	end
end

function ns.Options.Init()
	local frame = CreateFrame("Frame", "CritMaticForeverOptions", UIParent, "BackdropTemplate")
	ns.Options.frame = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetSize(520, 560)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	ns.ApplyBackdrop(frame)
	ns.Database.ApplyPoint(frame, "options", { "CENTER", "CENTER", 0, 0 })
	frame:Hide()
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "CritMaticForeverOptions")
	end

	local titleButton = CreateFrame("Button", nil, frame)
	titleButton:SetPoint("TOPLEFT", 10, -8)
	titleButton:SetPoint("TOPRIGHT", -32, -8)
	titleButton:SetHeight(24)
	titleButton:RegisterForDrag("LeftButton")
	titleButton:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	titleButton:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		ns.Database.SavePoint("options", frame)
	end)
	local title = titleButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT")
	title:SetText(ns.L.ADDON_TITLE)

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -8, -8)
	close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	close.text:SetPoint("CENTER")
	close.text:SetText("×")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	ns.Options.tabButtons = {}
	local tabNames = {
		{ "general", ns.L.GENERAL },
		{ "alerts", ns.L.ALERTS },
		{ "social", ns.L.SOCIAL },
		{ "ignore", ns.L.IGNORE },
		{ "about", ns.L.ABOUT },
	}
	for index, info in ipairs(tabNames) do
		local button = CreateFrame("Button", ns.WidgetName("Tab"), frame, "UIPanelButtonTemplate")
		button:SetSize(96, 22)
		button:SetPoint("TOPLEFT", 12 + (index - 1) * 100, -36)
		button:SetText(info[2])
		button:SetScript("OnClick", function()
			ns.Options.ShowPage(info[1])
		end)
		ns.Options.tabButtons[info[1]] = button
	end

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 12, -66)
	scroll:SetPoint("BOTTOMRIGHT", -16, 12)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local nextScroll = self:GetVerticalScroll() - delta * 40
		if nextScroll < 0 then
			nextScroll = 0
		end
		local maxScroll = self:GetVerticalScrollRange()
		if nextScroll > maxScroll then
			nextScroll = maxScroll
		end
		self:SetVerticalScroll(nextScroll)
	end)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(480, 800)
	scroll:SetScrollChild(content)
	ns.Options.scroll = scroll
	ns.Options.content = content

	local general = MakePage(content)
	pages.general = general
	Section(general, ns.L.GENERAL)
	Checkbox(general, "trackDamage", ns.L.TRACK_DAMAGE)
	Checkbox(general, "trackHealing", ns.L.TRACK_HEALING)
	Checkbox(general, "trackCrit", ns.L.TRACK_CRITS)
	Checkbox(general, "trackHit", ns.L.TRACK_HITS)
	Checkbox(general, "trackPet", ns.L.TRACK_PETS)
	Checkbox(general, "trackFight", ns.L.TRACK_FIGHT)
	Checkbox(general, "countOverheal", ns.L.COUNT_OVERHEAL)
	Checkbox(general, "tooltip", ns.L.TOOLTIP)
	Checkbox(general, "tooltipEmpty", ns.L.TOOLTIP_EMPTY)
	Checkbox(general, "minimap", ns.L.MINIMAP_BUTTON, function()
		if ns.Minimap.Update then
			ns.Minimap.Update()
		end
	end)
	Checkbox(general, "showPets", ns.L.SHOW_PETS, function()
		if ns.CritLog.IsShown() then
			ns.CritLog.Refresh()
		end
	end)
	local minY = general:Row(24)
	local minLabel = general:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minLabel:SetPoint("TOPLEFT", 4, minY)
	minLabel:SetText(ns.L.MINIMUM)
	local minBox = CreateFrame("EditBox", "CritMaticForeverMinimum", general, "InputBoxTemplate")
	minBox:SetAutoFocus(false)
	minBox:SetSize(80, 20)
	minBox:SetPoint("TOPLEFT", 300, minY)
	minBox:SetText(tostring(ns.Database.Get("minimumAmount") or 0))
	minBox:SetScript("OnEnterPressed", function(self)
		local value = tonumber(self:GetText())
		if not value or value < 0 then
			value = 0
		end
		value = math.floor(value)
		ns.Database.Set("minimumAmount", value)
		self:SetText(tostring(value))
		self:ClearFocus()
	end)
	minBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	local alerts = MakePage(content)
	pages.alerts = alerts
	Section(alerts, ns.L.ALERTS)
	Checkbox(alerts, "alert", ns.L.ALERT_ENABLE)
	Checkbox(alerts, "alertFight", ns.L.ALERT_FIGHT)
	Checkbox(alerts, "lockAlert", ns.L.LOCK_ALERT)
	Slider(alerts, "alertSize", ns.L.ALERT_SIZE, 12, 32, 1)
	Slider(alerts, "alertHold", ns.L.ALERT_HOLD, 1, 8, 1)
	local timing
	timing = Button(alerts, ns.L.ALERT_TIMING, 280, function()
		local nextTiming = ns.Database.Get("alertTiming") == "instant" and "combatend" or "instant"
		ns.Database.Set("alertTiming", nextTiming)
		local label = nextTiming == "combatend" and ns.L.ALERT_COMBATEND or ns.L.ALERT_INSTANT
		timing:SetText(ns.L.ALERT_TIMING .. ": " .. label)
	end)
	do
		local label = ns.Database.Get("alertTiming") == "combatend" and ns.L.ALERT_COMBATEND or ns.L.ALERT_INSTANT
		timing:SetText(ns.L.ALERT_TIMING .. ": " .. label)
	end
	Section(alerts, ns.L.SOUND)
	Checkbox(alerts, "sound", ns.L.SOUND)
	CycleButton(alerts, "soundCrit", ns.L.SOUND_CRIT)
	CycleButton(alerts, "soundHit", ns.L.SOUND_HIT)
	CycleButton(alerts, "soundHealCrit", ns.L.SOUND_HEAL_CRIT)
	CycleButton(alerts, "soundHeal", ns.L.SOUND_HEAL)
	Button(alerts, ns.L.PREVIEW, 180, function()
		ns.Commands.Demo()
	end)
	Section(alerts, ns.L.COLORS)
	ColorRow(alerts, "spell", ns.L.COLOR_SPELL)
	ColorRow(alerts, "crit", ns.L.COLOR_CRIT)
	ColorRow(alerts, "hit", ns.L.COLOR_HIT)
	ColorRow(alerts, "critHeal", ns.L.COLOR_CRITHEAL)
	ColorRow(alerts, "heal", ns.L.COLOR_HEAL)
	ColorRow(alerts, "petCrit", ns.L.COLOR_PETCRIT)
	ColorRow(alerts, "petHit", ns.L.COLOR_PETHIT)

	local social = MakePage(content)
	pages.social = social
	Section(social, ns.L.SOCIAL)
	Checkbox(social, "chat", ns.L.CHAT)
	Checkbox(social, "chatSummary", ns.L.CHAT_SUMMARY)
	Slider(social, "summaryLimit", ns.L.SUMMARY_LIMIT, 1, 8, 1)
	Checkbox(social, "lockLog", ns.L.LOCK_LOG)

	local ignore = MakePage(content)
	pages.ignore = ignore
	Section(ignore, ns.L.IGNORED_SPELLS)
	local spellY = ignore:Row(24)
	local spellBox = CreateFrame("EditBox", "CritMaticForeverIgnoreSpell", ignore, "InputBoxTemplate")
	spellBox:SetAutoFocus(false)
	spellBox:SetSize(220, 20)
	spellBox:SetPoint("TOPLEFT", 8, spellY)
	local addSpell = CreateFrame("Button", ns.WidgetName("AddSpell"), ignore, "UIPanelButtonTemplate")
	addSpell:SetSize(80, 22)
	addSpell:SetPoint("LEFT", spellBox, "RIGHT", 8, 0)
	addSpell:SetText(ns.L.ADD)
	local function commitSpell()
		local clean = ns.Database.IgnoreSpell(spellBox:GetText())
		if clean then
			ns.Print(string.format(ns.L.IGNORE_ADDED, clean))
			spellBox:SetText("")
			ns.Options.RefreshIgnore()
		else
			ns.Print(ns.L.IGNORE_USAGE)
		end
	end
	addSpell:SetScript("OnClick", commitSpell)
	spellBox:SetScript("OnEnterPressed", function(self)
		commitSpell()
		self:ClearFocus()
	end)
	spellBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	Section(ignore, ns.L.IGNORED_TARGETS)
	local targetY = ignore:Row(24)
	local targetBox = CreateFrame("EditBox", "CritMaticForeverIgnoreTarget", ignore, "InputBoxTemplate")
	targetBox:SetAutoFocus(false)
	targetBox:SetSize(220, 20)
	targetBox:SetPoint("TOPLEFT", 8, targetY)
	local addTarget = CreateFrame("Button", ns.WidgetName("AddTarget"), ignore, "UIPanelButtonTemplate")
	addTarget:SetSize(80, 22)
	addTarget:SetPoint("LEFT", targetBox, "RIGHT", 8, 0)
	addTarget:SetText(ns.L.ADD)
	local function commitTarget()
		local clean = ns.Database.IgnoreTarget(targetBox:GetText())
		if clean then
			ns.Print(string.format(ns.L.TARGET_ADDED, clean))
			targetBox:SetText("")
			ns.Options.RefreshIgnore()
		else
			ns.Print(ns.L.TARGET_USAGE)
		end
	end
	addTarget:SetScript("OnClick", commitTarget)
	targetBox:SetScript("OnEnterPressed", function(self)
		commitTarget()
		self:ClearFocus()
	end)
	targetBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	Button(ignore, ns.L.WIPE_SPELLS, 220, function()
		ns.Database.WipeSpells()
		ns.Print(ns.L.WIPED)
		ns.Options.RefreshIgnore()
	end)
	Button(ignore, ns.L.WIPE_TARGETS, 220, function()
		ns.Database.WipeTargets()
		ns.Print(ns.L.WIPED)
		ns.Options.RefreshIgnore()
	end)
	ignore.listTop = ignore.y
	ignore.empty = ignore:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ignore.empty:SetPoint("TOPLEFT", 4, ignore.listTop)
	ignore.empty:SetText(ns.L.NO_IGNORES)

	local about = MakePage(content)
	pages.about = about
	Section(about, ns.L.ABOUT)
	local limitY = about:Row(150)
	local limitation = about:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	limitation:SetPoint("TOPLEFT", 4, limitY)
	limitation:SetWidth(450)
	limitation:SetJustifyH("LEFT")
	limitation:SetJustifyV("TOP")
	limitation:SetWordWrap(true)
	limitation:SetText(ns.L.LIMITATION)
	local statusY = about:Row(90)
	about.status = about:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	about.status:SetPoint("TOPLEFT", 4, statusY)
	about.status:SetWidth(450)
	about.status:SetJustifyH("LEFT")
	about.status:SetJustifyV("TOP")
	Button(about, ns.L.LOG, 180, function()
		ns.CritLog.Toggle()
	end)
	Button(about, ns.L.DEMO, 180, function()
		ns.Commands.Demo()
	end)
	Button(about, ns.L.CHANGELOG, 180, function()
		ns.Options.ShowChangelog()
	end)
	Button(about, ns.L.RESET_POS, 180, function()
		ns.Database.ResetPositions()
		if ns.CritLog.frame then
			ns.Database.ApplyPoint(ns.CritLog.frame, "log", { "CENTER", "CENTER", 0, 30 })
			ns.Database.ApplySize(ns.CritLog.frame, "log", 520, 420)
		end
		ns.Database.ApplyPoint(frame, "options", { "CENTER", "CENTER", 0, 0 })
		if ns.Minimap.Place then
			ns.Minimap.Place()
		end
		ns.Print(ns.L.RESET_POS_DONE)
	end)
	Button(about, ns.L.RESET, 180, function()
		if StaticPopup_Show then
			StaticPopup_Show("CRITMATICFOREVER_RESET")
		end
	end)

	local changelog = CreateFrame("Frame", "CritMaticForeverChangelog", UIParent, "BackdropTemplate")
	changelog:SetFrameStrata("FULLSCREEN_DIALOG")
	changelog:SetSize(460, 360)
	changelog:SetPoint("CENTER")
	changelog:SetClampedToScreen(true)
	ns.ApplyBackdrop(changelog, 0.05, 0.045, 0.06, 0.98)
	changelog:Hide()
	changelog.title = changelog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	changelog.title:SetPoint("TOP", 0, -16)
	changelog.title:SetText(ns.L.CHANGELOG_TITLE)
	changelog.body = changelog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	changelog.body:SetPoint("TOPLEFT", 18, -48)
	changelog.body:SetPoint("TOPRIGHT", -18, -48)
	changelog.body:SetJustifyH("LEFT")
	changelog.body:SetJustifyV("TOP")
	changelog.body:SetWordWrap(true)
	local ok = CreateFrame("Button", "CritMaticForeverChangelogOk", changelog, "UIPanelButtonTemplate")
	ok:SetSize(120, 24)
	ok:SetPoint("BOTTOM", 0, 16)
	ok:SetText(ns.L.CLOSE)
	ok:SetScript("OnClick", function()
		ns.account.lastSeenVersion = ns.version or ns.AddonVersion()
		changelog:Hide()
	end)
	ns.Options.changelog = changelog
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "CritMaticForeverChangelog")
	end

	local panel = CreateFrame("Frame")
	panel.name = ns.L.ADDON_TITLE
	local open = CreateFrame("Button", "CritMaticForeverOpenOptions", panel, "UIPanelButtonTemplate")
	open:SetSize(260, 26)
	open:SetPoint("TOPLEFT", 16, -16)
	open:SetText(ns.L.OPEN_OPTIONS)
	open:SetScript("OnClick", function()
		ns.Options.Toggle()
	end)
	local blurb = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	blurb:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12)
	blurb:SetWidth(420)
	blurb:SetJustifyH("LEFT")
	blurb:SetText(ns.L.WELCOME)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local okCategory, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
		if okCategory and category then
			pcall(Settings.RegisterAddOnCategory, category)
		end
	elseif type(InterfaceOptions_AddCategory) == "function" then
		InterfaceOptions_AddCategory(panel)
	end

	ns.Options.ShowPage("general")
end
