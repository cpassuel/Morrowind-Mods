--[[
	Quick Security
	@author		
	@version	0.60
	@changelog	0.60 Initial version
    
	TODO add haskey
	FIXME probe/lockpick unequipped => car trap activated => plus utile
	FIXME trap actived just afer tool selection => tool not equipped fast enough => équiper l'outil et retarder la fermeture du menu
	(attention aux multiples events onKeyDown => besoin d'un flag fermenuture en cours un faire le unregister avant ?

--]]

-- mod informations
local modName = "Quick Security"
local modFolder = "QuickSecurity"	-- this way can have a different name for the mod folder
local modVersion = "V0.60"
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
	weaponDrawn = false,
	weaponReady = false,
	castReady = false,
	isEquipping = false,
	isProbe = false,
}

-- keep information about the target (container/door trapped or locked or both)
local currentTarget = {
	target = nil,
	isTrapped = false,
	isLocked = false,
	--isDisaring
	--isUnlocking
	isClosing = false,
}

-- TODO rename in playerInformation
local playerAttribute = {
	agility=0,
	luck=0,
	security=0,
	--
	currentFatigue=0,
	maxFatigue=0,
	fatigueTerm = 0,
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
-- TODO Add key bind variable
local modDefaultConfig = {
	modEnabled = true,
	--
	useWorstCondition = true,	-- true => use worst condition tool (already used), false best condution (maybe put a 3 states value: worst, don't care, best)
    computeChance = true,
	hintKeyExists = false,
    minQuality = 10,
	--TODO add variable (+rename)
-- "myKeybind":{
--     "keyCode":57,
--     "isShiftDown":false,
--     "isAltDown":false,
--     "isControlDown":false
--   },
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
---@param msg string to be logged as Info in MWSE.log
local function logInfo(msg)
	-- https://www.lua.org/pil/5.2.html
	-- TODO get ride of string.format in calling 
	--s = string.format('[' .. modName .. '] ' .. 'INFO ' .. fmt, unpack(arg))
	--mwse.log(s)
	mwse.log('[' .. modName .. '] ' .. 'INFO ' .. msg)
end


---Log a message to MWSE.log if debug mode is enabled
---@param msg string to be logged as Info in MWSE.log
local function logDebug(msg)
	if (config.debugMode) then
		mwse.log('[' .. modName .. '] ' .. 'DEBUG ' .. msg)
	end
end


---Log an error message to MWSE.log
---@param msg string to be logged as Error in MWSE.log
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
	-- at full fatigue, playerAttribute.fatigueTerm = playerAttribute.fFatigueBase
	-- TODO compute 0.2 * pcAgility + 0.1 * pcLuck + securitySkill
end


--- Compute the minimal lockpick quality for the given locklevel at current fatigue and at max fatigue
---@param locklevel number level of the lock to unlock
---@return number minimal lockpick quality for the given locklevel
-- chance to successfully unlock
-- ((Security + (Agility/5) + (Luck/10)) * Lockpick multiplier * (0.75 + 0.5 * Current Fatigue/Maximum Fatigue) - Lock Level)%
-- 2 partie ind�pendantes Security + (Agility/5) + (Luck/10)) et (0.75 + 0.5 * Current Fatigue/Maximum Fatigue)
-- formule qui renvoie 2 r�sultats % avec current fatigue et % avec full fatigue
-- input Lockpick multiplier (from inventory) et Lock Level
--TODO rewrite formulas
--TODO delete
-- https://riptutorial.com/lua/example/4082/multiple-results
local function getMinLockPickMultiplier(locklevel)
	local lpQualCurFatigue, lpQualMaxFatigue

	getPlayerStats()

	-- -- lpmulmintcurrent = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5 * fatcurrent/fatmax)
	lpQualCurFatigue = locklevel / ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue))
	-- -- lpmultminfull = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5)
	-- lpQualMaxFatigue = locklevel / ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * (0.75 + 0.5))

	-- return lpQualCurFatigue, lpQualMaxFatigue
	return lpQualCurFatigue
end


---Compute the chance to unlock a door/container given the toolQuality and the locklevel in parameter
---@param toolQuality number quality of the lockpick
---@param locklevel number level of the lock
---@return number chance to unlock (can be negative)
local function getUnlockChance(toolQuality, locklevel)
	-- Lockpick
	-- x = 0.2 * pcAgility + 0.1 * pcLuck + securitySkill
	-- x *= pickQuality * fatigueTerm
	-- x += fPickLockMult * lockStrength

	getPlayerStats()

	local chance = (playerAttribute.agility/5 + playerAttribute.luck/10 + playerAttribute.security) * toolQuality * playerAttribute.fatigueTerm + playerAttribute.fPickLockMult * locklevel
	logDebug(string.format("Unlock chance %.2f", chance))
	--TODO add a max(0, chance) ?
	return chance
