--[[
	Lockpick and Probe Hotkey
	@author		cpassuel
	@version	
	@changelog	0.20 Initial version
]]--


-- Informations about the mod
local modName = "Lockpick and Probe Hotkey"
local modVersion = "V0.20"
local modConfig = "LockPickProbeHotkey"
local modAuthor= "cpassuel"


--[[
	Ideas
	
	In case of no usable lockpick check formula with full fatigue restaured and write message if ok
	
	Gestion de Hidden trap => MCP
	
	mininalUnlockChance (add a fail back option ?)
	
	Lockpick : equiper le lockpick minimal qui permet de d�v�rouiller

	Probe = option to specify not to use the lowest level
]]

--[[
	Infos

	https://en.uesp.net/wiki/Morrowind:Security
	https://www.nexusmods.com/morrowind/mods/48634 Visible Persuasion Chance

	local fFatigueBase = tes3.findGMST(1006).value
	local fFatigueMult = tes3.findGMST(1007).value
	-- -- fatigueTerm is 1.25 at full fatigue and 0.75 at 0 fatigue
	local fatigueTerm = fFatigueBase - fFatigueMult * (1 - tes3.mobilePlayer.fatigue.normalized)
]]


--[[
	Variables
]]
local activatedTarget = nil
local hiddenTraps = false	-- MCP option

local playerAttribute = {
	agility=0,
	luck=0,
	security=0,
	--
	currentFatigue=0,
	maxFatigue=0,
}


--[[
	mod config
]]


-- Define mod config package
local modDefaultConfig = {
	modEnabled = true,
	--
	--hiddenTraps = false,	-- MCP option to hide traps Retrieve from MCP
	useSkeletonKey = false,
	hintKeyExists = false,
	-- hotkey mapping 
	probeHotkey = 0,
	lockpickHotkey = 0,
	mininalUnlockChance = 0,	-- equip a lockpick with a minimal unlock chance
	probeQuality = 0,	-- which probe use, meduim quality fisrt ?
	--
	debugMode = false
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
	log helper functions
]]


--- Log a message to MWSE.log if debug mode is enabled
-- @param msg string to be logged as Info in MWSE.log
local function logDebug(msg)
	if (config.debugMode) then
		mwse.log('[' .. modName .. '] ' .. 'DEBUG ' .. msg)
	end
end


--[[
	Helper functions
]]

-- chance to successfully unlock
-- ((Security + (Agility/5) + (Luck/10)) * Lockpick multiplier * (0.75 + 0.5 * Current Fatigue/Maximum Fatigue) - Lock Level)%
-- 2 partie ind�pendantes Security + (Agility/5) + (Luck/10)) et (0.75 + 0.5 * Current Fatigue/Maximum Fatigue)

-- formule qui renvoie 2 r�sultats % avec current fatigue et % avec full fatigue
-- input Lockpick multiplier (from inventory) et Lock Level
-- https://riptutorial.com/lua/example/4082/multiple-results

-- recuperer les infos du joueur
-- https://mwse.readthedocs.io/en/latest/lua/type/tes3mobilePlayer.html
-- https://mwse.readthedocs.io/en/latest/lua/type/tes3statistic.html

-- TODO calculer la quality minimale du lockpick pour le niveau de lock donn�


--[[
	event handlers 
]]


--- Compute and save current player stats 
local function getPlayerStats()
	-- skill et attributes
	local player = tes3.mobilePlayer
	
	playerAttribute.security = player.security.current
	playerAttribute.agility = player.agility.current
	playerAttribute.luck = player.luck.current

	playerAttribute.currentFatigue = player.fatigue.current
	playerAttribute.maxFatigue = player.fatigue.base
end


--- returns a lockpick with a minimium quality (current quality between 1.0 and 5.0)
-- https://en.uesp.net/wiki/Morrowind:Security
-- @param minQuality minimal quality of the lockpick to retrieve
-- @return nil if no lockpick of the minimal quality is found or else the lockpick
local function getLockpick(minQuality)
	local inventory = tes3.player.object.inventory
	local curLockPick = nil
	local curQuality = 0

    -- loop over inventory to find the lowest
	for _, v in pairs(inventory) do
        if v.object.objectType == tes3.objectType.lockpick then
			--mwse.log("object = %s - %s - %d", v.object.name, v.object.objectType, v.count)
			if v.object.quality >= minQuality then
				-- TODO Warning can return a too good lockpick => rechercher le lockpick de quality minimal pour le 
				-- Warning quality is a float value
				-- save the lockpick and its quality
				logDebug(string.format("Found lockpick %s quality %f Condition %d", v.object.name, v.object.quality , v.object.condition))

				if (curLockPick == nil) or (v.object.quality < curQuality)  then
					curLockPick = v.object
					curQuality = v.object.quality
				end
			end
        end
    end

	-- TODO check the logDebug if curLockPick = nil
	logDebug(string.format("Returning lockpick %p", curLockPick))
	return curLockPick
end


--- Search for a probe of the minimal quality
-- @param minQuality
-- @return the probe or nil if not found
local function getProbe(minQuality)
	local inventory = tes3.player.object.inventory

    for _, v in pairs(inventory) do
        if v.object.objectType == tes3.objectType.probe then
			if v.object.quality >= minQuality then
				-- Warning quality is a float value
				logDebug(string.format("Probe %s quality %f Condition %d", v.object.name, v.object.quality , v.object.condition))
				return v.object
			end
        end
    end
	return nil
end


--- Compute the minimal lockpick quality for the given locklevel
-- @param locklevel level of the lock to unlock
-- @returns minimal lockpick quality for the given locklevel
local function getMinLockPickMultiplier(locklevel)
	getPlayerStats()

	-- lpmultminfull = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5)
	-- lpmulmintcurrent = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5 * fatcurrent/fatmax)
	return locklevel / ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue))
