--[[
	Quick Security
	@author		
	@version	0.80
	@changelog	0.50 Initial version
    
	FIXME Quand pas de lockpick dispo après un disarm => pas de restoreWeapon
	TODO check behaviour with Equip Script fix in MCP
	TODO Restore weapon when another target is activated (! nil) if previously selected tool is stil equipped, add an option to disable this behavior ?

	---------- TEST ----------
	OK Unlock + restoreWeapon (locked only)
	OK Disarm + restoreWeapon (trapped only)
	OK Disarm + unlock + restoreWeapon
	Unlock + no more lockpick + restoreWeapon
	Disarm + no more probe + restoreWeapon
	Unlock + lockpick broken => getLockpick
	Disarm + probe broken => getProbe
	Unlock + unequipped condition 0 => restoreWeapon
	Disarm + unequipped condition 0 => restoreWeapon ou getLockpick
	OK Disarm + haskey
	OK Locked + no lockpick + hintHaskey

	TODO player haskey => option to equip lockpick anyway ?

--]]

-- mod informations
local modName = "Quick Security"
local modFolder = "QuickSecurity"	-- this way can have a different name for the mod folder
local modVersion = "V0.80"
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
	-- TODO put in playerAttribute
	isWeaponAStateStored=false,	-- set to true if trapped
	weapon = nil,
	-- tes3mobilePlayer properties https://mwse.github.io/MWSE/types/tes3mobilePlayer/
	weaponDrawn = false,
	weaponReady = false,
	castReady = false,
	--
	isEquipping = false,
	isProbe = false,
	currentEquippedTool = nil,	-- currently equipped tool (probe/lockpick) or nil
}

-- keep information about the target (container/door trapped or locked or both)
local currentTarget = {
	target = nil,
	isTrapped = false,
	isLocked = false,
	isClosing = false,	-- closing the menu ?
}

-- TODO rename in playerInformation
local playerAttribute = {
	agility = 0,
	luck = 0,
	security = 0,
	-- security ratio
	securityRatio = 0,
	-- fatigue status
	currentFatigue = 0,
	maxFatigue = 0,
	fatigueTerm = 0,
	fullFatigueTerm = 0,
	-- static GMST values 
	gmstOk=false,
	fTrapCostMult = 0,
	fFatigueBase = 0,
	fFatigueMult = 0,
	fPickLockMult = 0
}


--[[

	Mod translation
	https://mwse.github.io/MWSE/guides/mod-translations/
	
]]--

-- returns a table of transation, you acces a translation by its key: i18n("HELP_ATTACKED")
local i18n = mwse.loadTranslations(modFolder)


--[[

	mod config

]]

--#region mod config