end


---Compute the chance to disarm a door/container given the probe quality and the magickaCost in parameter
---@param toolQuality number quality of the probe
---@param magickaCost number *level* of the trap
---@return number chance to disarm the trap
local function getDisarmChance(toolQuality, magickaCost)
	-- Disarm
	-- x = 0.2 * pcAgility + 0.1 * pcLuck + securitySkill
	-- x += fTrapCostMult * trapSpellPoints
	-- x *= probeQuality * fatigueTerm

	getPlayerStats()

	local chance = ((playerAttribute.agility/5 + playerAttribute.luck/10 + playerAttribute.security) + (playerAttribute.fTrapCostMult * magickaCost)) * toolQuality * playerAttribute.fatigueTerm
	logDebug(string.format("Disarm chance %.2f", chance))
	return chance
end


-- TODO implement current & maxFatigue quality
-- TODO use a different color for lockpicks needing full fatigue ?
-- TODO compute chance and add in toolsTable[toolName] => need level of trap/lock
--- Search in the inventory for lockpicks or probes with a minimal quality
---@param searchProbes boolean true to search probes, false to search lockpicks
---@param minQual number minimal quality of the tool requested
---@return table unsorted table of tables with one entry par tool with quality information, can be nil if no tool found
local function searchTools(searchProbes, minQual)
	local inventory = tes3.player.object.inventory

	-- TODO add function to compute chance (current and max), so minQual not needed, pass level instead

	local toolsTable = {}
	local objectTypeToSearch

	if searchProbes then
		objectTypeToSearch = tes3.objectType.probe
	else
		objectTypeToSearch = tes3.objectType.lockpick
	end

	-- no need to search for tool condition as it will be defined when equipping
	--TODO try to count objects, when used and not used, sereval entry in inventory or only one ? 
	for _, stack in pairs(inventory) do
		if stack.object.objectType == objectTypeToSearch then
			local tool = stack.object	-- tes3lockpick or tes3probe
			local toolName = tool.name
			local toolQuality = tool.quality

			logDebug(string.format("searchTools: Found probe %s - %p (%.2f)",toolName, tool, toolQuality))

			-- check min quality
			-- TOOD check chance > 0
			if toolQuality >= minQual then
				-- add only one *type* of tool
				if (toolsTable[toolName] == nil) then
					toolsTable[toolName]={}
					toolsTable[toolName].name = toolName
					toolsTable[toolName].tool = tool
					toolsTable[toolName].quality = toolQuality
					-- 
					if searchProbes then
						toolsTable[toolName].type = tes3.objectType.probe
					else
						toolsTable[toolName].type = tes3.objectType.lockpick
					end
					logDebug(string.format("searchTools: Adding tool %s - %p (%.2f)",toolName, tool, toolQuality))
				end
			end
		end
	end

	return toolsTable
end


---comment
local function storeWeapon()
	-- TODO test on isWeaponAStateStored ?
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


	--TODO add a delay before equiping
	-- check prerequisites
	logDebug(string.format("restoreWeapon %s - %p", currentMenu.weapon, currentMenu.weapon))

	if currentMenu.isWeaponAStateStored then
		logDebug(string.format("isWeaponAStateStored"))
		-- need a timer to give time to unequip the probe/lockpick
		-- TODO secure it by cancelling when there is already a timer started
		-- FIXME weapon always drawn then go back to desired state
		-- TODO use a double timer ? first weaponReady = false then equip then restore weaponReady

		-- DEBUG test unequip first
		tes3.mobilePlayer.weaponReady = false
		tes3.mobilePlayer.castReady = false
		local objectType
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
		-- timer.start({
		-- 	duration = .5,
		-- 	iterations = 1,
		-- 	callback = function()
				tes3.mobilePlayer:equip({ item = currentMenu.weapon, selectBestCondition = true })
				tes3.mobilePlayer.castReady = currentMenu.castReady
				tes3.mobilePlayer.weaponReady = currentMenu.weaponReady
				-- DEBUG
				--tes3.mobilePlayer.castReady = false
				--tes3.mobilePlayer.weaponReady = false
				currentMenu.isWeaponAStateStored = false
				logDebug(string.format("restoreWeapon: timer callback"))
		-- 	end
		-- })
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

]]