end


--- Compute the chance to unlock a container 
-- return can be negative
-- @param locklevel level of the lock to unlock
-- @param lpmult
-- @return 
local function	getLockpickChance(locklevel, lpmult)
	local chancecurrent,chancefull

	getPlayerStats()

	-- ((Security + (Agility/5) + (Luck/10)) * Lockpick multiplier * (0.75 + 0.5 * Current Fatigue/Maximum Fatigue) - Lock Level)
	chancecurrent = ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * lpmult * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue)) - locklevel
	chancefull = ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * lpmult * (0.75 + 0.5)) - locklevel
	return chancecurrent
end


--- Equip the lockpick
-- @param lp lockpick to equip
local function equipLockPick(lp)
	logDebug(string.format("Equipping lockpick %p", lp))
	if lp ~= nil then
		-- https://mwse.github.io/MWSE/types/tes3mobileActor/#equip
		tes3.mobilePlayer:equip({item = lp, selectWorstCondition=true})
		-- https://mwse.github.io/MWSE/apis/mwscript/#mwscriptequip
		--mwscript.equip{ reference = tes3.player, item = lp}
	end
end


--- Called when the player looks at a new object that would show a tooltip, or transfers off of such an object.
-- keep track of object looked at by the player
local function onActivationTargetChanged(e)
	activatedTarget = e.current
end


--
local function onKeyDown(e)
	if e.keyCode == config.probeHotkey then
	
	elseif e.keyCode == config.lockpickHotkey then
	
	end
end


--- manage OnMouseButtonEvent
--  
local function onMouseButtonDown(e)
	-- checks prerequisite
	if not config.modEnabled then
		return
	end

	if tes3.menuMode() then
		return
	end
	
	-- TODO check in combat

	-- catch only left button
	if (e.button ~= 2) then
		return
	end
	
	if activatedTarget ~= nil then
		if (activatedTarget.object.objectType == tes3.objectType.container) or (activatedTarget.object.objectType == tes3.objectType.door) then
			-- door or container
			local lockNode = activatedTarget.lockNode	-- peut �tre nil si pas locked, � verifier pour trapped
			if lockNode ~= nil then
				local isLocked = (lockNode.locked)
				local isTrapped = (lockNode.trap ~= nil)
				local isKeyLock = (lockNode.key ~= nil)

				-- TODO change workflow: check trapped first
				-- how to manage hidden trap option ?

				-- TODO check if a lockpick of minimal quality is already equiped
				-- get the minimal quality of the lockpick
				minQuality =  getMinLockPickMultiplier(lockNode.level)

				lockpick = getLockpick(minQuality)
				-- 
				if lockpick ~= nil then
					tes3.messageBox("Equiping lockpick")
					equipLockPick(lockpick)
					getPlayerStats()
				else
					tes3.messageBox("No lockpick with a quality > %6.2f", minQuality)
				end
			
				-- TODO change tests
				if isLocked and isTrapped then
					-- locked and trapped
					tes3.messageBox("Trapped and Lock Level: " .. lockNode.level)
				else
					if isLocked then
						-- only locked
						tes3.messageBox("Lock Level: " .. lockNode.level)
						tes3.messageBox("Unlock chance %6.2f", getLockpickChance(lockNode.level, 1.1)) -- why 1.1 ?
					elseif isTrapped then
						-- only trapped
						tes3.messageBox("Trapped")
					end
				end
			end
		else
			-- it's not a door or container so no need to check type again
			activatedTarget = nil
		end
	end
end


--[[
	constructor
]]

local function initialize()
	-- retrieve MCP settings
	-- https://mwse.github.io/MWSE/references/code-patch-features/
	-- https://mwse.github.io/MWSE/apis/tes3/?h=code+patch+feature#tes3hascodepatchfeature
	local state = tes3.hasCodePatchFeature(tes3.codePatchFeature.hiddenTraps)
	-- TODO check if returns 2 values
	if (state ~= nil) and (state == true) then
		hiddenTraps = true
		-- mwse.log("DEBUG MCP hiddenTraps = true") -- DEBUG
	end

	-- check tes3.codePatchFeature.hiddenLocks ?

	event.register(tes3.event.mouseButtonDown, onMouseButtonDown)
	event.register(tes3.event.activationTargetChanged, onActivationTargetChanged)
	-- TODO filter hotkeys to retrieve => needs a refresh in case of hotkey change (unregister/register)
	-- https://mwse.github.io/MWSE/events/keyDown/

	mwse.log(modName)
end
event.register(tes3.event.initialized, initialize)


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
	
	local page = template:createSideBarPage {
		label = "Sidebar",
		description = "Lock and Probe"
	}
	
	local catMain = page:createCategory(modName)
	catMain:createYesNoButton {
		label = "Enable " .. modName,
		description = "Allows you to Enable or Disable the mod",
		variable = createtableVar("modEnabled"),
		defaultSetting = true,
	}

	local catSettings = page:createCategory("Settings")
	catSettings:createYesNoButton {
		label = "Use Skeleton key",
		description = "Allows to equip Skeleton key if no other key is available or good enough to unlock the container",
		variable = createtableVar("useSkeletonKey"),
		defaultSetting = false,
	}

	catSettings:createYesNoButton {
		label = "Hint if a key exists for the object",
		description = "Tells the user that a key exists for this object if he doesn't a lockpick good enough",
		variable = createtableVar("hintKeyExists"),
		defaultSetting = false,
	}

	mwse.mcm.register(template)
end

event.register(tes3.event.modConfigReady, registerModConfig)