-- Define mod config default values
local modDefaultConfig = {
	modEnabled = true,
	--
	useWorstCondition = true,	-- true => use worst condition tool (already used), false best condution (maybe put a 3 states value: worst, don't care, best)
    diplayChance = true,
	selectUsableFullFatigue = false,	-- select also tools *usable* only with full fatigue (or fatigue higher than current fatigue)
	hintKeyExists = false,
	usePlayerKey = true,	-- if the player has the key to unlock, don't open lockpick menu
	selectionKey = {
	    keyCode = tes3.scanCode.space,
	    isShiftDown = false,
	    isAltDown = false,
	    isControlDown =false
	},
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


---Log a string as Info level in MWSE.log
---@param msg string to be logged as INFO in MWSE.log
local function logInfo(msg)
	-- https://www.lua.org/pil/5.2.html
	-- TODO get ride of string.format in calling 
	--s = string.format('[' .. modName .. '] ' .. 'INFO ' .. fmt, unpack(arg))
	--mwse.log(s)
	mwse.log('[' .. modName .. '] ' .. 'INFO ' .. msg)
end


---Log a message to MWSE.log if debug mode is enabled
---@param msg string to be logged as DEBUG in MWSE.log
local function logDebug(msg)
	if (config.debugMode) then
		mwse.log('[' .. modName .. '] ' .. 'DEBUG ' .. msg)
	end
end


---Log an error message to MWSE.log
---@param msg string to be logged as ERROR in MWSE.log
-- TODO https://stackoverflow.com/questions/4021816/in-lua-how-can-you-print-the-name-of-the-current-function-like-the-c99-func
local function logError(msg)
	mwse.log('[' .. modName .. '] ' .. 'ERROR ' .. msg)
end


---Returns a table with sorted index of tbl https://stackoverflow.com/a/24565797
---@param tbl table table to order
---@param sortFunction function sorting function
---@return table table of ordered reference of tbl
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


---Update the currentIndex by moving to the next tool/item
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


---Update currentIndex by moving to the previous tool/item
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


--- Compute and save current player stats 
local function getPlayerStats()
	-- skill et attributes
	local player = tes3.mobilePlayer

	playerAttribute.security = player.security.current
	playerAttribute.agility = player.agility.current
	playerAttribute.luck = player.luck.current

	playerAttribute.currentFatigue = player.fatigue.current
	playerAttribute.maxFatigue = player.fatigue.base

	-- static values
	if not playerAttribute.gmstOk then
		playerAttribute.fTrapCostMult = tes3.findGMST(tes3.gmst.fTrapCostMult).value
		playerAttribute.fFatigueBase = tes3.findGMST(tes3.gmst.fFatigueBase).value
		playerAttribute.fFatigueMult = tes3.findGMST(tes3.gmst.fFatigueMult).value
		playerAttribute.fPickLockMult = tes3.findGMST(tes3.gmst.fPickLockMult).value
		playerAttribute.gmstOk = true
	end

	-- https://mwse.github.io/MWSE/types/tes3mobilePlayer/?h=mobile+player#getfatigueterm
	playerAttribute.fatigueTerm = playerAttribute.fFatigueBase - playerAttribute.fFatigueMult * (1 - playerAttribute.currentFatigue / playerAttribute.maxFatigue)
	playerAttribute.fullFatigueTerm = playerAttribute.fFatigueBase
	-- compute *security ratio* used in chance computation
	playerAttribute.securityRatio = (playerAttribute.agility/5 + playerAttribute.luck/10 + playerAttribute.security)
end


---Compute the chance to unlock a door/container given the toolQuality and the locklevel in parameter
---@param toolQuality number quality of the lockpick
---@param locklevel number level of the lock
---@return number curChance, number fullChance returns the chance to unlock the object with current and full fatigue (can be negative)
local function getUnlockChance(toolQuality, locklevel)
	-- Lockpick
	-- x = 0.2 * pcAgility + 0.1 * pcLuck + securitySkill
	-- x *= pickQuality * fatigueTerm
	-- x += fPickLockMult * lockStrength

	getPlayerStats()

	local curChance = playerAttribute.securityRatio * toolQuality * playerAttribute.fatigueTerm + playerAttribute.fPickLockMult * locklevel
	local fullChance = playerAttribute.securityRatio * toolQuality * playerAttribute.fullFatigueTerm + playerAttribute.fPickLockMult * locklevel
	logDebug(string.format("Unlock chance: %.2f - %.2f", curChance, fullChance))
	-- Don't cap negative curChance to 0 because it is used to sort lockpicks
	return curChance, fullChance
end


---Compute the chance to disarm a door/container given the probe quality and the magickaCost in parameter
---@param toolQuality number quality of the probe
---@param magickaCost number *level* of the trap
---@return number curChance, number fullChance returns the chance to disarm the trap with current and full fatigue
local function getDisarmChance(toolQuality, magickaCost)
	-- Disarm
	-- x = 0.2 * pcAgility + 0.1 * pcLuck + securitySkill
	-- x += fTrapCostMult * trapSpellPoints
	-- x *= probeQuality * fatigueTerm

	getPlayerStats()

	local curChance = (playerAttribute.securityRatio + (playerAttribute.fTrapCostMult * magickaCost)) * toolQuality * playerAttribute.fatigueTerm
	local fullChance = (playerAttribute.securityRatio + (playerAttribute.fTrapCostMult * magickaCost)) * toolQuality * playerAttribute.fullFatigueTerm
	logDebug(string.format("Disarm chance: %.2f - %.2f", curChance, fullChance))
	return curChance, fullChance
end


---Search in the inventory for lockpicks or probes with a non negative chance to unlock
---@param searchForProbes boolean true to search for probes, false to search for lockpicks
---@param level number level of the trap (magickaCost) or of the lock
---@return table unsorted table of tables with one entry par tool with quality information, can be nil if no tool found
local function searchTools(searchForProbes, level)

	---Check if the object is of the type searched (probe or lockpick)
	---@param object any object found in inventory
	---@return boolean returns true if it's a searched object type
	local function isSearchedTool(object)
		if searchForProbes then
			return (object.objectType == tes3.objectType.probe)
		else
			return (object.objectType == tes3.objectType.lockpick)
		end
	end

	---Returns the chance to unlock/disarm from the quality of the object
	---@param quality number quality of the object
	---@return number curChance, number fullChance returns chance at current and full fatigue
	local function computeChange(quality)
		if searchForProbes then
			return getDisarmChance(quality, level)
		else
			return getUnlockChance(quality, level)
		end
	end

	local inventory = tes3.player.object.inventory
	local toolsTable = {}
	for _, stack in pairs(inventory) do
		-- stack = tes3itemStack (https://mwse.github.io/MWSE/types/tes3itemStack/)
		if not isSearchedTool(stack.object) then
			goto continue
		end

		local tool = stack.object	-- tes3lockpick or tes3probe
		local toolName = tool.name

		-- compute chance current, max fatique
		local curChance, fullChance = computeChange(tool.quality)
		-- option to select object usable at full fatigue
		if config.selectUsableFullFatigue then
			if fullChance <=0 then goto continue end
		else
			if curChance <= 0 then goto continue end
		end

		if (toolsTable[toolName] == nil) then
			toolsTable[toolName]={}
			toolsTable[toolName].name = toolName
			toolsTable[toolName].tool = tool
			toolsTable[toolName].count = stack.count
			toolsTable[toolName].curChance = curChance
			toolsTable[toolName].fullChance = fullChance

			if searchForProbes then
				toolsTable[toolName].type = tes3.objectType.probe
			else
				toolsTable[toolName].type = tes3.objectType.lockpick
			end

			logDebug(string.format("searchTools: Adding %d %s - %p (%.2f - %.2f)",stack.count, toolName, tool, curChance, fullChance))
		end

		--MUST BE just before the end of the for loop: No continue in Lua :(
	    ::continue::
	end
	return toolsTable
end


---Store player weapon information and status
local function storeWeapon()
	-- Test on isWeaponAStateStored
	if  currentMenu.isWeaponAStateStored then
		logError(string.format("storeWeapon: Weapon aldeady stored %s - %p", currentMenu.weapon, currentMenu.weapon))
	end
	-- TODO better object retrieval (torch, lockpick)
	-- https://mwse.github.io/MWSE/apis/tes3/?h=get+equipped+item#tes3getequippeditem
	-- returns tes3equipmentStack https://mwse.github.io/MWSE/types/tes3equipmentStack/
	local equipStack = tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.weapon })
	if (equipStack) then
		currentMenu.weapon = equipStack.object
	end

	--currentMenu.weaponDrawn = tes3.mobilePlayer.weaponDrawn
	currentMenu.weaponReady = tes3.mobilePlayer.weaponReady
	currentMenu.castReady = tes3.mobilePlayer.castReady
	currentMenu.isWeaponAStateStored = true

	logDebug(string.format("storeWeapon %s - %p", currentMenu.weapon, currentMenu.weapon))
end


---Restore the weapon and weaponDrawn state before the tool equipping
local function restoreWeapon()
	--TODO add a delay before equiping ?
	-- check prerequisites
	logDebug(string.format("restoreWeapon %s - %p", currentMenu.weapon, currentMenu.weapon))

	if currentMenu.isWeaponAStateStored then
		logDebug(string.format("restoreWeapon: isWeaponAStateStored"))

		currentMenu.currentEquippedTool = nil
		-- need a timer to give time to unequip the probe/lockpick
		-- TODO secure it by cancelling when there is already a timer started
		-- FIXME weapon always drawn then go back to desired state
		-- TODO use a double timer ? first weaponReady = false then equip then restore weaponReady

		-- DEBUG test unequip first
		tes3.mobilePlayer.weaponReady = false
		tes3.mobilePlayer.castReady = false
		local objectType
		logDebug(string.format("restoreWeapon currentMenu.isProbe %s", currentMenu.isProbe))

		if currentMenu.isProbe then
			objectType = tes3.objectType.probe
		else
			objectType = tes3.objectType.lockpick
		end
		tes3.mobilePlayer:unequip({ type = objectType})
		--tes3.mobilePlayer.castReady = currentMenu.castReady
		--tes3.mobilePlayer.weaponReady = currentMenu.weaponReady

		--tes3.mobilePlayer:equip({ item = currentMenu.weapon, selectBestCondition = true })
		-- https://mwse.github.io/MWSE/apis/timer/#timerstart
		timer.start({
			duration = .5,
			iterations = 1,
			callback = function()
				tes3.mobilePlayer:equip({ item = currentMenu.weapon, selectBestCondition = true })
				tes3.mobilePlayer.castReady = currentMenu.castReady
				tes3.mobilePlayer.weaponReady = currentMenu.weaponReady
				-- DEBUG
				--tes3.mobilePlayer.castReady = false
				--tes3.mobilePlayer.weaponReady = false
				currentMenu.isWeaponAStateStored = false
				logDebug(string.format("restoreWeapon: timer callback"))
			end
		})
	end
end


--- Reset the current target to no target
local function resetCurrentTarget()
	logDebug(string.format("Reset current target"))
	currentTarget.target = nil
	currentTarget.isTrapped = false
	currentTarget.isLocked = false
end


--[[

	UI functions
	Menu structure
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
        toolsListBlock (GUIID_TestUI_ContentBlock)
            Tool block
                Tool icon block
                Tool label block

]]

-- TODO try to reorganize functions
-- forward functions declaration
local onMouseWheel, destroyWindow

-- https://mwse.github.io/MWSE/events/uiActivated/#event-data
local function uiActivatedCallback(e)
	logDebug(string.format("uiActivatedCallback %s", e.element))
	-- Destroy menu
	destroyWindow()
end


---Equip the selected tool in the menu
local function equipSelectedTool()

    ---comment
	---@return any 
	local function retrieveSelectedTool()
        -- retrieve the block containing the items
        -- TODO put and retrieve in currentMenu (same for other GUID)
        local menu = tes3ui.findMenu(GUIID_Menu)
        local contentBlock = menu:findChild (GUIID_TestUI_ContentBlock)
        local selectedBlock = contentBlock.children[currentMenu.currentIndex]

        -- https://mwse.github.io/MWSE/types/tes3uiElement/?h=create+block#getpropertyobject
        -- retrieve the tool reference
        return selectedBlock:getPropertyObject(modName .. ":Item")
    end


	---TODO may cause issues when manual equipment
	---Retrieve the isProbe flag that define if the menu is about probe (true) or lockpick (false) from the title block
	---@return boolean return the kind of tool in the menuprobe (true) or lockpick (false)
	local function getIsProbe()
		local menu = tes3ui.findMenu(GUIID_Menu)
		local titleBlock = menu:findChild(GUIID_TestUI_TitleBlock)
		return titleBlock:getPropertyBool(modName .. ":isProbe")
	end

	currentMenu.isEquipping = true

    local item = retrieveSelectedTool()
    logDebug(string.format("equipSelectedTool: selected item %s", item))

	currentMenu.currentEquippedTool = item
	currentMenu.isProbe= getIsProbe()

    -- TODO how and when to reset isWeaponAStateStored
	-- TODO need to track the right weapon as when you pass from trapped to locked, the equipped will be the probe not the initial weapon same for weaponDrawn
	-- keep track of the already equipped weapon
    if not currentMenu.isWeaponAStateStored then
		storeWeapon()
    end

	-- equip it
	tes3.mobilePlayer.castReady = false
	-- switch to ready mode
	-- https://mwse.github.io/MWSE/types/tes3mobilePlayer/?h=weapondrawn#weaponready
	tes3.mobilePlayer.weaponReady = true

	-- TODO add a flag to prevent multiple call back
	timer.start({
		duration = .3,
		iterations = 1,
		callback = function()
			-- https://mwse.github.io/MWSE/types/tes3mobilePlayer/#equip
			logDebug(string.format("equipSelectedTool: timer callback"))

			if config.useWorstCondition then
				tes3.mobilePlayer:equip({ item = item, selectWorstCondition = true })
			else
				tes3.mobilePlayer:equip({ item = item, selectBestCondition = true })
			end
			currentMenu.isEquipping = false
		end
	})
end


--- Highlight the tool associated to the currentIndex in the menu
local function highLightTool()
	-- retrieve the block containing the items
	local menu = tes3ui.findMenu(GUIID_Menu)

	local contentBlock = menu:findChild(GUIID_TestUI_ContentBlock)
	local children = contentBlock.children

	-- iterate on blocks
	for i, block in pairs(children) do
		local label = block:findChild(GUIID_TestUI_ItemBlockLabel)
		local curChance = label:getPropertyFloat(modName .. ":curChance")

		-- https://mwse.github.io/MWSE/apis/tes3ui/?h=getpal#tes3uigetpalette
		if (i == currentMenu.currentIndex) then
			if curChance <= 0 then
				label.color = tes3ui.getPalette("answer_color")
			else
				label.color = tes3ui.getPalette("active_color")
			end
		else
			if curChance <= 0 then
				-- for the case to display usable at full fatique tool
				label.color = tes3ui.getPalette("negative_color")
			else
				label.color = tes3ui.getPalette("normal_color")
			end
		end
	end

	-- update the display
	contentBlock:updateLayout()
end


--Update the menu title depending on the type of tool in parameter
---@param isProbe boolean true if looking for probe false for lockpick
local function updateTitle(isProbe)
	local menu = tes3ui.findMenu(GUIID_Menu)

	local titleBlock = menu:findChild(GUIID_TestUI_TitleBlock)

	-- store the type of tool
	titleBlock:setPropertyBool(modName .. ":isProbe", isProbe)

	-- only one child
	local titleLabel = titleBlock.children[1]
	if isProbe then
		titleLabel.text = "Select a probe"
	else
		titleLabel.text = "Select a lockpick"
	end

	titleLabel:updateLayout()
end


---Create the menu with the tools list from the table in paramter
---@param toolsTable table of tools to display (MUST NOT BE EMPTY)
local function createWindow(toolsTable)
	if tes3.menuMode() then
		return
	end

	logDebug(string.format("Create Window"))

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
    local sortedKeys = getKeysSortedByValue(toolsTable, function(a, b) return a.curChance < b.curChance end)
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

		-- Item icon block
		local icon = toolBlock:createImage({path = "icons\\" .. toolsTable[v].tool.icon})
		icon.borderRight = 5

		-- Compute Item label text
		local labelText = toolsTable[v].name
		if toolsTable[v].count > 1 then
			labelText = labelText .. string.format(" (%d)", toolsTable[v].count)
		end
		if config.diplayChance then
			-- display only curChance when selectUsableFullFatigue = false ?
			labelText = labelText .. string.format(" %.f%% / %.f%%", math.max(0, toolsTable[v].curChance), toolsTable[v].fullChance)
		end

		-- add the GUIID for later selection job
		local label = toolBlock:createLabel({id = GUIID_TestUI_ItemBlockLabel, text = labelText})

		-- add curChance property for label color later
		label:setPropertyFloat(modName .. ":curChance", toolsTable[v].curChance)

		label.absolutePosAlignY = 0.5

		itemsCount = itemsCount + 1
    end

	currentMenu.itemsCount = itemsCount
	currentMenu.currentIndex = 1

	-- Final setup
	menu:updateLayout()
	highLightTool()

	-- events only registered during the life of the menu to ease events management and reduce mod incompatibility
	event.register(tes3.event.mouseWheel, onMouseWheel)
	event.register(tes3.event.uiActivated, uiActivatedCallback)
end


--- Destroy the menu if exists
destroyWindow=function()
	local menu = tes3ui.findMenu(GUIID_Menu)

	logDebug("destroyWindow")

	-- TODO add flag isDisplayed ?
	if (menu) then
		logDebug("Destroy existing Menu")
		-- unregister events registered only for the life of the menu 
		-- https://mwse.github.io/MWSE/apis/event/#eventunregister
		event.unregister(tes3.event.mouseWheel, onMouseWheel)
		event.unregister(tes3.event.uiActivated, uiActivatedCallback)

        menu:destroy()
    end
end


--[[

	event handlers

]]

--#region events handler


-- https://mwse.github.io/MWSE/apis/event/#eventregister
local function onKeyDown(e)
	if tes3ui.findMenu(GUIID_Menu) ~= nil then
		logDebug("Event onKeyDown")
		if not currentTarget.isClosing then
			equipSelectedTool()
			currentTarget.isClosing = true
			--DEBUG test avec delai après équipement
			--TODO better test in case of multiple events
			-- timer.start({
			-- 	duration = .5,
			-- 	iterations = -1,
			-- 	callback = function()
					destroyWindow()
					currentTarget.isClosing = false
			-- 	end
			-- })
		end
	end
end


--- You NEED to destroy your menu when entering menu mode to avoid locking the UI
-- https://mwse.github.io/MWSE/events/menuEnter/
---@param e any event object for menuEnter
local function onMenuEnter(e)
	logDebug(string.format("onMenuEnter"))
	destroyWindow()
end


---Manage action on a non nil target
---@param target any activated target
local function manageCurrentTarget(target)

	-- TODO returns key instead ?
	---Check if a key exists for this door/container
	---@return boolean true is there is a key to open the door/container
	local function objectHasKey()
		if (target == nil) or (target.lockNode == nil) then
			return false
		else
			return target.lockNode.key ~= nil
		end
	end


	---Check if the player has the k to unlock the object
	---@return boolean true if the player has the key to unlock the object in his inventory
	local function playerHasKey()
		if objectHasKey() then
			logDebug(string.format("Target %s has key %s", target, target.lockNode.key))

			return tes3.getItemCount({
				reference = tes3.player,
				item = target.lockNode.key
			}) > 0
		else
			return false
		end
	end

	logDebug(string.format("manageCurrentTarget"))

	-- currently equiping tool no need to do something
	if currentMenu.isEquipping then
		return
	end

	local searchForProbe = false

	-- TODO Refactor the 3 branches of the test
	-- check if same target => meaning it has been disarmed or unlocked
	if (currentTarget.target == target) then
		-- same target so it is a door or a container
		-- case tool broken => managed in onUnequipped
		logDebug(string.format("manageCurrentTarget with same target %s - %p", target, target))

		-- TODO rewrite tests
		-- DEBUG
		logDebug(string.format("target %s (trapped %s)", target, tes3.getTrap({ reference = target })))

		if tes3.getTrap({ reference = target }) then
			logError(string.format("Same target but still trapped %s - %p", target, target))
			-- If probe equipped exit
			if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe }) then
				logDebug(string.format("manageCurrentTarget - Probe already equipped"))
				return
			end

			searchForProbe = true
			currentTarget.isTrapped = true
		else
			if not tes3.getLocked({ reference = target }) then
				-- final state: the object is disarmed and unlocked
				-- may be can unregister unequipped event
				resetCurrentTarget()
				restoreWeapon()
				return
			else
				-- locked
				logError(string.format("Same target but still locked %s - %p", target, target))

				if objectHasKey() then
					logDebug(string.format("manageCurrentTarget - objectHasKey"))
					if playerHasKey() then
						logDebug(string.format("manageCurrentTarget - playerHasKey"))
						-- check if the player has the key (cf. Security Enhanced). If so do not equip lockpick (option in config ?)

						-- qu'est ce qui arrive si le joueur a la clé mais que le lockpick est équipé ?
					return
					end
				end

				-- TODO test lockpick equipped
				if  tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.lockpick }) then
					logDebug(string.format("manageCurrentTarget: lockpick already equipped"))
					return
				end
				currentTarget.isTrapped = false
				currentTarget.isLocked =true
				searchForProbe = false
			end
		end
	else
		-- New target, check if it's a door / container
		-- TODO remove 
		if (target.object.objectType ~= tes3.objectType.container) and (target.object.objectType ~= tes3.objectType.door) then
			resetCurrentTarget()
			return
		end

		-- https://mwse.github.io/MWSE/apis/tes3/#tes3gettrap (returns nil if not trapped)
		if tes3.getTrap({ reference = target }) then
			-- test if probe equipped
			-- https://mwse.github.io/MWSE/apis/tes3/#tes3getequippeditem
			if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe }) then
				logDebug(string.format("manageCurrentTarget - Probe already equipped"))
				return
			end
			currentTarget.isTrapped = true
			searchForProbe = true
		else
			-- https://mwse.github.io/MWSE/apis/tes3/#tes3getlocked (returns true if locked)
			if tes3.getLocked({ reference = target }) then

				if (target.lockNode.key ~= nil) then
					tes3.messageBox(string.format("DEBUG There is key for this object: %s", target.lockNode.key))
					-- check if the player has the key (cf. Security Enhanced). If so do not equip lockpick (option in config ?)

					-- qu'est ce qui arrive si le joueur a la clé mais que le lockpick est équipé ?
				end

				-- check for an equipped lockpick
				if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.lockpick }) then
					logDebug(string.format("manageCurrentTarget - lockpick already equipped"))
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
	currentTarget.target = target

	local items
	if searchForProbe then
		items = searchTools(searchForProbe, target.lockNode.trap.magickaCost)
	else
		items = searchTools(searchForProbe, tes3.getLockLevel({ reference = target }))
	end

	currentTarget.target = target

	-- If no tool available just display a message
	local next = next
	if next(items) == nil then
		if searchForProbe then
			tes3.messageBox("You don't have probes")
		else
			if config.hintKeyExists and objectHasKey() then
				tes3.messageBox("You don't have good enough lockpicks to unlock but a key exists")
			else
				tes3.messageBox("You don't have lockpicks or your lockpicks are not good enough to unlock")
			end
			-- TODO check if a probe is equipped
			if currentMenu.currentEquippedTool then
				restoreWeapon()
			end
		end
		-- Exit nothing to do
		return
	end

	-- TODO check if destroy menu is needed
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


