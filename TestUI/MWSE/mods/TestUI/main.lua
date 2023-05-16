--[[
	TestUI
	@author		
	@version	0.00
	@changelog	0.00 Initial version

	The goal of this mod is to give a starting template with some examples to create a MWSE Lua mod
	with a Mod Config Menu (MCM) for Morrowind. It tries to use the best practices.

	The mod itself doesn't do much, it captures CombatStarted and MouseButtonDown to show how to manage events.
	It is probably not compatible with OpenMW

	MWSE Lua ref https://mwse.github.io/MWSE/
	Lua https://www.lua.org/docs.html
	    https://www.lua.org/cgi-bin/demo
		
	Mod folders structure

	|-- Data Files
	|	|-- <modName>.txt
	|	|-- <modName>-metadata.toml
	|	|-- MWSE
	|	|	|-- config
	|	|	|	|-- <modName>.json
	|	|	|-- mods
	|	|	|	|-- <modName>
	|	|	|	|	|-- main.lua
	|	|	|	|-- i18n
	|	|	|	|	|-- deu.lua
	|	|	|	|	|-- eng.lua
	|	|	|	|	|-- fra.lua

	Folder i18n is only needed if you use mod translation
	<modName>.txt is an optional readme text file, its location is not explictely defined

	You can find more lua mod examples at https://github.com/Hrnchamd/MWSE-Lua-mods
	You can also check my mod Morrowind Mouse Control at https://www.nexusmods.com/morrowind/mods/48254

	DEBUG
	You can add logDebug to log infos in MWSE.log by setting debugMode to true in the config <modName>.json. Otherwise it should be set to false.
	In case of issues with you mod, check MWSE.log flie in Morrowind folder, you will see^

	Parts of the code with inspired from SecurityEnhanced
]]--


-- Adapts settings to your mod
local modName = "TestUI"	-- MUST be same as the mod folder 
local modVersion = "V0.00"
local modConfig = modName	-- file name for MCM config file
local modAuthor= "me"


-- Keep track of all the GUI IDs we care about.
local GUIID_MenuContents = nil
local GUIID_TestUI_ContentBlock = nil
local GUIID_TestUI_NameLabel = nil


-- keep information about the target (container/door trapped or locked or both)
local currentTarget = {
	target = nil,
	isTrapped = false,
	isLocked = false,
}


--[[

	Mod translation
	https://mwse.github.io/MWSE/guides/mod-translations/
	
	Translation in not complete because I'm lazy, it's just to show how it works

]]--

-- returns a table of transation, you acces a translation by its key: i18n("HELP_ATTACKED")
-- FIXME: RROR: Failed to run mod initialization script 'testui.mwse.mods.testui.main': Data Files\MWSE\core\initialize.lua:229: Could not load any valid i18n files.
local i18n = mwse.loadTranslations(modName)


--[[

	mod config

]]

-- list of values for the MCM dropdown menu
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
	mwCtrlAction = modifierKeyOptions[1]["value"],	-- BEWARE table index start at 1 so I selected the first value (NONE)
	myText = "my sample text",
	debugMode = true,	-- true for debugging purpose should be false for mod release, it could be a MCM option, currently you have to change its value in the config file
	--
	useWorstCondition = true,	-- maybe put a . state value worst, don't care, best
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

		Helper functions

]]--


--- Reset the current target to no target
local function resetCurrentTarget()
	currentTarget.target = nil
	currentTarget.isTrapped = false
	currentTarget.isLocked = false
end


--- Log a string as Info level
-- @param msg string to be logged as Info in MWSE.log
local function logInfo(msg)
	-- https://www.lua.org/pil/5.2.html
	-- TODO get ride of string.format in calling 
	--s = string.format('[' .. modName .. '] ' .. 'INFO ' .. fmt, unpack(arg))
	--mwse.log(s)
	mwse.log('[' .. modName .. '] ' .. 'INFO ' .. msg)
end


--- Log a message to MWSE.log if debug mode is enabled
-- @param msg string to be logged as Info in MWSE.log
local function logDebug(msg)
	if (config.debugMode) then
		mwse.log('[' .. modName .. '] ' .. 'DEBUG ' .. msg)
	end
end


