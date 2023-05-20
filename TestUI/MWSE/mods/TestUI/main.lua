--[[
	TestUI
	@author		
	@version	0.10
	@changelog	0.10 Initial version

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

	Features
	If lockpick / probe already equipped => do not display menu
	Once container / door is disarmed and unlocked => returns to inital state (weapon, readymode)
	
]]--


-- Adapts settings to your mod
local modName = "TestUI"	-- MUST be same as the mod folder 
local modVersion = "V0.10"
local modConfig = modName	-- file name for MCM config file
local modAuthor= "me"


-- Keep track of all the GUI IDs we care about.
local GUIID_Menu = nil
--local GUIID_TestUI_NameLabel = nil
local GUIID_TestUI_ContentBlock = nil
local GUIID_TestUI_ItemBlock = nil

-- TODO rename
local currentMenu = {
	itemsCount = 0,
	currentIndex = 0,
	window = nil,
	--
	isFirstTrapped=false,	-- set to true if trapped
	weapon = nil,
	weaponDrawn = true,
}

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

--#region mod config

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

--#endregion

--[[

		Helper functions

]]--

---Returns a table with sorted index of tbl https://stackoverflow.com/a/24565797
---@param tbl any
---@param sortFunction any
---@return table
local function getKeysSortedByValue(tbl, sortFunction)
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return sortFunction(tbl[a], tbl[b])
	end)

	return keys
end


--- Reset the current target to no target
local function resetCurrentTarget()
	currentTarget.target = nil
	currentTarget.isTrapped = false
	currentTarget.isLocked = false
end


--- Log a string as Info level in MWSE.log
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


--- Log an error message to MWSE.log
-- @param msg string to be logged as Error in MWSE.log
local function logError(msg)
	mwse.log('[' .. modName .. '] ' .. 'ERROR ' .. msg)
end


--- Update the currentIndex by moving to the next tool/item
local function nextTool()
	if currentMenu.itemsCount < 1 then
		logError("(nextTool) Try to get the next item but there are no items")
	end

	if currentMenu.currentIndex == currentMenu.itemsCount then
		currentMenu.currentIndex = 1
	else
		currentMenu.currentIndex = currentMenu.currentIndex + 1
	end
end


--- Update currentIndex by moving to the previous item
local function previousTool()
	if currentMenu.itemsCount < 1 then
		logError("(previousTool) Try to get the previous item but there are no items")
	end

	if currentMenu.currentIndex == 1 then
		currentMenu.currentIndex = currentMenu.itemsCount
	else
		currentMenu.currentIndex = currentMenu.currentIndex - 1
	end
end


--- Search in the inventory for lockpicks or probes with a minimal quality
-- @param true to search probes, false to search lockpicks
-- @param minQual minimal quality of the tool requested
-- @return unsorted table of tables with one entry par tool with quality information, can be nil if no tool found
local function searchTools(searchProbes, minQual)
	local inventory = tes3.player.object.inventory

	local toolsTable = {}
	local objectTypeToSearch

	if searchProbes then
		objectTypeToSearch = tes3.objectType.probe
	else
		objectTypeToSearch = tes3.objectType.lockpick
	end

	-- no need to search for tool condition as it will be defined when equipping
	for _, stack in pairs(inventory) do
		if stack.object.objectType == objectTypeToSearch then
			local tool = stack.object	-- tes3lockpick or tes3probe
			local toolName = tool.name
			local toolQuality = tool.quality

			logDebug(string.format("Found probe %s - %p (%.2f)",toolName, tool, toolQuality))

			-- check min quality
			if toolQuality >= minQual then
				-- add only one *type* of tool
				if (toolsTable[toolName] == nil) then
					toolsTable[toolName]={}
					toolsTable[toolName].tool = tool
					toolsTable[toolName].quality = toolQuality
					logDebug(string.format("Adding tool %s - %p (%.2f)",toolName, tool, toolQuality))
				end
			end
		end
	end

	return toolsTable
end


