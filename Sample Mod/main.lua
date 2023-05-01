--[[
	Sample mod
	@author		
	@version	
	@changelog	0.0 Initial version
]]--


-- Informations about the mod
local modName = "Sample Mod"
local modVersion = "V0.0"
local modConfig = "SampleMod"	-- for MCM config file
local modAuthor= "me"

--[[

	MWSE Lua ref https://mwse.github.io/MWSE/

]]--


--[[
	event handlers 
]]



--[[
	constructor
]]

local function initialize()
	-- code
end
event.register("initialized", initialize)


--[[
	mod config menu
]]

local function createtableVar(id)
	return mwse.mcm.createTableVariable{
		id = id,
		table = config
	}  
end

local function registerModConfig()
    local template = mwse.mcm.createTemplate(modName)
	template:saveOnClose(modConfig, config)
	
	local page = template:createPage()
	
	local catMain = page:createCategory(modName)
	catMain:createYesNoButton {
		label = "Enable " .. modName,
		description = "Allows you to Enable or Disable this mod",
		variable = createtableVar("modEnabled"),
		defaultSetting = true,
	}
	
	mwse.mcm.register(template)
end

event.register("modConfigReady", registerModConfig)
