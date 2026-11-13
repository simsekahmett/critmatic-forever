local _, ns = ...

ns.CritLog = {
	mode = "damage",
	fightSide = "damage",
	sortKey = "left",
	sortDesc = true,
	query = "",
}

local rows = {}
local menuButtons = {}

local function DisplayName(record)
	local name = record.name or ("#" .. tostring(record.spellID or "?"))
	if record.isPet then
		return ns.L.PET .. ": " .. name
	end
	return name
end

local function Bucket(record, mode, fightSide)
	if not record then
		return nil
	end
	local heal = mode == "healing" or (mode == "fight" and fightSide == "heal")
	return heal and record.heal or record.damage
end

local function SessionMap(isPet, heal)
	local session = ns.Recorder.session
	if isPet then
		return heal and session.petHealing or session.petDamage
	end
	return heal and session.healing or session.damage
end

function ns.CritLog.BuildEntries()
	local mode = ns.CritLog.mode
	local fightSide = ns.CritLog.fightSide
	local heal = mode == "healing" or (mode == "fight" and fightSide == "heal")
	local query = (ns.CritLog.query or ""):lower()
	local showPets = ns.Database.Get("showPets")
	local merged = {}

	local function touch(spellID, isPet)
		local key = ns.Logic.RecordKey(spellID, isPet)
		if not merged[key] then
			merged[key] = {
				spellID = spellID,
				isPet = isPet and true or false,
				name = nil,
				icon = nil,
				left = 0,
				right = 0,
				rec = nil,
			}
		end
		return merged[key]
	end

	for _, record in pairs(ns.char.records) do
		if type(record) == "table" and record.spellID and (showPets or not record.isPet) then
			local entry = touch(record.spellID, record.isPet)
			entry.rec = record
			entry.name = DisplayName(record)
			entry.rawName = record.name
			entry.icon = record.icon
			local bucket = Bucket(record, mode, fightSide)
			if mode == "fight" then
				entry.right = bucket and bucket.fight or 0
			else
				entry.left = bucket and bucket.crit or 0
				entry.right = bucket and bucket.hit or 0
			end
			entry.critTarget = bucket and bucket.critTarget or nil
			entry.hitTarget = bucket and bucket.hitTarget or nil
			entry.critTime = bucket and bucket.critTime or nil
			entry.hitTime = bucket and bucket.hitTime or nil
			entry.prevCrit = bucket and bucket.prevCrit or 0
			entry.prevHit = bucket and bucket.prevHit or 0
		end
	end

	if mode == "fight" then
		local map = SessionMap(false, heal)
		for spellID, info in pairs(map or {}) do
			local entry = touch(spellID, false)
			entry.left = info.total or 0
			entry.rawName = entry.rawName or info.name
			entry.name = entry.name or info.name or ("#" .. tostring(spellID))
			entry.icon = entry.icon or info.icon
		end
		if showPets then
			local pets = SessionMap(true, heal)
			for spellID, info in pairs(pets or {}) do
				local entry = touch(spellID, true)
				entry.left = info.total or 0
				entry.rawName = entry.rawName or info.name
				entry.name = entry.name or (ns.L.PET .. ": " .. (info.name or ("#" .. tostring(spellID))))
				entry.icon = entry.icon or info.icon
			end
		end
	end

	local entries = {}
	for _, entry in pairs(merged) do
		local name = entry.name or ""
		local matches = query == "" or name:lower():find(query, 1, true)
		local hasValue = (entry.left or 0) > 0 or (entry.right or 0) > 0
		local rawName = entry.rawName or name
		if matches and hasValue and not ns.Database.IsIgnoredSpell(entry.spellID, rawName) then
			entries[#entries + 1] = entry
		end
	end
	return ns.Logic.SortEntries(entries, ns.CritLog.sortKey, ns.CritLog.sortDesc)
end

local function ShareText(entry)
	local L = ns.L
	local name = entry.name or "?"
	if ns.CritLog.mode == "fight" then
		local amount = (entry.right or 0) > 0 and entry.right or entry.left
		return string.format(L.SHARE_FIGHT, name, ns.FormatNumber(amount or 0))
	end
	local heal = ns.CritLog.mode == "healing"
	if (entry.left or 0) > 0 then
		local pattern = heal and L.SHARE_HEAL_CRIT or L.SHARE_CRIT
		return string.format(pattern, name, ns.FormatNumber(entry.left))
	end
	local pattern = heal and L.SHARE_HEAL or L.SHARE_HIT
	return string.format(pattern, name, ns.FormatNumber(entry.right or 0))
end

function ns.SendShare(channel, text, target)
	if not text or text == "" then
		return
	end
	if channel == "PARTY" and not (IsInGroup and IsInGroup()) then
		ns.Print(ns.L.NOT_IN_GROUP)
		return
	end
	if channel == "RAID" and not (IsInRaid and IsInRaid()) then
		ns.Print(ns.L.NOT_IN_RAID)
		return
	end
	if channel == "GUILD" and not (IsInGuild and IsInGuild()) then
		ns.Print(ns.L.NOT_IN_GUILD)
		return
	end
	if channel == "WHISPER" and (not target or target == "") then
		return
	end
	if type(SendChatMessage) ~= "function" then
		ns.Print(ns.L.SHARE_FAILED)
		return
	end
	local ok = pcall(SendChatMessage, text, channel, nil, target)
	if not ok then
		ns.Print(ns.L.SHARE_FAILED)
	end
end

local function HideMenu()
	if ns.CritLog.menu then
		ns.CritLog.menu:Hide()
	end
	if ns.CritLog.catcher then
		ns.CritLog.catcher:Hide()
	end
end

function ns.CritLog.ShowMenu(entry, anchor)
	local menu = ns.CritLog.menu
	if not menu or not entry then
		return
	end
	HideMenu()
	local L = ns.L
	local text = ShareText(entry)
	local items = {
		{ label = entry.name or L.SHARE, title = true },
		{ label = L.SHARE_SAY, click = function() ns.SendShare("SAY", text) end },
		{ label = L.SHARE_YELL, click = function() ns.SendShare("YELL", text) end },
		{ label = L.SHARE_PARTY, click = function() ns.SendShare("PARTY", text) end },
		{ label = L.SHARE_RAID, click = function() ns.SendShare("RAID", text) end },
		{ label = L.SHARE_GUILD, click = function() ns.SendShare("GUILD", text) end },
		{
			label = L.SHARE_WHISPER,
			click = function()
				ns.pendingShare = text
				if StaticPopup_Show then
					StaticPopup_Show("CRITMATICFOREVER_WHISPER")
				end
			end,
		},
		{
			label = L.IGNORE_SPELL,
			click = function()
				local clean = ns.Database.IgnoreSpell(entry.rec and entry.rec.name or entry.name, entry.spellID)
				if clean or entry.spellID then
					ns.Print(string.format(L.IGNORE_ADDED, clean or entry.name or "?"))
					ns.CritLog.Refresh()
				end
			end,
		},
		{
			label = L.CLEAR_SPELL,
			click = function()
				ns.Database.ForgetRecord(entry.spellID, entry.isPet)
				ns.Print(string.format(L.CLEARED_SPELL, entry.name or "?"))
				ns.CritLog.Refresh()
			end,
		},
	}

	for index = 1, #menuButtons do
		menuButtons[index]:Hide()
	end
	local y = -6
	for index, item in ipairs(items) do
		local button = menuButtons[index]
		if not button then
			button = CreateFrame("Button", nil, menu)
			button:SetHeight(22)
			button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			button.text:SetPoint("LEFT", 8, 0)
			button.text:SetPoint("RIGHT", -8, 0)
			button.text:SetJustifyH("LEFT")
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			ns.Paint(highlight, 1, 0.8, 0.3, 0.18)
			menuButtons[index] = button
		end
		button:SetPoint("TOPLEFT", 4, y)
		button:SetPoint("TOPRIGHT", -4, y)
		button.text:SetText(item.label)
		if item.title then
			button:Disable()
			button.text:SetTextColor(0.9, 0.75, 0.3)
			button:SetScript("OnClick", nil)
		else
			button:Enable()
			button.text:SetTextColor(0.95, 0.95, 0.95)
			button:SetScript("OnClick", function()
				HideMenu()
				if item.click then
					item.click()
				end
			end)
		end
		button:Show()
		y = y - 22
	end
	menu:SetSize(210, -y + 8)
	menu:ClearAllPoints()
	if anchor then
		menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	else
		menu:SetPoint("CENTER")
	end
	ns.CritLog.catcher:Show()
	menu:Show()
end

local function EnsureRow(index, parent)
	local row = rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, parent)
	row:SetHeight(30)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", 6, 0)
	row.leftText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.leftText:SetPoint("RIGHT", row, "RIGHT", -86, 0)
	row.leftText:SetWidth(78)
	row.leftText:SetJustifyH("RIGHT")
	-- The name takes whatever the number columns leave, at any window width.
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.leftText, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.rightText:SetPoint("RIGHT", -8, 0)
	row.rightText:SetWidth(78)
	row.rightText:SetJustifyH("RIGHT")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" and self.entry then
			ns.CritLog.ShowMenu(self.entry, self)
		end
	end)
	row:SetScript("OnEnter", function(self)
		ns.CritLog.ShowRowTooltip(self)
	end)
	row:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	rows[index] = row
	return row
