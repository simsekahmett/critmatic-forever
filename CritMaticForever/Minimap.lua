local _, ns = ...

ns.Minimap = {}

function ns.Minimap.Place()
	local button = ns.Minimap.button
	if not button or not Minimap then
		return
	end
	local angle = math.rad(ns.account.minimapAngle or 210)
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.Minimap.Update()
	local button = ns.Minimap.button
	if not button then
		return
	end
	if ns.Database.Get("minimap") then
		button:Show()
		ns.Minimap.Place()
	else
		button:Hide()
	end
end

function ns.Minimap.Init()
	if not Minimap then
		return
	end
	local button = CreateFrame("Button", "CritMaticForeverMinimapButton", Minimap)
	ns.Minimap.button = button
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 4) + 4)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(52, 52)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ns.Options.Toggle()
		else
			ns.CritLog.Toggle()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			local mx, my = Minimap:GetCenter()
			ns.account.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
			ns.Minimap.Place()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(ns.L.ADDON_TITLE, 1, 0.5, 0.15)
		GameTooltip:AddLine(ns.L.MINIMAP_TIP, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	ns.Minimap.Update()
end