-- TODO try to reorganize functions
-- forward functions declaration
local onMouseWheel, destroyWindow

-- https://mwse.github.io/MWSE/events/uiActivated/#event-data
local function uiActivatedCallback(e)
	logDebug(string.format("uiActivatedCallback %s", e.element))
	-- TODO Destroy menu
end


---Equip the selected tool in the menu
local function equipSelectedTool()

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
	local function getIsProbe()
		local menu = tes3ui.findMenu(GUIID_Menu)
		local titleBlock = menu:findChild(GUIID_TestUI_TitleBlock)
		return titleBlock:getPropertyBool(modName .. ":isProbe")
	end

	currentMenu.isEquipping = true

    local item = retrieveSelectedTool()
    logDebug(string.format("equipSelectedTool: selected item %s", item))

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


--Update the menu title depending on the type of tool in parameter
---@param isProbe boolean true if looking for probe false for lockpick
local function updateTitle(isProbe)
	local objectType
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

		-- Item icon block
		local icon = toolBlock:createImage({path = "icons\\" .. toolsTable[v].tool.icon})
		icon.borderRight = 5

		-- Item label text
		--TODO add logic to display chances
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

		--TODO voir quand l'utiliser (cf. quick loot)
		-- https://mwse.github.io/MWSE/apis/tes3ui/?h=leaveme#tes3uileavemenumode
        --tes3ui.leaveMenuMode()
        menu:destroy()
    end
end


--[[

	event handlers

]]

--#region events handler


-- https://mwse.github.io/MWSE/apis/event/#eventregister
-- event.register(tes3.event.keyDown, onKeyDown, { filter = tes3.scanCode.space })
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
	logDebug(string.format("MenuEnter"))
	destroyWindow()
end