end

function ns.CritLog.ShowRowTooltip(row)
	local entry = row.entry
	if not entry or not GameTooltip then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local r, g, b = ns.Database.Color("spell")
	GameTooltip:AddLine(entry.name or "?", r, g, b)
	local function add(label, value, previous, target, when, colorKey)
		if not value or value <= 0 then
			return
		end
		local cr, cg, cb = ns.Database.Color(colorKey)
		local line = ns.FormatNumber(value)
		if previous and previous > 0 then
			line = line .. "  (" .. ns.L.PREVIOUS .. " " .. ns.FormatNumber(previous) .. ")"
		end
		GameTooltip:AddDoubleLine(label, line, cr, cg, cb, cr, cg, cb)
		if target then
			GameTooltip:AddDoubleLine(ns.L.TARGET, target, 0.7, 0.7, 0.7, 0.85, 0.85, 0.85)
		end
		if type(when) == "number" and when > 0 and type(date) == "function" then
			GameTooltip:AddDoubleLine(ns.L.WHEN, date("%Y-%m-%d %H:%M", when), 0.7, 0.7, 0.7, 0.85, 0.85, 0.85)
		end
	end
	if ns.CritLog.mode == "fight" then
		add(ns.L.THIS_FIGHT, entry.left, nil, nil, nil, "hit")
		add(ns.L.BEST_FIGHT, entry.right, nil, nil, nil, "crit")
	elseif ns.CritLog.mode == "healing" then
		add(ns.L.BEST_HEAL_CRIT, entry.left, entry.prevCrit, entry.critTarget, entry.critTime, "critHeal")
		add(ns.L.BEST_HEAL, entry.right, entry.prevHit, entry.hitTarget, entry.hitTime, "heal")
	else
		add(ns.L.BEST_CRIT, entry.left, entry.prevCrit, entry.critTarget, entry.critTime, entry.isPet and "petCrit" or "crit")
		add(ns.L.BEST_HIT, entry.right, entry.prevHit, entry.hitTarget, entry.hitTime, entry.isPet and "petHit" or "hit")
	end
	GameTooltip:Show()
