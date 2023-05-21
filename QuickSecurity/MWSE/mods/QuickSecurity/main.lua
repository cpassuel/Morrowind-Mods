--[[
	Quick Security
	@author		
	@version	0.10
	@changelog	0.10 Initial version
    
--]]

-- mod informations
local modName = "Quick Security"
local modFolder = "QuickSecurity"	-- this way can have a different name for the mod folder
local modVersion = "V0.10"
local modConfig = modName	-- file name for MCM config file
local modAuthor= "Thinuviel"


-- TODO put in a table
-- Keep track of all the GUI IDs we care about.
local GUIID_Menu = nil
local GUIID_TestUI_TitleBlock = nil
local GUIID_TestUI_ContentBlock = nil
local GUIID_TestUI_ItemBlock = nil

-- TODO rename
local currentMenu = {
	itemsCount = 0,
	currentIndex = 0,
	window = nil,
	--
	isWeaponAStateStored=false,	-- set to true if trapped
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
local i18n = mwse.loadTranslations(modFolder)


--[[

	mod config

]]

--#region mod config


-- Define mod config default values
-- TODO Add key bind variable
local modDefaultConfig = {
	modEnabled = true,
	--
	useWorstCondition = true,	-- true => use worst condition tool (already used), false best condution (maybe put a 3 states value: worst, don't care, best)
    useCalcUnlockChance = true,
    minQuality = 10,
	--
	debugMode = true,	-- true for debugging purpose should be false for mod release, it could be a MCM option, currently you have to change its value in the config file
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


---Compute the minimal quality of the lockpick depending on player stats and lock level
---@param level integer level of the lock
---@return number minimal needed quality of the lockpick
local function getLockpickMinQuality(level)
	return config.minQuality / 10.0
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
					toolsTable[toolName].name = toolName
					toolsTable[toolName].tool = tool
					toolsTable[toolName].quality = toolQuality
					logDebug(string.format("Adding tool %s - %p (%.2f)",toolName, tool, toolQuality))
				end
			end
		end
	end

	return toolsTable
end

--- Reset the current target to no target
local function resetCurrentTarget()
	logDebug(string.format("Restoring cureent target"))
	currentTarget.target = nil
	currentTarget.isTrapped = false
	currentTarget.isLocked = false
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

    Menu
        titleBlock
			titleLabel
        toolsListBlock
            Tool block
                Tool icon block
                Tool label block

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

-- TODO try to reorganize functions
-- forward functions declaration
local onMouseButtonDown, onMouseWheel, highLightTool

-- https://mwse.github.io/MWSE/events/uiActivated/#event-data
local function uiActivatedCallback(e)
	logDebug(string.format("uiActivatedCallback %s", e.element))
	-- TODO Destroy menu
end


---Restore the weapon and weaponDrawn state before the tool equipping
local function restoreWeapon()
	-- check prerequisites

	logDebug(string.format("Restoring %s - %p", currentMenu.weapon, currentMenu.weapon))
	tes3.mobilePlayer:equip({ item = currentMenu.weapon, selectBestCondition = true })
	tes3.mobilePlayer.weaponDrawn = currentMenu.weaponDrawn
end


---Equip the selected tool in the menu
local function equipSelectedTool()

    local function retrieveSelectedTool()
        -- retrieve the block containing the items
        -- TOD put and retrieve in currentMenu (same for other GUID)
        local menu = tes3ui.findMenu(GUIID_Menu)
        local contentBlock = menu:findChild (GUIID_TestUI_ContentBlock)
        local selectedBlock = contentBlock.children[currentMenu.currentIndex]

        -- https://mwse.github.io/MWSE/types/tes3uiElement/?h=create+block#getpropertyobject
        -- retrieve the tool reference
        return selectedBlock:getPropertyObject(modName .. ":Item")
    end

    local item = retrieveSelectedTool()
    logDebug(string.format("selected item %p", item))

    -- TODO how and when to reset isWeaponAStateStored
	-- TODO need to track the right weapon as when you pass from trapped to locked, the equipped will be the probe not the initial weapon same for weaponDrawn
	-- keep track of the already equipped weapon
    if not currentMenu.isWeaponAStateStored then
        currentMenu.weapon = tes3.getEquippedItem({ actor = tes3.player })
        currentMenu.weaponDrawn = tes3.mobilePlayer.weaponDrawn
        currentMenu.isWeaponAStateStored = true
    end

	-- destroy menu
	--destroyWindow()

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


--Uupdate the menu title depending on the type of tool in parameter
---@param isProbe boolean true if looking for probe false for lockpick
local function updateTitle(isProbe)
	local menu = tes3ui.findMenu(GUIID_Menu)

	local titleBlock = menu:findChild(GUIID_TestUI_TitleBlock)
	-- only one child
	local titleLabel = titleBlock.children[1]
	if isProbe then
		titleLabel.text = "Select a probe"
	else
		titleLabel.text = "Select a lockpick"
	end

	titleLabel:updateLayout()
end


---Create the window with the tools list from the table in paramter
---@param toolsTable table of tools to display (MUST NOT BE EMPTY)
local function createWindow(toolsTable)
	if tes3.menuMode() then
		return
	end

	if (tes3ui.findMenu(GUIID_Menu)) then
        return
    end

	local next = next
	if next(toolsTable) == nil then
        logError("list of tools MUST NOT BE EMPTY")
        return
	end

	-- Create window and frame
	local menu = tes3ui.createMenu{ id = GUIID_Menu, fixedFrame = true }

	-- To avoid low contrast, text input windows should not use menu transparency settings
	menu.alpha = 1.0

	-- Create layout (update title later)
	local titleBlock = menu:createBlock({ id = GUIID_TestUI_TitleBlock })
	titleBlock.autoHeight = true
	titleBlock.autoWidth = true
	titleBlock.paddingAllSides = 1
	titleBlock.childAlignX = 0.5

	local titleLabel = titleBlock:createLabel({ text = '' })
	titleLabel.color = tes3ui.getPalette("header_color")
	titleBlock:updateLayout()
    titleBlock.widthProportional = 1.0
	menu.minWidth = titleLabel.width

	local toolsListBlock = menu:createBlock{ id = GUIID_TestUI_ContentBlock }
	toolsListBlock.autoWidth = true
	toolsListBlock.autoHeight = true
	toolsListBlock.flowDirection = "top_to_bottom"

	local itemsCount = 0
    local sortedKeys = getKeysSortedByValue(toolsTable, function(a, b) return a.quality < b.quality end)
    for _,v in pairs(sortedKeys) do
		-- Our container block for this item.
		local toolBlock = toolsListBlock:createBlock({ id = GUIID_TestUI_ItemBlock })
		toolBlock.flowDirection = "left_to_right"
		toolBlock.autoWidth = true
		toolBlock.autoHeight = true
		toolBlock.paddingAllSides = 3

		-- Store the item info on the toolBlock for later logic.
		-- https://mwse.github.io/MWSE/types/tes3uiElement/?h=set+property+object#setpropertyobject
		toolBlock:setPropertyObject(modName .. ":Item", toolsTable[v].tool)

		-- create Item icon block
		local icon = toolBlock:createImage({path = "icons\\" .. toolsTable[v].tool.icon})
		icon.borderRight = 5

		-- Label text
		local labelText = toolsTable[v].name
		-- add the GUIID for later selection job
		local label = toolBlock:createLabel({id = GUIID_TestUI_ItemBlockLabel, text = labelText})
		label.absolutePosAlignY = 0.5

		itemsCount = itemsCount + 1
    end

	currentMenu.itemsCount = itemsCount
	currentMenu.currentIndex = 1

	-- Final setup
	menu:updateLayout()
	highLightTool()

	-- events only registered during the life of the menu to ease event management and reduce mod incompatibility
	--event.register(tes3.event.mouseButtonDown, onMouseButtonDown)
	event.register(tes3.event.mouseWheel, onMouseWheel)
	event.register(tes3.event.uiActivated, uiActivatedCallback)
end


--- Destroy the Window if exists
local function destroyWindow()
	local menu = tes3ui.findMenu(GUIID_Menu)

	-- TODO add flag isDisplayed ?
	if (menu) then
		logDebug("Destroy Menu")
		-- unregister events registered only for the life of the menu 
		-- https://mwse.github.io/MWSE/apis/event/#eventunregister
		--event.unregister(tes3.event.mouseButtonDown, onMouseButtonDown)
		event.unregister(tes3.event.mouseWheel, onMouseWheel)
		event.unregister(tes3.event.uiActivated, uiActivatedCallback)

        tes3ui.leaveMenuMode()
        menu:destroy()
    end
end


--- Highlight the tool associated to the currentIndex
highLightTool=function()
	-- retrieve the block containing the items
	local menu = tes3ui.findMenu(GUIID_Menu)

	local contentBlock = menu:findChild(GUIID_TestUI_ContentBlock)
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


-- https://mwse.github.io/MWSE/apis/event/#eventregister
-- event.register(tes3.event.keyDown, onKeyDown, { filter = tes3.scanCode.space })
local function onKeyDown(e)
	if tes3ui.findMenu(GUIID_Menu) ~= nil then
		logDebug("onKeyDown")
		equipSelectedTool()
	end
end


--- You NEED to destroy your menu when entering menu mode to avoid locking the UI
-- https://mwse.github.io/MWSE/events/menuEnter/
---@param e any event object for menuEnter
local function onMenuEnter(e)
	logDebug(string.format("MenuEnter"))
	destroyWindow()
end


--- Manage unequipped event
-- https://mwse.github.io/MWSE/events/unequipped/
---@param e any event object
local function onUnequipped(e)
	if not config.modEnabled then
		return
	end

	if currentTarget.target == nil then
		return
	end

	if (e.item ~= tes3.objectType.probe) and (e.item ~= tes3.objectType.lockpick) then
		return
	end

	-- TODO better checks because when you equip a tool, you can unequip a weapon => dedicated variable
	-- TODO check if restoreWeapon() should be ok because currentTarget is nil
	tes3.messageBox("DEBUG tool broken")

	logDebug(string.format("Unequipped %s", e.item.name))
	-- event unequipped when the probe/locpick is completly used (condition = 0)
	-- => redo the same as in ActivatedChanged
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


-- FIXME pb avec MMC => need an update on MMC
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


-- TODO isolate in a dedicated function for use on unEuipped
--- Event fired when a target changes or a target is disarmed or unlocked
-- same target
--   trapped -> disarmed
--     locked => display menu
--     unlocked => returns
-- new target
--
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

	-- TODO isolate this part in a dedicated function
    local searchForProbe = false

    -- check if same target => meaning it has been disarmed or unlocked
	if (currentTarget.target == e.current) then
		-- same target so it is a door or a container
		logDebug(string.format("onActivationTargetChanged with same target %s - %p", e.current, e.current))

        if tes3.getTrap({ reference = e.current }) then
			logError(string.format("Same target but still trapped %s - %p", e.current, e.current))
            return
        end

        if not tes3.getLocked({ reference = e.current }) then
            -- final
			resetCurrentTarget()
            restoreWeapon()
            return
        else
            -- locked
			logError(string.format("Same target but still locked %s - %p", e.current, e.current))
            currentTarget.isTrapped = false
            currentTarget.isLocked =true
            searchForProbe = false
        end
	else
		-- New target, check if it's a door / container
		if (e.current.object.objectType ~= tes3.objectType.container) and (e.current.object.objectType ~= tes3.objectType.door) then
			resetCurrentTarget()
            return
        end

		-- https://mwse.github.io/MWSE/apis/tes3/#tes3gettrap (returns nil if not trapped)
        if tes3.getTrap({ reference = e.current }) then
            -- test if probe equipped
            -- https://mwse.github.io/MWSE/apis/tes3/#tes3getequippeditem
            if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe }) then
                logDebug(string.format("Probe already equipped"))
                return
            end
            currentTarget.isTrapped = true
            searchForProbe = true
        else
			-- https://mwse.github.io/MWSE/apis/tes3/#tes3getlocked (returns true if locked)
            if tes3.getLocked({ reference = e.current }) then
                -- check for an equipped lockpick
                if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.lockpick }) then
                    logDebug(string.format("lockpick already equipped"))
                    return
                end

                currentTarget.isLocked = true
                searchForProbe = false
            else
                -- not locked and not trapped => exit
				resetCurrentTarget()
                return
            end
        end
    end

    -- trapped or locked and no related tool equipped

    local minQuality = 0
    if not searchForProbe then
        -- compute min quality
		-- https://mwse.github.io/MWSE/apis/tes3/#tes3getlocklevel
		minQuality = getLockpickMinQuality(tes3.getLockLevel({ reference = e.current }))
    end

    local items = searchTools(searchForProbe, minQuality)
    currentTarget.target = e.current

    -- If no tool just display a message
    local next = next
    if next(items) == nil then
        if searchForProbe then
            tes3.messageBox("You don't have probes")
        else
            tes3.messageBox("You don't have lockpick or not good enough")
        end
        return
    end

    -- TODO check if destroy menu is needed
    -- TODO remove dead code
    if currentTarget.target == nil then
		resetCurrentTarget()	-- may be not necessary
		destroyWindow()
		return
	end

	logDebug(string.format("Container/door %s (%p) - trapped %s, locked %s", currentTarget.target, currentTarget.target, currentTarget.isTrapped, currentTarget.isLocked))

    createWindow(items)
	updateTitle(searchForProbe)
    highLightTool()
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
	-- TODO register only when menu is displayed
	-- TODO Use key in config file
	event.register(tes3.event.keyDown, onKeyDown, { filter = tes3.scanCode.space })

	GUIID_Menu = tes3ui.registerID(modName .. ":Menu")
	GUIID_TestUI_ContentBlock = tes3ui.registerID(modName .. ":ContentBlock")
	GUIID_TestUI_ItemBlock = tes3ui.registerID(modName .. ":ItemBlock")
	GUIID_TestUI_ItemBlockLabel = tes3ui.registerID(modName .. ":ItemBlockLabel")

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
		label = "Equip the worst condition tool",
		description = "Equip the worst condition tool (already used) to prevent having too many used tools",
		variable = createtableVar("useWorstCondition"),
		defaultSetting = true,
	}

    catSettings:createYesNoButton {
		label = "Compute chance to unlock",
		description = "Compute the chance to unlock the door/container to display only usable lockpicks",
		variable = createtableVar("useCalcUnlockChance"),
		defaultSetting = true,
	}

	-- https://easymcm.readthedocs.io/en/latest/components/settings/classes/KeyBinder.html
	catSettings:createKeyBinder {
		label = "Assign Keybind",
		allowCombinations = true,
		defaultSetting = {
			keyCode = tes3.scanCode.space,
			--These default to false
			isShiftDown = false,
			isAltDown = false,
			isControlDown = false,
		},
		variable = createtableVar("myKeybind")
	}

    -- For DEBUG only
	catSettings:createSlider {
		label = "Quality slider",
		description = "DEBUG Changes minimal quality of the lockpick * 10",
		min = 0,
		max = 30,
		step = 1,
		jump = 1,
		variable = createtableVar("minQuality")
	}
	mwse.mcm.register(template)
end

event.register(tes3.event.modConfigReady, registerModConfig)

--#endregion