local files = {
	"CritMaticForever/Logic.lua",
	"CritMaticForever/Locale.lua",
	"CritMaticForever/Client.lua",
	"CritMaticForever/Database.lua",
	"CritMaticForever/Alerts.lua",
	"CritMaticForever/Recorder.lua",
	"CritMaticForever/CritLog.lua",
	"CritMaticForever/Tooltips.lua",
	"CritMaticForever/Options.lua",
	"CritMaticForever/Minimap.lua",
	"CritMaticForever/Commands.lua",
	"CritMaticForever/Init.lua",
}

local failed = false
for i = 1, #files do
	local chunk, err = loadfile(files[i])
	if not chunk then
		failed = true
		io.stderr:write(err .. "\n")
	end
end

if failed then
	os.exit(1)
end
print("syntax ok")