--[[

	UI functions

	+--------------------------+
	|+------------------------+|
	||        Label           || GUIID_TestUI_NameLabel
	|+------------------------+|
	|+------------------------+|
	||     Tools block        || GUIID_TestUI_ContentBlock
	||+----------------------+||
	|||     item block       |||
	|||+---++---------------+|||
	|||| i ||    label      ||||
	|||+---++---------------+|||
	||+----------------------+||
	||+----------------------+||
	|||     item block       |||
	|||+---+ +--------------+|||
	|||| i ||    label      ||||
	|||+---+ +--------------+|||
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


-- forward functions declaration
local onMouseButtonDown, onMouseWheel, highLightTool

-- https://mwse.github.io/MWSE/events/uiActivated/#event-data
local function uiActivatedCallback(e)
	logDebug(string.format("uiActivatedCallback %s", e.element))
	-- TODO Destroy menu
end


--- Create the window if there are items to select
-- @param isProbe true if we need to select a probe, false for a lockpick
local function createWindow(isProbe)
	if tes3.menuMode() then
		return
	end

	if (tes3ui.findMenu(GUIID_Menu)) then
        return
    end

	-- TODO deplacer dans l'activation
	-- TODO manage min quality
	local toolsTable = searchTools(isProbe, 0)

	local next = next
	if next(toolsTable) == nil then
		-- TODO change the message depending on the type of object. How to make the differnce between no tool or not good enough tool
		tes3.messageBox("No tools found")
	end

	-- Create window and frame
	local menu = tes3ui.createMenu{ id = GUIID_Menu, fixedFrame = true }

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
	
	local input_block = menu:createBlock{ id = GUIID_TestUI_ContentBlock }
	input_block.autoWidth = true
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

	-- TODO use searchTools funtion
	--local objectTypeToSearh
	local inventory = tes3.player.object.inventory
	local itemsCount = 0
	for _, v in pairs(inventory) do
        if v.object.objectType == objectTypeToSearch then
			-- Our container block for this item.
			local block = input_block:createBlock({ id = GUIID_TestUI_ItemBlock })
			block.flowDirection = "left_to_right"
			block.autoWidth = true
			block.autoHeight = true
			block.paddingAllSides = 3
			-- TODO Keep nb or items
			-- TODO filter on quality for lockpick
			-- TODO filtrer par type de lockpick/name et maxCondition (ATTENTION propriété de l'objet lui même, pas du parent)

			-- Store the item info on the block for later logic.
			-- https://mwse.github.io/MWSE/types/tes3uiElement/?h=set+property+object#setpropertyobject
			block:setPropertyObject(modName .. ":Item", v.object)

			-- Item icon
			local icon = block:createImage({path = "icons\\" .. v.object.icon})
			icon.borderRight = 5

			-- https://mwse.github.io/MWSE/types/tes3lockpick/
			-- 
			-- Label text
			local labelText = v.object.name

			-- add the GUIID for later selection job
			local label = block:createLabel({id = GUIID_TestUI_ItemBlockLabel, text = labelText})
			label.absolutePosAlignY = 0.5

			itemsCount = itemsCount + 1
		end
	end
	currentMenu.itemsCount = itemsCount
	currentMenu.currentIndex = 1

	-- TODO Set position

	-- Final setup
	menu:updateLayout()
	highLightTool()

	-- events only registered during the life of the menu to ease event management and reduce mod incompatibility
	event.register(tes3.event.mouseButtonDown, onMouseButtonDown)
	event.register(tes3.event.mouseWheel, onMouseWheel)
	event.register(tes3.event.uiActivated, uiActivatedCallback)
end


--- Destroy the Window if exists
local function destroyWindow()
	local menu = tes3ui.findMenu(GUIID_Menu)

	-- TODO add flag isDisplayed ?
	if (menu) then
		-- unregister events registered only for the life of the menu 
		-- https://mwse.github.io/MWSE/apis/event/#eventunregister
		event.unregister(tes3.event.mouseButtonDown, onMouseButtonDown)
		event.unregister(tes3.event.mouseWheel, onMouseWheel)
		event.unregister(tes3.event.uiActivated, uiActivatedCallback)

        tes3ui.leaveMenuMode()
        menu:destroy()
    end
end


--- Hightlist the tool in index
highLightTool=function()
	-- retrieve the block containing the items
	local menu = tes3ui.findMenu(GUIID_Menu)

	local contentBlock = menu:findChild (GUIID_TestUI_ContentBlock)
	local children = contentBlock.children

	-- iterate on blocks
	for i, block in pairs(children) do
		if (i == currentMenu.currentIndex) then
			local label = block:findChild(GUIID_TestUI_ItemBlockLabel)
			label.color = tes3ui.getPalette("active_color")
		else
			local label = block:findChild(GUIID_TestUI_ItemBlockLabel)
			label.color = tes3ui.getPalette("normal_color")
		end
	end

	-- update the display
	contentBlock:updateLayout()
end


--[[

	event handlers

]]

--#region events handler

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

-- TODO isolate the main code in a dedicated function
-- TODO use space button instead of mouse down ??
-- FIXME the menu prevents openning the menu (inventory, map) => need to destroy menu at right mouse
--- Callback function for MouseButtonDown event
-- https://mwse.github.io/MWSE/events/mouseButtonDown/
-- @param e event
onMouseButtonDown = function(e)
	-- event registered only when menu is displayed so prerequisites checking is reduced

	-- Left button = 0
	if (e.button ~= 0) then
		return
	end

	logDebug(string.format("onMouseButtonDown"))

	-- retrieve the block containing the items
	-- TOD put in currentMenu
	local menu = tes3ui.findMenu(GUIID_Menu)
	local contentBlock = menu:findChild (GUIID_TestUI_ContentBlock)
	local selectedBlock = contentBlock.children[currentMenu.currentIndex]

	-- https://mwse.github.io/MWSE/types/tes3uiElement/?h=create+block#getpropertyobject
	-- retrieve the tool reference
	local item = selectedBlock:getPropertyObject(modName .. ":Item")
	logDebug(string.format("selected item %p", item))

	-- TODO need to track the right weapon as when you pass from trapped to locked, the equipped will be the probe not the initial weapon same for weaponDrawn
	-- keep track of the already equipped weapon
	local currentEquipped = tes3.getEquippedItem({ actor = tes3.player })
	logDebug(string.format("currentEquipped item %p", currentEquipped))

	-- destroy menu
	destroyWindow()

	-- equip it
	-- https://mwse.github.io/MWSE/types/tes3mobilePlayer/#equip
	if config.useWorstCondition then
		tes3.mobilePlayer:equip({ item = item, selectWorstCondition = true })
	else
		tes3.mobilePlayer:equip({ item = item, selectBestCondition = true })
	end

	-- store old mode
	-- switch to ready mode
	-- https://mwse.github.io/MWSE/types/tes3mobilePlayer/#weaponready
	tes3.mobilePlayer.weaponDrawn = true
end


-- FIXME pb avec MMC => need an update
--- Update the selected tool in the menu depending on mousewheel direction
-- @param e mousewheel event
onMouseWheel = function(e)
	-- event registered only when menu is displayed so prerequisites checking is reduced

	-- TODO check other prerequisites ???
	--logDebug(string.format("onMouseWheel"))

	-- Change the selected tool depending on mousewheel direction (delta)
	if e.delta > 0 then
		previousTool()
	else
		nextTool()
	end

	-- Update display
	highLightTool()
end


--- Event fired when target changes or target is disarmed or unlocked
-- https://mwse.github.io/MWSE/events/activationTargetChanged/
-- 
-- @param e event object
local function onActivationTargetChanged(e)
	if not config.modEnabled then
		return
	end

	-- e.current is a tes3reference
	if e.current == nil then
		logDebug(string.format("onActivationTargetChanged - No object"))
		resetCurrentTarget()
		destroyWindow()
		return
	end

	-- TODO use tes3.getLocked https://mwse.github.io/MWSE/apis/tes3/#tes3getlocked or tes3.getLockLevel https://mwse.github.io/MWSE/apis/tes3/#tes3getlocklevel ?
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
				highLightTool()
			end
		end
	else
		-- New target, check if it's locked or trapped
		if (e.current.object.objectType == tes3.objectType.container) or (e.current.object.objectType == tes3.objectType.door) then
			local lockNode = e.current.lockNode
			if lockNode ~= nil then
				-- lockNode not nil => locked, trapped or both
				currentTarget.target = e.current

				-- 3 cases
				-- trapped => probe equipped => return
				-- locked => lockpick equipped => return
				-- trapped + locked => probe equipped => return, lockpick equipped => display menu

				-- priority is trapped
				-- TODO check for an equipped probe
				if (lockNode.trap ~= nil) then
					-- https://mwse.github.io/MWSE/apis/tes3/#tes3getequippeditem
					if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe }) then
						logDebug(string.format("Probe already equipped"))
						return
					else
						currentTarget.isTrapped = true
					end
				end

				-- FIXME when trapped and equipped lockpick => no menu
				if lockNode.locked and (lockNode.trap == nil) then
					currentTarget.isLocked = true
					-- check for an equipped lockpick
					if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.lockpick }) then
						logDebug(string.format("lockpick already equipped"))
						return
					end
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
	searchTools(true, 0)
	searchTools(false, 0)

	if currentTarget.isTrapped then
		tes3.messageBox("Trapped")
		createWindow(true)
		highLightTool()
	else
		tes3.messageBox("Locked")
		createWindow(false)
		highLightTool()
	end