--- Search for probe in inventory
-- @return a table
local function searchProbes()
	local probesTable = {}

	local inventory = tes3.player.object.inventory
	-- TODO refactor pour chercher les lockpick
	for _, v in pairs(inventory) do
		if v.object.objectType == tes3.objectType.probe then
			-- TODO how to get condition of the item ? https://mwse.github.io/MWSE/types/tes3itemData/
			-- https://mwse.github.io/MWSE/types/tes3itemData/
			local probe = v.object
			local probeName = probe.name
			local condition	= 0

			-- Seems to have variables once equipped
			-- https://mwse.github.io/MWSE/types/tes3itemStack/#object
			if (v.variables) then
				-- No need to iterate over all items in stack as they all have the same condition
				condition = v.variables[1].condition
			end
			-- TEST il peut avoir plusieurs items => c'est pourquoi il faut parcourir la liste
			-- mais dans une stack, tous les items ont la même condition => donc le 1er devrait suffir
			if (v.variables) then
				for _, data in pairs(v.variables) do
					logDebug(string.format("data probe condition %d" , data.condition))
				end
			end

			-- TODO Refactor code to update once
			if (probesTable[probeName] == nil) then
				probesTable[probeName]={}
				-- update
				probesTable[probeName].condition = condition
				probesTable[probeName].probe = probe
				logDebug(string.format("Adding probe %s - %p - condition %d",probeName, probe, condition))
			else
				-- check condition of the stored probe
				if config.useWorstCondition then
					if condition < probesTable[probe.name].condition then
						-- update
						logDebug(string.format("Updating lower probe %s - %p - condition %d",probeName, probe, condition))
						probesTable[probeName].condition = condition
						probesTable[probeName].probe = probe
					end
				else
					if condition > probesTable[probeName].condition then
						-- update
						logDebug(string.format("Updating better probe %s - %p - condition %d",probe.name, probe, condition))
						probesTable[probe.name].condition = condition
						probesTable[probe.name].probe = probe
					end
				end
			end
		end
	end

	return probesTable
end


--[[

	UI functions

	+--------------------------+
	|+------------------------+|
	||        Label           ||
	|+------------------------+|
	|+------------------------+|
	||     Tools block        ||
	||+----------------------+||
	|||     item block       |||
	||+----------------------+||
	||+----------------------+||
	|||     item block       |||
	||+----------------------+||
	|+------------------------+|
	+--------------------------+

TODO hide instead of destroying ?
Populate probe: besoin uniquement de la position de la target (position fixé dans le createWindow) ?
Populate lockpick: besoon du lock et des stats player pour filter les lock utiles (mettre une option pour afficher tout ?)
s'il y a une clé pour le lock et que le joueur l'a, ne pas afficher la fenetre ?
check if a tool is already equipped before displaying the window

Options
hideChance	don't display the chance to unlock with the lockpick
selectWorstCondition select tools with the worst condition in order to minimize used tools in the inventory

Object loocked/trapped actived
	afficher le menu de selection outil
	gerer la selection
	fermer le menu
	equiper l'outil

Ne plus afficher le menu à moins que l'outil soit cassé
Ou disarm réussi mais loocked => afficher menu

Comment detecter que le trap est disarmed https://mwse.github.io/MWSE/events/trapDisarm/
]]