---DEBUG
---https://mwse.github.io/MWSE/events/lockPick/
local function onLockPick(e)
	logDebug(string.format("Event lockPick - %s (%.2f)", e.tool, e.chance))
end

---DEBUG
---https://mwse.github.io/MWSE/events/trapDisarm/
local function onTrapDisarm(e)
	logDebug(string.format("Event trapDisarm - %s (%.2f)", e.tool, e.chance))
end


---https://mwse.github.io/MWSE/events/activate/
---Prevent the activation of the trap when equipping a probe
---TODO useless for locks ?
---@param e any onActivate object
---@return any
local function onActivate(e)
	logDebug(string.format("Event onActivate - activator  %s, target  %s", e.activator, e.target))

	-- We only care if the player is activating something
	if (e.activator ~= tes3.player) then
		return
	end

	-- and if the target is the current target
	if (e.target ~= currentTarget.target) then
		return
	end

	-- if equipping not completed => stop the event to prevent trap activation
	if (currentMenu.isEquipping) then
		return false
	end
end


--[[

currentTool == nil => exit
item unequipped <> currentTool => exit
item unequipped == currentTool (implicit)
	set currentTool = nil ?
	condition <> 0 => exit (manual unequiped or unequipped by mod(restoreWeapon))
	condition == 0
		target unlocked or disarmed (se souvenir de l'opération en cours ?) => détailler
			disarmed et currentTool = probe
				locked ? => manageTarget
		sinon trapped et currentTool = probe ou locked et currentTool = lockpick => broken tool => manageTarget
]]


-- FIXME tool broken does not work => pas le message broken
-- FIXME tool broken does not work => pas de menu
--- Manage unequipped event
-- https://mwse.github.io/MWSE/events/unequipped/
---@param e any event object
local function onUnequipped(e)
	if not config.modEnabled then
		return
	end

	logDebug(string.format("onUnequipped: item %s (%p), type %d", e.item.name, e.item, e.item.objectType))
	logDebug(string.format("onUnequipped: currentTarget.target %s", currentTarget.target))

	-- if currentTarget.target == nil then
	-- 	return
	-- end

	-- e.item is tes3baseObject
	if (e.item.objectType ~= tes3.objectType.probe) and (e.item.objectType ~= tes3.objectType.lockpick) then
		return
	end

	-- condition=0 => broken sinon unequip normal
	if (e.itemData)
	then
		-- https://mwse.github.io/MWSE/types/tes3itemData/#condition
		logDebug(string.format("onUnequipped: item %s, condition %d", e.item.name, e.itemData.condition))
		-- TODO check target state (trapped/locked) => need to keep the target reference
		if (e.itemData.condition == 0) then
			logDebug(string.format("onUnequipped: Broken tool %s", e.item.name))

			if (currentTarget.target) then
				manageCurrentTarget(currentTarget.target)
			end
			-- que faire quand condition > 0 (unequip manuel ou depuis restoreWeapon) ??? rien ?
			-- Attention le unequipped peut être du au restoreWeapon
		end
	end

	-- TODO better checks because when you equip a tool, you can unequip a weapon => dedicated variable
	-- TODO check if restoreWeapon() should be ok because currentTarget is nil

	-- event unequipped when the probe/locpick is completly used (condition = 0)
	-- => redo the same as in ActivatedChanged
	-- TODO change functione name
	-- TODO pass a target object. how to get the reference ????
	--manageCurrentTarget(e.item)
end


---Update the selected tool in the menu depending on mousewheel direction
---@param e any mousewheel event
onMouseWheel = function(e)
	-- event registered only when menu is displayed so prerequisites checking is reduced

	-- Change the selected tool depending on mousewheel direction (delta)
	if e.delta > 0 then
		previousTool()
	else
		nextTool()
	end

	-- Update display
	highLightTool()
end


local function getLockpick(target)

	-- TODO returns key instead ?
	---Check if a key exists for this door/container
	---@return boolean true is there is a key to open the door/container
	local function objectHasKey()
		if (target == nil) or (target.lockNode == nil) then
			return false
		else
			return target.lockNode.key ~= nil
		end
	end

	--DELETE ?
	---Check if the player has the k to unlock the object
	---@return boolean true if the player has the key to unlock the object in his inventory
	local function playerHasKey()
		if objectHasKey() then
			logDebug(string.format("Target %s has key %s", target, target.lockNode.key))

			return tes3.getItemCount({
				reference = tes3.player,
				item = target.lockNode.key
			}) > 0
		else
			return false
		end
	end

	currentTarget.target = target

	destroyWindow()

	logDebug(string.format("getLockpick: target %s (%p)", target, target))

	local items = searchTools(false, tes3.getLockLevel({ reference = target }))

	-- If no tool available just display a message
	local next = next
	if next(items) == nil then
		-- manage objectHasKey
		--TODO modify text depending on objectType
		if config.hintKeyExists and objectHasKey() then
			tes3.messageBox("You don't have good enough lockpicks but a key exists to unlock")
		else
			tes3.messageBox("You don't have good enough lockpicks in your inventory")
		end
		restoreWeapon()
		return
	end

	createWindow(items)
	updateTitle(false)
	highLightTool()
end


local function getProbe(target)
	currentTarget.target = target

	destroyWindow()

	logDebug(string.format("getProbe: target %s (%p)", target, target))

	local items = searchTools(true, target.lockNode.trap.magickaCost)

	-- If no tool available just display a message
	local next = next
	if next(items) == nil then
		tes3.messageBox("You don't have probes in your inventory")
		-- case exhauted probe
		restoreWeapon()
		return
	end

	createWindow(items)
	updateTitle(true)
	highLightTool()
end




---@param e any event object
local function onUnequippedBis(e)
	if not config.modEnabled then
		return
	end

	if currentTarget.target == nil then
		return
	end

	-- other item equipped
	if (currentMenu.currentEquippedTool) == nil or (e.item ~= currentMenu.currentEquippedTool) then
		logDebug(string.format("onUnequippedBis: Skipping - item %s (%p)", e.item.name, e.item))
		return
	end

	currentMenu.currentEquippedTool = nil

	if (e.itemData.condition > 0) then
		-- case disarm or unlock ?
		logDebug(string.format("onUnequippedBis: tool %s OK, condition %d", e.item.name, e.itemData.condition))

		--TODO Pb quand on change d'arme => unequipped lockpick => getLockpick
		if tes3.getLocked({ reference = currentTarget.target }) then
			if not currentMenu.isEquipping then
				getLockpick(currentTarget.target)
			end
		else
			restoreWeapon()
		end
	else
		-- broken tool
		-- condition = 0
		logDebug(string.format("onUnequippedBis: Broken tool %s", e.item.name))

	if tes3.getTrap({ reference = currentTarget.target }) then
			getProbe(currentTarget.target)
		elseif tes3.getLocked({ reference = currentTarget.target }) then
			getLockpick(currentTarget.target)
		else
			restoreWeapon()
		end
	end
	-- 2 cases
	-- object still trapped/locked
	-- dans le cas où on est obligé de reprendre un object du même type => quelque chose à faire en particulier ?
end


---@param e any activationTargetChanged event object
local function onActivationTargetChangedBis(e)
	local target=nil

	-- TODO returns key instead ?
	---Check if a key exists for this door/container
	---@return boolean true is there is a key to open the door/container
	local function objectHasKey()
		if (target == nil) or (target.lockNode == nil) then
			return false
		else
			return target.lockNode.key ~= nil
		end
	end

	---Check if the player has the k to unlock the object
	---@return boolean true if the player has the key to unlock the object in his inventory
	local function playerHasKey()
		if objectHasKey() then
			logDebug(string.format("Target %s has key %s", target, target.lockNode.key))

			return tes3.getItemCount({
				reference = tes3.player,
				item = target.lockNode.key
			}) > 0
		else
			return false
		end
	end

	local function isProbeEquipped()
		return tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe })
	end

	local function isLockpickEquipped()
		return tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.lockpick })
	end

	if not config.modEnabled then
		return
	end

	logDebug(string.format("Event onActivationTargetChangedBis: Current = %p and Previous = %p", e.current, e.previous))

	-- currently equiping tool no need to do something
	if currentMenu.isEquipping then
		return
	end

	if e.current == nil then
		destroyWindow()
		return
	end

	target = e.current		-- e.item is tes3baseObject
	if (target.object.objectType ~= tes3.objectType.container) and (target.object.objectType ~= tes3.objectType.door) then
		destroyWindow()
		return
	end

	if tes3.getTrap({ reference = target }) then
		-- Trapped
		logDebug(string.format("onActivationTargetChangedBis: trapped"))
		if not isProbeEquipped() then
			--
			getProbe(target)
		end
	elseif tes3.getLocked({ reference = target }) then
		-- Locked
		logDebug(string.format("onActivationTargetChangedBis: locked"))
		--TODO move playerHasKey to getLockpick
		if not playerHasKey() then
			if not isLockpickEquipped() then
				--
				getLockpick(target)
			end
		else
			if not config.usePlayerKey then
				getLockpick(target)
			end
		end
	else
		-- Not trapped or locked
		logDebug(string.format("onActivationTargetChangedBis: %s Not trapped or locked", target))
		destroyWindow()

		if target == currentTarget.target then
			-- final state: the object is disarmed and unlocked
			-- may be can unregister unequipped event
			resetCurrentTarget()
			restoreWeapon()
		end
	end
