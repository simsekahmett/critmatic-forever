local _, ns = ...

ns.Alerts = {}

local pool = {}
local active = {}
local GAP = 6
local lastSound = 0

local function TextHeight(size)
	return math.floor(size + 8 + 0.5)
end

-- Offset of a line from the top of the stack: sum of the lines above it.
local function StackOffset(index)
	local offset = 0
	for above = 1, index - 1 do
		local frame = active[above]
		offset = offset + (frame and frame:GetHeight() or 40) + GAP
	end
	return offset
end

local function Release(frame)
	frame:Hide()
	if frame.fade then
		frame.fade:Stop()
	end
	for index = #active, 1, -1 do
		if active[index] == frame then
			table.remove(active, index)
		end
	end
	pool[#pool + 1] = frame
end

local function Place()
	local saved = ns.account.positions.alert
	local point = saved and saved.point or "TOP"
	local relative = saved and saved.relativePoint or "TOP"
	local x = saved and saved.x or 0
	local y = saved and saved.y or -170
	for index, frame in ipairs(active) do
		frame.stackIndex = index
		frame:ClearAllPoints()
		frame:SetPoint(point, UIParent, relative, x, y - StackOffset(index))
	end
end

function ns.Alerts.Place()
	Place()
end

local function CreateAlert()
	local frame = CreateFrame("Frame", ns.WidgetName("Alert"), UIParent)
	frame:SetSize(20, 24)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	if frame.SetClipsChildren then
		frame:SetClipsChildren(false)
	end
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.text:SetPoint("CENTER")
	frame.text:SetJustifyH("CENTER")
	frame.text:SetWordWrap(false)

	local fade = frame:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetDuration(0.45)
	alpha:SetStartDelay(4)
	fade:SetScript("OnFinished", function()
		Release(frame)
		Place()
	end)
	frame.fade = fade
	frame.fadeAnim = alpha

	frame:SetScript("OnDragStart", function(self)
		if ns.Database.Get("lockAlert") then
			return
		end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
		local index = self.stackIndex or 1
		ns.account.positions.alert = {
			point = point,
			relativePoint = relativePoint or point,
			x = xOfs or 0,
			y = (yOfs or 0) + StackOffset(index),
		}
		Place()
	end)
	frame:Hide()
	return frame
end

function ns.Alerts.Play(key, force)
	if not key or key == "none" then
		return
	end
	if not force and not ns.Database.Get("sound") then
		return
	end
	local now = GetTime and GetTime() or 0
	local throttle = ns.Database.Get("soundThrottle") or 2
	if not force and (now - lastSound) < throttle then
		return
	end
	local soundID = ns.ResolveSound(key)
	if not soundID or type(PlaySound) ~= "function" then
		return
	end
	local ok = pcall(PlaySound, soundID, "Master")
	if ok then
		lastSound = now
	end
end

local function ShowPrevious(payload)
	if ns.ValueIsSecret(payload.secretPrevious) then
		return payload.secretPrevious
	end
	if type(payload.previous) == "number" and payload.previous > 0 then
		return payload.previous
	end
	if type(payload.previous) == "string" and payload.previous ~= "" then
		return payload.previous
	end
	return nil
end

local function WriteLine(fontstring, payload)
	local spellHex = ns.Logic.HexColor(ns.Database.Color("spell"))
	local valueHex = ns.Logic.HexColor(ns.Database.Color(payload.colorKey or "crit"))
	local name = payload.name or "?"
	local label = payload.label or ""
	local amount = payload.secretAmount
	if amount == nil then
		amount = payload.amount or ""
	end
	local previous = ShowPrevious(payload)
	local body
	if payload.critFeed then
		body = ns.FormatLine("|cff" .. spellHex .. "★ %s|r |cff" .. valueHex .. "crit %s|r", name, amount)
		previous = nil
	else
		body = ns.FormatLine("|cff" .. valueHex .. "%s:|r |cff" .. spellHex .. "%s|r — %s", label, name, amount)
	end
	local wrote = false
	if previous ~= nil and body ~= nil then
		local suffix = ns.FormatLine("|cff9a9a9a" .. (ns.L.CHAT_PREVIOUS or "(previous %s)") .. "|r", previous)
		wrote = suffix ~= nil and pcall(fontstring.SetFormattedText, fontstring, "%s %s", body, suffix)
	end
	if not wrote and body ~= nil then
		wrote = pcall(fontstring.SetFormattedText, fontstring, "%s", body)
	end
	if not wrote then
		pcall(fontstring.SetText, fontstring, name)
	end
end

function ns.Alerts.Show(payload, forceSound)
	if not payload then
		return
	end
	local frame = table.remove(pool)
	if not frame then
		frame = CreateAlert()
	end
	if #active >= 4 then
		Release(active[#active])
	end
	table.insert(active, 1, frame)

	local font, _, flags = GameFontNormal:GetFont()
	local size = ns.Database.Get("alertSize") or 18
	flags = flags or "OUTLINE"
	local height = TextHeight(size)
	frame.text:ClearAllPoints()
	frame.text:SetPoint("CENTER")
	frame.text:SetFont(font, size, flags)
	frame.text:SetJustifyH("CENTER")
	frame.text:SetWordWrap(false)
	WriteLine(frame.text, payload)
	local width = 32
	local widthOk, measured = pcall(function()
		if frame.text.GetUnboundedStringWidth then
			return frame.text:GetUnboundedStringWidth()
		end
		return frame.text:GetStringWidth()
	end)
	if widthOk and type(measured) == "number" and not ns.ValueIsSecret(measured) and measured > 1 then
		width = measured + 8
	end
	frame:SetSize(width, height)

	frame.fadeAnim:SetStartDelay(ns.Database.Get("alertHold") or 4)
	frame.fade:Stop()
	frame:SetAlpha(1)
	frame:Show()
	Place()
	frame.fade:Play()
	ns.Alerts.Play(payload.sound, forceSound)
end

function ns.Alerts.Init()
	-- Frames are created on demand so a missing font does not block login.
end
