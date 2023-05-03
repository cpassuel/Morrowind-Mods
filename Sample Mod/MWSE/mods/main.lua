--[[
	Sample mod
	@author		
	@version	
	@changelog	0.0 Initial version


Mod's folders structure

|-- Data Files
|	|-- Sample Mod.txt
|	|-- Sample Mod-metadata.toml
|	|-- MWSE
|	|	|-- config
|	|	|	|-- SampleMod.json
|	|	|-- mods
|	|	|	|-- Sample Mod
|	|	|	|	|-- main.lua
|	|	|	|-- i18n
|	|	|	|	|-- deu.lua
|	|	|	|	|-- eng.lua
|	|	|	|	|-- fra.lua

Folder i18n is only needed if you use mod translation

]]--


-- Informations about the mod
local modName = "Sample Mod"
local modVersion = "V0.0"
local modConfig = "SampleMod"	-- file name for MCM config file
local modAuthor= "me"


--[[

	MWSE Lua ref https://mwse.github.io/MWSE/

]]--


local function logInfo(s)
	-- https://www.lua.org/pil/5.2.html
	-- TODO get ride of string.format in calling 
	--mwse.log(string.format(fmt, unpack(arg)))

	--s = string.format('[' .. modName .. '] ' .. 'INFO ' .. fmt, unpack(arg))
	--mwse.log(s)
	mwse.log('[' .. modName .. '] ' .. 'INFO ' .. s)
end


--[[
	mod config
]]

-- list of values for dropdown menu
local modifierKeyOptions = {
	{ label = "NONE", value = 0 },
	{ label = "Cycle Spells", value = 1 },
	{ label = "Cycle Weapons", value = 2 },
}

-- Define mod config default values
local modDefaultConfig = {
	modEnabled = true,
	--
	timeScale = 25,
	mwCtrlAction = 0,
	myText = "Sample Mod",
}


-- Load config file, and fill in default values for missing elements.
local config = mwse.loadConfig(modConfig)
if (config == nil) then
	config = modDefaultConfig
else
	for key, value in pairs(modDefaultConfig) do
		if (config[key] == nil) then
			config[key] = value
		end
	end
end


--[[
	event handlers

]]

-- https://mwse.github.io/MWSE/events/mouseButtonDown/
local function onMouseButtonDown(e)
	-- only in game
	if tes3.menuMode() then
		return
	end
	
	-- mod must be enabled
	if not config.modEnabled then
		return
	end

	if (e.button ~= 3) then
		return
	end
	
	tes3.messageBox("Button #4 pressed")
end


-- https://mwse.github.io/MWSE/events/combatStarted/
local function onCombatStarted(e)
	-- mod must be enabled
	if not config.modEnabled then
		return
	end

	-- Some time it's useful to log info (for debug, ...)
	logInfo(string.format("onCombatStarted event - actor %d, target %d", e.actor.actorType, e.target.actorType))

	-- https://mwse.github.io/MWSE/references/actor-types/
	-- Need to check againt nil ?
	-- is the played attacked ? RE PHRASE
	if (e.actor.actorType ~= tes3.actorType.player) then
		tes3.messageBox("Help, I'm attacked")
	else
		tes3.messageBox("Beware, Scum !")
	end
	--tes3.messageBox("Help, I'm attacked - actor %d, target %d", e.actor.actorType  , e.target.actorType)
end


--[[
	constructor
]]

local function initialize()
	-- register needed events, better to use tes.event reference instead of the name https://mwse.github.io/MWSE/references/events/
	event.register(tes3.event.mouseButtonDown, onMouseButtonDown)
	event.register(tes3.event.combatStarted, onCombatStarted)
end
event.register("initialized", initialize)


--[[
	mod config menu

	https://easymcm.readthedocs.io/en/latest/
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
	
	local page = template:createSideBarPage{
		label = "Sidebar Page",
		description = modName .. " " .. modVersion
	}

	-- You can create categories to group settings

	local catMain = page:createCategory(modName)
	catMain:createYesNoButton {
		label = "Enable " .. modName,
		description = "Allows you to Enable or Disable this mod",
		variable = createtableVar("modEnabled"),
		defaultSetting = true,
	}

	local catSettings = page:createCategory("Mod Settings")
	catSettings:createSlider {
		label = "Time Scale",
		description = "Changes the speed of the day/night cycle.",
		min = 0,
		max = 50,
		step = 1,
		jump = 5,
		variable = createtableVar("timeScale")
	}

	catSettings:createDropdown {
		label = "Action for CTRL + MouseWheel",
		description = "Select the wanted action when using mouse wheel while holding CTRL key down",
		options = modifierKeyOptions,	  
		variable = createtableVar("mwCtrlAction"),
		defaultSetting = 0,
	}

	-- https://easymcm.readthedocs.io/en/latest/components/settings/classes/TextField.html
	catSettings:createTextField {
		label = "Text input",
		description = "Enter a text",
		variable = createtableVar("myText")
	}

	-- https://easymcm.readthedocs.io/en/latest/components/settings/classes/KeyBinder.html
	catSettings:createKeyBinder {
		label = "Assign Keybind",
		allowCombinations = true,
		defaultSetting = {
			keyCode = tes3.scanCode.k,
			--These default to false
			isShiftDown = true,
			isAltDown = false,
			isControlDown = false,
		},
		variable = createtableVar("myKeybind")
	}

	mwse.mcm.register(template)
end

event.register("modConfigReady", registerModConfig)