end


--#endregion

--[[
	constructor
]]

--- Initialization register the events and the GUID for menu
local function initialize()
	-- registers needed events, better to use tes.event reference instead of the name https://mwse.github.io/MWSE/references/events/
	event.register(tes3.event.activationTargetChanged, onActivationTargetChanged)

	event.register(tes3.event.unequipped, onUnequipped)
	event.register(tes3.event.menuEnter, onMenuEnter)
	--event.register(tes3.event.activate, onActivate)
	--event.register(tes3.event.trapDisarm, onTrapDisarm)
	--event.register(tes3.event.equip, onEquip)

	GUIID_Menu = tes3ui.registerID(modName .. ":Menu")
	GUIID_TestUI_ContentBlock = tes3ui.registerID(modName .. ":ContentBlock")
	GUIID_TestUI_ItemBlock = tes3ui.registerID(modName .. ":ItemBlock")
	GUIID_TestUI_ItemBlockLabel = tes3ui.registerID(modName .. ":ItemBlockLabel")
	--GUIID_TestUI_NameLabel = tes3ui.registerID("TestUI:NameLabel")

	logInfo(modName .. " " .. modVersion .. " initialized")
end
event.register(tes3.event.initialized, initialize)


--[[
	Mod Config Menu

	https://easymcm.readthedocs.io/en/latest/
]]

--#region MCM

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

	catSettings:createYesNoButton {
		label = "Equip worst item",
		description = "Equip the worst item (already used) to prevent having too many used tools",
		variable = createtableVar("useWorstCondition"),
		defaultSetting = true,
	}

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

--#endregion