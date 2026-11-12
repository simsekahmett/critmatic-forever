local addonName, ns = ...

ns.addonName = addonName

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name ~= addonName then
			return
		end
		ns.version = ns.AddonVersion()
		ns.Database.Init()
		ns.Alerts.Init()
		ns.Guard("CritLog", ns.CritLog.Init)
		ns.Guard("Tooltips", ns.Tooltips.Init)
		ns.Guard("Options", ns.Options.Init)
		ns.Guard("Minimap", ns.Minimap.Init)
		ns.Guard("Commands", ns.Commands.Init)
		ns.Recorder.Init()
		if ns.account.lastSeenVersion ~= ns.version and ns.Options.ShowChangelog then
			ns.Options.ShowChangelog()
		end
	elseif event == "PLAYER_LOGIN" then
		ns.Recorder.OnLogin()
	end
end)