---Manage action on a non nil target
---@param target any activated target
local function manageCurrentTarget(target)
	logDebug(string.format("manageCurrentTarget"))

	local searchForProbe = false

	-- currently equiping tool no need to do something
	if currentMenu.isEquipping then
		return
	end

	-- TODO Refactor the 3 branches of the test
	-- check if same target => meaning it has been disarmed or unlocked
	if (currentTarget.target == target) then
		-- same target so it is a door or a container
		-- case tool broken
		logDebug(string.format("onActivationTargetChanged with same target %s - %p", target, target))

		-- TODO rewrite tests
		-- DEBUG
		logDebug(string.format("target %s (trapped %s)", target, tes3.getTrap({ reference = target })))

		if tes3.getTrap({ reference = target }) then
			logError(string.format("Same target but still trapped %s - %p", target, target))
			-- TODO check probe equipped
			if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe }) then
				logDebug(string.format("manageCurrentTarget - Probe already equipped"))
				return
			end
			searchForProbe = true
			currentTarget.isTrapped = true
		else
			if not tes3.getLocked({ reference = target }) then
				-- final state: the object is disarmed and unlocked
				-- maby becan unregister unequipped event
				resetCurrentTarget()
				restoreWeapon()
				return
			else
				-- locked
				logError(string.format("Same target but still locked %s - %p", target, target))
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

	local minQuality = 0
	if not searchForProbe then
		-- compute min quality
		-- https://mwse.github.io/MWSE/apis/tes3/#tes3getlocklevel
		minQuality = getMinLockPickMultiplier(tes3.getLockLevel({ reference = target }))
		logDebug(string.format("getMinLockPickMultiplier %.2f", minQuality))

		getUnlockChance(1.1, tes3.getLockLevel({ reference = target }))
	end

	local items = searchTools(searchForProbe, minQuality)
	currentTarget.target = target

	-- If no tool available just display a message
	local next = next
	if next(items) == nil then
		if searchForProbe then
			tes3.messageBox("You don't have probes")
		else
			tes3.messageBox("You don't have lockpicks or your lockpicks are not good enough to unlock")
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
			-- que faire quand condition > 0 ??? rien ?
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
			resetCurrentTarget()
			destroyWindow()
		else
		-- si nil que faire ? destroyWindow() ne pose pas de problème car à priori déjà detruit
		-- en revanche ne pas faire de resetCurrentTarget() pour les cas des outils cassé mais
		-- à traiter dans l'event unequipped car pas d'event onActivationTargetChanged
		destroyWindow()
		end
	end

	-- TODO test new activated object (door/container)

	manageCurrentTarget(e.current)

	-- TODO isolate this part in a dedicated function
	-- local searchForProbe = false

	-- -- check if same target => meaning it has been disarmed or unlocked
	-- if (currentTarget.target == e.current) then
	-- 	-- same target so it is a door or a container
	-- 	logDebug(string.format("onActivationTargetChanged with same target %s - %p", e.current, e.current))

    --     if tes3.getTrap({ reference = e.current }) then
	-- 		logError(string.format("Same target but still trapped %s - %p", e.current, e.current))
    --         return
    --     end

    --     if not tes3.getLocked({ reference = e.current }) then
    --         -- final state: the object is disarmed and unlocked
	-- 		resetCurrentTarget()
    --         restoreWeapon()
    --         return
    --     else
    --         -- locked
	-- 		logError(string.format("Same target but still locked %s - %p", e.current, e.current))
    --         currentTarget.isTrapped = false
    --         currentTarget.isLocked =true
    --         searchForProbe = false
    --     end
	-- else
	-- 	-- New target, check if it's a door / container
	-- 	if (e.current.object.objectType ~= tes3.objectType.container) and (e.current.object.objectType ~= tes3.objectType.door) then
	-- 		resetCurrentTarget()
    --         return
    --     end

	-- 	-- https://mwse.github.io/MWSE/apis/tes3/#tes3gettrap (returns nil if not trapped)
    --     if tes3.getTrap({ reference = e.current }) then
    --         -- test if probe equipped
    --         -- https://mwse.github.io/MWSE/apis/tes3/#tes3getequippeditem
    --         if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.probe }) then
    --             logDebug(string.format("Probe already equipped"))
    --             return
    --         end
    --         currentTarget.isTrapped = true
    --         searchForProbe = true
    --     else
	-- 		-- https://mwse.github.io/MWSE/apis/tes3/#tes3getlocked (returns true if locked)
    --         if tes3.getLocked({ reference = e.current }) then
    --             -- check for an equipped lockpick
    --             if tes3.getEquippedItem({ actor = tes3.player, objectType = tes3.objectType.lockpick }) then
    --                 logDebug(string.format("lockpick already equipped"))
    --                 return
    --             end

    --             currentTarget.isLocked = true
    --             searchForProbe = false
    --         else
    --             -- not locked and not trapped => exit
	-- 			resetCurrentTarget()
    --             return
    --         end
    --     end
    -- end

    -- -- trapped or locked and no related tool equipped

    -- local minQuality = 0
    -- if not searchForProbe then
    --     -- compute min quality
	-- 	-- https://mwse.github.io/MWSE/apis/tes3/#tes3getlocklevel
	-- 	minQuality = getMinLockPickMultiplier(tes3.getLockLevel({ reference = e.current }))
	-- 	logDebug(string.format("getMinLockPickMultiplier %.2f", minQuality))
    -- end

    -- local items = searchTools(searchForProbe, minQuality)
    -- currentTarget.target = e.current

    -- -- If no tool available just display a message
    -- local next = next
    -- if next(items) == nil then
    --     if searchForProbe then
    --         tes3.messageBox("You don't have probes")
    --     else
    --         tes3.messageBox("You don't have lockpicks or your lockpicks are not good enough to unlock")
    --     end
    --     return
    -- end

    -- -- TODO check if destroy menu is needed
    -- -- TODO remove dead code
    -- if currentTarget.target == nil then
	-- 	resetCurrentTarget()	-- may be not necessary
	-- 	destroyWindow()
	-- 	return
	-- end

	-- logDebug(string.format("Container/door %s (%p) - trapped %s, locked %s", currentTarget.target, currentTarget.target, currentTarget.isTrapped, currentTarget.isLocked))

    -- createWindow(items)
	-- updateTitle(searchForProbe)
    -- highLightTool()
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

	-- DEBUG
	event.register(tes3.event.lockPick, onLockPick)
	event.register(tes3.event.trapDisarm, onTrapDisarm)
	event.register(tes3.event.activate, onActivate)

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
		label = "Display chance to unlock or disarm",
		description = "Compute the chance to unlock the door/container to display only usable lockpicks",
		variable = createtableVar("computeChance"),
		defaultSetting = true,
	}

    catSettings:createYesNoButton {
		label = "Hint - tell if there is a key to open",
		description = "Gives the player a hint ",
		variable = createtableVar("hintKeyExists"),
		defaultSetting = false,
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
		variable = createtableVar("myKeybind") --TODO rename variable
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