end

function ns.CritLog.Refresh()
	local frame = ns.CritLog.frame
	if not frame then
		return
	end
	local entries = ns.CritLog.BuildEntries()
	local content = ns.CritLog.content
	local width = ns.CritLog.scroll:GetWidth()
	if width < 10 then
		width = 400
	end
	content:SetWidth(width)
	local critColor = ns.CritLog.mode == "healing" and "critHeal" or "crit"
	local hitColor = ns.CritLog.mode == "healing" and "heal" or "hit"
	for index, entry in ipairs(entries) do
		local row = EnsureRow(index, content)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
		row:SetWidth(width)
		row.entry = entry
		ns.Paint(row.bg, 1, 1, 1, index % 2 == 0 and 0.04 or 0.015)
		if entry.icon then
			row.icon:SetTexture(entry.icon)
		else
			row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end
		local nr, ng, nb = ns.Database.Color("spell")
		row.name:SetText(entry.name or "?")
		row.name:SetTextColor(nr, ng, nb)
		local lr, lg, lb = ns.Database.Color(critColor)
		local rr, rg, rb = ns.Database.Color(hitColor)
		row.leftText:SetText((entry.left or 0) > 0 and ns.FormatNumber(entry.left) or "—")
		row.rightText:SetText((entry.right or 0) > 0 and ns.FormatNumber(entry.right) or "—")
		row.leftText:SetTextColor(lr, lg, lb)
		row.rightText:SetTextColor(rr, rg, rb)
		row:Show()
	end
	for index = #entries + 1, #rows do
		rows[index]:Hide()
		rows[index].entry = nil
	end
	content:SetHeight(math.max(#entries * 30, 1))
	ns.CritLog.empty:SetShown(#entries == 0)
	if ns.CritLog.mode == "fight" then
		ns.CritLog.empty:SetText(ns.L.EMPTY_FIGHT)
	else
		ns.CritLog.empty:SetText(ns.L.EMPTY_LOG)
	end

	local L = ns.L
	if ns.CritLog.mode == "fight" then
		ns.CritLog.leftHeader:SetText(L.THIS_FIGHT)
		ns.CritLog.rightHeader:SetText(L.BEST_FIGHT)
	elseif ns.CritLog.mode == "healing" then
		ns.CritLog.leftHeader:SetText(L.BEST_HEAL_CRIT)
		ns.CritLog.rightHeader:SetText(L.BEST_HEAL)
	else
		ns.CritLog.leftHeader:SetText(L.BEST_CRIT)
		ns.CritLog.rightHeader:SetText(L.BEST_HIT)
	end

	local status
	if ns.Recorder.combatLogEnabled then
		status = L.STATUS_CLEU_ON
	else
		status = L.STATUS_CLEU_OFF
	end
	if ns.Recorder.hidden and ns.Recorder.hidden > 0 then
		status = status .. "  " .. string.format(L.HIDDEN_HITS, ns.Recorder.hidden)
	end
	ns.CritLog.status:SetText(status)
	ns.CritLog.fightToggle:SetShown(ns.CritLog.mode == "fight")
	local side = ns.CritLog.fightSide == "heal" and L.HEAL or L.DAMAGE
	ns.CritLog.fightToggle:SetText(side)
end

function ns.CritLog.SetSort(key)
	if ns.CritLog.sortKey == key then
		ns.CritLog.sortDesc = not ns.CritLog.sortDesc
	else
		ns.CritLog.sortKey = key
		ns.CritLog.sortDesc = key ~= "name"
	end
	ns.CritLog.Refresh()
end

function ns.CritLog.SetMode(mode)
	ns.CritLog.mode = mode
	for name, button in pairs(ns.CritLog.tabs) do
		if name == mode then
			button:SetAlpha(1)
		else
			button:SetAlpha(0.55)
		end
	end
	ns.CritLog.Refresh()
end

function ns.CritLog.IsShown()
	return ns.CritLog.frame and ns.CritLog.frame:IsShown()
end

function ns.CritLog.Toggle()
	local frame = ns.CritLog.frame
	if not frame then
		return
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

local function HeaderButton(parent, text, width, justify, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 20)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.label:SetAllPoints()
	button.label:SetJustifyH(justify or "RIGHT")
	button.label:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

function ns.CritLog.Init()
	local frame = CreateFrame("Frame", "CritMaticForeverLog", UIParent, "BackdropTemplate")
	ns.CritLog.frame = frame
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(380, 260, 860, 720)
	elseif frame.SetMinResize then
		frame:SetMinResize(380, 260)
		frame:SetMaxResize(860, 720)
	end
	ns.ApplyBackdrop(frame, 0.05, 0.045, 0.06, 0.96)
	ns.Database.ApplySize(frame, "log", 520, 420)
	ns.Database.ApplyPoint(frame, "log", { "CENTER", "CENTER", 0, 30 })
	frame:Hide()
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "CritMaticForeverLog")
	end

	local titleButton = CreateFrame("Button", nil, frame)
	titleButton:SetPoint("TOPLEFT", 8, -6)
	titleButton:SetPoint("TOPRIGHT", -32, -6)
	titleButton:SetHeight(22)
	titleButton:RegisterForDrag("LeftButton")
	titleButton:SetScript("OnDragStart", function()
		if not ns.Database.Get("lockLog") then
			frame:StartMoving()
		end
	end)
	titleButton:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		ns.Database.SavePoint("log", frame)
	end)
	local title = titleButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT")
	title:SetText(ns.L.ADDON_TITLE)

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -6, -6)
	close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	close.text:SetPoint("CENTER")
	close.text:SetText("×")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	ns.CritLog.tabs = {}
	local function addTab(key, label, x)
		local button = CreateFrame("Button", ns.WidgetName("LogTab"), frame, "UIPanelButtonTemplate")
		button:SetSize(110, 22)
		button:SetPoint("TOPLEFT", x, -32)
		button:SetText(label)
		button:SetScript("OnClick", function()
			ns.CritLog.SetMode(key)
		end)
		ns.CritLog.tabs[key] = button
	end
	addTab("damage", ns.L.TAB_DAMAGE, 10)
	addTab("healing", ns.L.TAB_HEALING, 124)
	addTab("fight", ns.L.TAB_FIGHT, 238)

	local search = CreateFrame("EditBox", "CritMaticForeverSearch", frame, "InputBoxTemplate")
	search:SetAutoFocus(false)
	search:SetSize(160, 20)
	search:SetPoint("TOPLEFT", 16, -60)
	search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	search:SetScript("OnTextChanged", function(self)
		ns.CritLog.query = self:GetText() or ""
		ns.CritLog.Refresh()
	end)
	local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	searchLabel:SetPoint("LEFT", search, "RIGHT", 8, 0)
	searchLabel:SetText(ns.L.SEARCH)

	local fightToggle = CreateFrame("Button", "CritMaticForeverFightToggle", frame, "UIPanelButtonTemplate")
	fightToggle:SetSize(110, 20)
	fightToggle:SetPoint("TOPRIGHT", -28, -60)
	fightToggle:SetScript("OnClick", function()
		ns.CritLog.fightSide = ns.CritLog.fightSide == "heal" and "damage" or "heal"
		ns.CritLog.Refresh()
	end)
	ns.CritLog.fightToggle = fightToggle

	local spellHeader = HeaderButton(frame, ns.L.SPELL, 160, "LEFT", function()
		ns.CritLog.SetSort("name")
	end)
	spellHeader:SetPoint("TOPLEFT", 12, -86)
	local leftHeader = HeaderButton(frame, ns.L.BEST_CRIT, 90, "RIGHT", function()
		ns.CritLog.SetSort("left")
	end)
	leftHeader:SetPoint("TOPRIGHT", -96, -86)
	local rightHeader = HeaderButton(frame, ns.L.BEST_HIT, 80, "RIGHT", function()
		ns.CritLog.SetSort("right")
	end)
	rightHeader:SetPoint("TOPRIGHT", -12, -86)
	ns.CritLog.leftHeader = leftHeader.label
	ns.CritLog.rightHeader = rightHeader.label

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 8, -108)
	scroll:SetPoint("BOTTOMRIGHT", -12, 36)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local height = 30
		local nextScroll = self:GetVerticalScroll() - delta * height * 2
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
	content:SetSize(400, 1)
	scroll:SetScrollChild(content)
	ns.CritLog.scroll = scroll
	ns.CritLog.content = content

	local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 12, -16)
	empty:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -12, -16)
	empty:SetJustifyH("LEFT")
	empty:SetJustifyV("TOP")
	empty:SetWordWrap(true)
	ns.CritLog.empty = empty

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	status:SetPoint("BOTTOMLEFT", 12, 10)
	status:SetPoint("BOTTOMRIGHT", -28, 10)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	ns.CritLog.status = status

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip.text = grip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	grip.text:SetPoint("CENTER")
	grip.text:SetText("◢")
	grip:SetScript("OnMouseDown", function()
		if not ns.Database.Get("lockLog") then
			frame:StartSizing("BOTTOMRIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		ns.Database.SaveSize("log", frame)
		ns.CritLog.Refresh()
	end)

	local menu = CreateFrame("Frame", "CritMaticForeverMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	ns.ApplyBackdrop(menu, 0.06, 0.05, 0.07, 0.98)
	menu:Hide()
	ns.CritLog.menu = menu
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:Hide()
	catcher:SetScript("OnClick", HideMenu)
	ns.CritLog.catcher = catcher

	frame:SetScript("OnShow", function()
		ns.CritLog.SetMode(ns.CritLog.mode)
	end)
	-- Rows take the scroll width only in Refresh, so follow live resizing too.
	frame:SetScript("OnSizeChanged", function(self)
		if self:IsShown() then
			ns.CritLog.Refresh()
		end
	end)
	ns.CritLog.SetMode("damage")
end
