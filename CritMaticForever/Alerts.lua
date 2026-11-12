local _, ns = ...

ns.Alerts = {}

local pool = {}
local active = {}
local ROW = 44
local lastSound = 0

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
		frame:SetPoint(point, UIParent, relative, x, y - (index - 1) * ROW)
	end
end

function ns.Alerts.Place()
	Place()
end

local function CreateAlert()
	local frame = CreateFrame("Frame", ns.WidgetName("Alert"), UIParent, "BackdropTemplate")
	frame:SetSize(280, 40)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	ns.ApplyBackdrop(frame, 0.07, 0.05, 0.05, 0.92)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(28, 28)
	frame.icon:SetPoint("LEFT", 8, 0)

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
	frame.text:SetPoint("RIGHT", -10, 0)
	frame.text:SetJustifyH("LEFT")
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
			y = (yOfs or 0) + (index - 1) * ROW,
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

local function ColoredText(payload)
	local spellR, spellG, spellB = ns.Database.Color("spell")
	local valueR, valueG, valueB = ns.Database.Color(payload.colorKey or "crit")
	local text = string.format(
		"|cff%s%s|r  |cff%s%s %s|r",
		ns.Logic.HexColor(spellR, spellG, spellB),
		payload.name or "?",
		ns.Logic.HexColor(valueR, valueG, valueB),
		payload.label or "",
		payload.amount or ""
	)
	if payload.previous then
		text = text .. "  |cff9a9a9a(" .. payload.previous .. ")|r"
	end
	return text
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
	frame.text:SetFont(font, size, flags or "OUTLINE")
	frame.text:SetText(ColoredText(payload))
	local width = frame.text:GetStringWidth() or 180
	frame:SetWidth(math.max(220, math.min(560, width + 58)))

	if payload.icon then
		frame.icon:SetTexture(payload.icon)
	else
		frame.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	end

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