end


-- TODO isolate in a dedicated function for use on unEuipped
-- same target
--   trapped -> disarmed
--     locked => display menu
--     unlocked => returns
--[[

Plusieurs cas

	- Target nil
		destroyed ?
	- Same target
	- New target
		Destroy Window
		tool still equipped ? => restoreWeapon
		Test trapped/locked	door/container

]]
---Event fired when a target changes or a target is disarmed or unlocked (target nil)
---https://mwse.github.io/MWSE/events/activationTargetChanged/
---@param e any activationTargetChanged event object
local function onActivationTargetChanged(e)
	if not config.modEnabled then
		return
	end

	logDebug(string.format("Event onActivationTargetChanged: Current = %p and Previous = %p", e.current, e.previous))

	-- FIXME quand un probe/lockpick est cassé (condition=0) => onActivationTargetChanged avec current = nil
	-- e.current is a tes3reference
	if e.current == nil then
		logDebug(string.format("onActivationTargetChanged - No object"))
		--resetCurrentTarget()
		destroyWindow()
		return
	end

	-- check new object actived
	-- TODO refactor test
	-- TODO traiter le cas ou currentTarget.target est nil auparavant (pas sur un objet trapped/unlocked)
	if e.current ~= nil	 then
		if e.current ~= currentTarget.target then
			-- New target activated (target not nil and not the current)
			resetCurrentTarget()
			-- destroy the menu (may be already deleted)
			destroyWindow()

			-- exit if not door or container
			if (e.current.object.objectType ~= tes3.objectType.container) and (e.current.object.objectType ~= tes3.objectType.door) then
				return
			end

			-- check trap / lock ? voir si cela pose problème pour la détection de la fin disarm/unlock
		else
			-- destroy the menu (may be already deleted)
			destroyWindow()

			-- check if we still have the last selected tool still equipped if so restore weapon if not already done (flag in restoreWeapon)

			-- en revanche ne pas faire de resetCurrentTarget() pour les cas des outils cassé mais
			-- à traiter dans l'event unequipped car pas d'event onActivationTargetChanged
		end
	end

	manageCurrentTarget(e.current)