-- @param isProbe true if we need to select a probe, false for a lockpick
local function createWindow(isProbe)
	if tes3.menuMode() then
		return
	end	

	if (tes3ui.findMenu(GUIID_MenuContents)) then
        return
    end

	-- Create window and frame
	local menu = tes3ui.createMenu{ id = GUIID_MenuContents, fixedFrame = true }

	-- To avoid low contrast, text input windows should not use menu transparency settings
	menu.alpha = 1.0

	-- Create layout
	-- TODO change the text for probe
	local text = ""
	if isProbe then
		text = "Select a probe"
	else
		text = "Select a lockpick"
	end
	local input_label = menu:createLabel{ text = text }
	input_label.borderBottom = 5
	input_label.color = tes3ui.getPalette("header_color")
	-- TODO add a block in labelblock to center the text
	--input_block.childAlignX = 0.5  -- centre content alignment
	
	local input_block = menu:createBlock{}
	input_block.autoWidth = true
	--input_block.width = 300
	input_block.autoHeight = true
	--input_block.childAlignX = 0.5  -- centre content alignment
	input_block.flowDirection = "top_to_bottom"

	local objectTypeToSearch = nil
	if (isProbe) then
		objectTypeToSearch = tes3.objectType.probe
	else
		objectTypeToSearch = tes3.objectType.lockpick
	end
	-- https://mwse.github.io/MWSE/types/tes3lockNode/

	local objectTypeToSearh
	local inventory = tes3.player.object.inventory
	for _, v in pairs(inventory) do
        if v.object.objectType == objectTypeToSearch then
			-- Our container block for this item.
			local block = input_block:createBlock({})
			block.flowDirection = "left_to_right"
			block.autoWidth = true
			block.autoHeight = true
			block.paddingAllSides = 3

			-- TODO filter on quality for lockpick
			-- TODO filtrer par type de lockpick/name et maxCondition (ATTENTION propriété de l'objet lui même, pas du parent)

			-- Store the item/count on the block for later logic.
			-- block:setPropertyObject("QuickLoot:Item", item)
			-- block:setPropertyInt("QuickLoot:Count", math.abs(stack.count))
			-- block:setPropertyInt("QuickLoot:Value", item.value)

			-- Item icon.
			--local icon = block:createImage({id = GUIID_QuickLoot_ContentBlock_ItemIcon, path = "icons\\" .. item.icon})
			local icon = block:createImage({id = GUIID_QuickLoot_ContentBlock_ItemIcon, path = "icons\\" .. v.object.icon})
			icon.borderRight = 5

			-- https://mwse.github.io/MWSE/types/tes3lockpick/
			-- 
			-- Label text
			local labelText = v.object.name .. " " .. " (12 %)"
		
			--local label = block:createLabel({id = GUIID_QuickLoot_ContentBlock_ItemLabel, text = labelText})
			local label = block:createLabel({text = labelText})
			label.absolutePosAlignY = 0.5
		end
	end
	-- TODO Set position

	-- Final setup
	menu:updateLayout()
end


local function destroyWindow()
	local menu = tes3ui.findMenu(GUIID_MenuContents)

	if (menu) then
        tes3ui.leaveMenuMode()
        menu:destroy()
    end
end


--[[

	event handlers

]]

---
-- https://mwse.github.io/MWSE/events/activate/
-- @param e event object
local function onActivate(e)
	--logDebug(string.format("Activated"))
	logDebug(string.format("Activated %s", e.target.object.name))
end


--- event when you try do disarm something
-- https://mwse.github.io/MWSE/events/trapDisarm/
-- @param e event object
local function onTrapDisarm(e)
	-- TODO use e.lockData.trap
	-- TODO comment voir si désarmé ????
	-- Ne fonctionne pas car c'est avant l'action de disarm => vérifier l'état du locknode dans activationchanged
	logDebug(string.format("Event trapDisarm %s", tostring(e.lockData.trap.deleted)))
end


--- You NEED to destroy your menu when entering menu mode to avoid locking the UI
-- https://mwse.github.io/MWSE/events/menuEnter/
-- @param e event object
local function onMenuEnter(e)
	logDebug(string.format("MenuEnter"))
	destroyWindow()
end


--- Manage unequipped event
-- https://mwse.github.io/MWSE/events/unequipped/
-- @parma
local function onUnequipped(e)
	tes3.messageBox("Unequipped")
	logDebug(string.format("Unequipped %s", e.item.name))
	-- event unequipped when the probe/locpick is completly used (condition = 0)
	-- [TestUI] DEBUG Unequipped Apprentice's Probe
end


--- Callback function for MouseButtonDown event
-- https://mwse.github.io/MWSE/events/mouseButtonDown/
-- @param e event
local function onMouseButtonDown(e)
	-- only in game
	if tes3.menuMode() then
		return
	end
	
	-- mod must be enabled
	if not config.modEnabled then
		return
	end

	if (e.button == 3) then
		tes3.messageBox(i18n("BUTTON_4"))
	end
	
	if (e.button == 4) then
		tes3.messageBox(i18n("BUTTON_5"))
	end
end


--- Event fired when target changes or target is disarmed or unlocked
-- https://mwse.github.io/MWSE/events/activationTargetChanged/
-- @param e event object
local function onActivationTargetChanged(e)
	if not config.modEnabled then
		return
	end

	if e.current == nil then
		logDebug(string.format("onActivationTargetChanged - No object"))
		resetCurrentTarget()
		destroyWindow()
		return
	end

	-- https://mwse.github.io/MWSE/apis/tes3/#tes3getequippeditem
	local equippedProbe = tes3.getEquippedItem({
        actor = tes3.player,
        objectType = tes3.objectType.probe
    })
	-- TODO more intelligent test: depends on the status of the target locked => test on lockpick, trapped => test on probe
	if (equippedProbe ~= nil) then
		logDebug(string.format("Probe already equipped"))
		return
	end

	-- 
	if (currentTarget.target == e.current) then
		logDebug(string.format("onActivationTargetChanged with same target %s - %p", e.current, e.current))
		-- same target so it is a door or a container
		-- actual vs old status
		if e.current.lockNode == nil then
			-- TODO remove this part
			-- FIXME shoudln't happen
			logDebug(string.format("onActivationTargetChanged but locknode nil with same target %s - %p", e.current, e.current))
		else
			if currentTarget.isTrapped and (e.current.lockNode.trap == nil) then
				-- trap disarmed
				logDebug(string.format("Trap disarmed on %s (%p)", currentTarget.target, currentTarget.target))
				currentTarget.isTrapped = false
				-- TODO update Window instead
				destroyWindow()		-- Not necessary as the window is closed after selection
				createWindow(false)
			end
		end
	else
		-- TODO check objectType
		if (e.current.object.objectType == tes3.objectType.container) or (e.current.object.objectType == tes3.objectType.door) then
			local lockNode = e.current.lockNode
			if lockNode ~= nil then
				-- lockNode not nil => locked, trapped or both
				currentTarget.target = e.current

				if lockNode.locked then
					currentTarget.isLocked = true
				end
	
				if (lockNode.trap ~= nil) then
					currentTarget.isTrapped = true
				end
			end
		end
	end

	if currentTarget.target == nil then
		resetCurrentTarget()	-- may be not necessary
		destroyWindow()
		return
	end

	logDebug(string.format("Container/door %s (%p) - trapped %s, locked %s", currentTarget.target, currentTarget.target, currentTarget.isTrapped, currentTarget.isLocked))

	-- TODO destroy UI when object changes
	-- TODO store locknode for locklevel

	searchProbes()
					
	if currentTarget.isTrapped then
		tes3.messageBox("Trapped")
		createWindow(true)
	else
		tes3.messageBox("Locked")
		createWindow(false)
	end
end


--- Callback function for CombatStarted event
-- https://mwse.github.io/MWSE/events/combatStarted/
-- @param e event object
local function onCombatStarted(e)
	-- mod must be enabled
	if not config.modEnabled then
		return
	end

	-- Sometimes it's useful to log debug info (only logged when debugMode is true)
	logDebug(string.format("onCombatStarted event - actor %d, target %d", e.actor.actorType, e.target.actorType))

	-- https://mwse.github.io/MWSE/references/actor-types/
	-- is the attacking actor is not the player ?
	if (e.actor.actorType ~= tes3.actorType.player) then
		tes3.messageBox(i18n("HELP_ATTACKED"))
	else
		tes3.messageBox(i18n("BEWARE_SCUM"))
	end
end


--[[
	constructor
]]

local function initialize()
	-- registers needed events, better to use tes.event reference instead of the name https://mwse.github.io/MWSE/references/events/
	event.register(tes3.event.mouseButtonDown, onMouseButtonDown)
	--event.register(tes3.event.combatStarted, onCombatStarted)
	event.register(tes3.event.activationTargetChanged, onActivationTargetChanged)

	event.register(tes3.event.unequipped, onUnequipped)
	event.register(tes3.event.menuEnter, onMenuEnter)
	--event.register(tes3.event.activate, onActivate)
	--event.register(tes3.event.trapDisarm, onTrapDisarm)

	GUIID_MenuContents = tes3ui.registerID("TestUI_MenuContents")
	GUIID_TestUI_ContentBlock = tes3ui.registerID("TestUI:ContentBlock")
	GUIID_TestUI_NameLabel = tes3ui.registerID("TestUI:NameLabel")

	logInfo(modName .. " " .. modVersion .. " initialized")
end
event.register(tes3.event.initialized, initialize)


--[[
	mod config menu

	https://easymcm.readthedocs.io/en/latest/

]]

---
-- @param id name of the variable
-- @return a TableVariable
local function createtableVar(id)
	return mwse.mcm.createTableVariable{
		id = id,
		table = config
	}  
end


--- Create the MCM menu
-- Basic UI, more fancier can be created like hiding parts of UI based on settings
-- UI should be transalated also
local function registerModConfig()
    local template = mwse.mcm.createTemplate(modName)
	template:saveOnClose(modConfig, config)
	
	-- https://easymcm.readthedocs.io/en/latest/components/pages/classes/SideBarPage.html
	local page = template:createSideBarPage{
		label = "Sidebar Page",
		description = modName .. " " .. modVersion
	}

	-- You can create categories to group settings
	-- https://easymcm.readthedocs.io/en/latest/components/categories/classes/Category.html
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

	-- didn't find ref for this setting
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

event.register(tes3.event.modConfigReady, registerModConfig)