end


--#endregion


--[[
	constructor
]]

--- Initialization register the events and the GUID for menu
local function initialize()
	-- registers needed events, better to use tes.event reference instead of the name https://mwse.github.io/MWSE/references/events/
	--event.register(tes3.event.activationTargetChanged, onActivationTargetChanged)
	event.register(tes3.event.activationTargetChanged, onActivationTargetChangedBis)

	--event.register(tes3.event.unequipped, onUnequipped)
	event.register(tes3.event.unequipped, onUnequippedBis)
	event.register(tes3.event.menuEnter, onMenuEnter)

	-- TODO register only when menu is displayed
	event.register(tes3.event.keyDown, onKeyDown, { filter = config.selectionKey.keyCode })

	event.register(tes3.event.activate, onActivate)

	-- DEBUG to delete after
	event.register(tes3.event.lockPick, onLockPick)
	event.register(tes3.event.trapDisarm, onTrapDisarm)

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

	local catSettings = page:createCategory("General Settings")

	catSettings:createYesNoButton {
		label = "Equip the worst condition tool",
		description = "Equip the worst condition tool (already used) to prevent having too many used tools",
		variable = createtableVar("useWorstCondition"),
		defaultSetting = true,
	}

    catSettings:createYesNoButton {
		label = "Display chance to unlock or disarm",
		description = "Compute the chance to unlock the door/container to display only usable lockpicks",
		variable = createtableVar("diplayChance"),
		defaultSetting = true,
	}

	local catLock = page:createCategory("Lock / Lockpick Settings")

    catLock:createYesNoButton {
		label = "Hint - tell if there is a key to open",
		description = "Gives the player a hint ",
		variable = createtableVar("hintKeyExists"),
		defaultSetting = false,
	}

    catLock:createYesNoButton {
		label = "Display lockpick usable when rested",
		description = "Add to the selection menu lockpicks that are not usable to unlock at the current fatigue but usable when rested",
		variable = createtableVar("selectUsableFullFatigue"),
		defaultSetting = false,
	}

    catLock:createYesNoButton {
		label = "Use key in inventory",
		description = "If the player has the key to unlock in his inventory, don't open the lockpick menu",
		variable = createtableVar("usePlayerKey"),
		defaultSetting = true,
	}

	-- https://easymcm.readthedocs.io/en/latest/components/settings/classes/KeyBinder.html
	catSettings:createKeyBinder {
		label = "Assign key for tool selection",
		description = "Assign key for tool selection. Need to restart the game to apply the change",
		allowCombinations = true,
		defaultSetting = {
			keyCode = tes3.scanCode.space,
			--These default to false
			isShiftDown = false,
			isAltDown = false,
			isControlDown = false,
		},
		variable = createtableVar("selectionKey")
	}
	mwse.mcm.register(template)
end

event.register(tes3.event.modConfigReady, registerModConfig)

--#endregion