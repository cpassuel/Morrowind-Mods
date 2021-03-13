--[[
	Lockpick and Probe Hotkey
	@author		cpassuel
	@version	
	@changelog	0.5 Initial version
]]--


-- Informations about the mod
local modName = "Lockpick and Probe Hotkey"
local modVersion = "V0.5"
local modConfig = "LockPickProbeHotkey"
local modAuthor= "cpassuel"


--[[
	Ideas
	
	In case of no usable lockpick check formula with full fatigue restaured and write message if ok
	
	Gestion de Hidden trap
	
	mininalUnlockChance (add a fail back option ?)
	
	Lockpick : equiper le lockpick minimal qui permet de dévérouiller
	
	Probe
	Find a probe with a minimal chance to disarm item (option), with fallback to the better probe below
	this minimal quality
]]


--[[
	Infos

	https://en.uesp.net/wiki/Morrowind:Security
	https://www.nexusmods.com/morrowind/mods/48634

	local fFatigueBase = tes3.findGMST(1006).value
	local fFatigueMult = tes3.findGMST(1007).value
	-- -- fatigueTerm is 1.25 at full fatigue and 0.75 at 0 fatigue
	local fatigueTerm = fFatigueBase - fFatigueMult * (1 - tes3.mobilePlayer.fatigue.normalized)
]]


--[[
	Variables
]]
local activatedTarget = nil

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
	hiddenTraps = false,	-- MCP option to hide traps
	-- hotkey mapping 
	probeHotkey = 0,
	lockpickHotkey = 0,
	mininalUnlockChance = 0,	-- equip a lockpick with a minimal unlock chance
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
]]

-- chance to successfully unlock
-- ((Security + (Agility/5) + (Luck/10)) * Lockpick multiplier * (0.75 + 0.5 * Current Fatigue/Maximum Fatigue) - Lock Level)%
-- 2 partie indépendantes Security + (Agility/5) + (Luck/10)) et (0.75 + 0.5 * Current Fatigue/Maximum Fatigue)

-- formule qui renvoie 2 résultats % avec current fatigue et % avec full fatigue
-- input Lockpick multiplier (from inventory) et Lock Level
-- https://riptutorial.com/lua/example/4082/multiple-results

-- recuperer les infos du joueur
-- https://mwse.readthedocs.io/en/latest/lua/type/tes3mobilePlayer.html
-- https://mwse.readthedocs.io/en/latest/lua/type/tes3statistic.html


--[[
	event handlers 
]]

-- Called when the player looks at a new object that would show a tooltip, or transfers off of such an object.
-- keep track of object looked at by the player
-- @param e: event info
local function onActivationTargetChanged(e)
	activatedTarget = e.current
end


-- update the playerAttribute table
local function getPlayerStats()
	-- skill et attributes
	local player = tes3.mobilePlayer
	
	playerAttribute.security = player.security.current
	playerAttribute.agility = player.agility.current
	playerAttribute.luck = player.luck.current

	playerAttribute.currentFatigue = player.fatigue.current
	playerAttribute.maxFatigue = player.fatigue.base
end


-- returns a lockpick with a minimium quality (current quality between 1.0 and 5.0)
-- https://en.uesp.net/wiki/Morrowind:Security
-- @param minQuality: minimal quality pf the lock pick
-- @return lockpick with the minimal quality or nil
-- @return quality of the lockpick or quality of the best lockpick in inventory if no available lockpick
local function getLockpick(minQuality)
	local inventory = tes3.player.object.inventory
	local curquality
	
	curquality = 0.0	-- Warning quality is a float value
	
    for _, v in pairs(inventory) do
        if v.object.objectType == 1262702412 then	-- 1262702412 	LOCK 	Lockpick
			-- calc max available quality if no lockpick with minimal quality or current quality lockpick
			if v.object.quality > curquality then
				curquality = v.object.quality
			end
			
			if v.object.quality >= minQuality then
				mwse.log("DEBUG Lockpick %s quality %f Condition %d", v.object.name, v.object.quality , v.object.condition)
				return v.object, curquality
			end
        end
    end
	return nil, curquality
end


-- Search for the first probe in inventory
-- @return a probe or nil if none available
-- min quality 0.25 for bent probe
local function getProbe()
	local inventory = tes3.player.object.inventory

    for _, v in pairs(inventory) do
        if v.object.objectType == 1112494672 then	-- 1112494672 	PROB 	Probe
			-- TODO Warning quality is a float value
			mwse.log("DEBUG Probe %s quality %f Condition %d", v.object.name, v.object.quality , v.object.condition)
			return v.object
        end
    end
	return nil
end


-- returns the minimal lockpick quality for the given locklevel at current fatigue
-- and at max fatigue
-- @param locklevel: lock level of the container
-- @return min lockpick quality for current fatigue
-- @return min lockpick quality for max fatigue
local function getMinLockPickMultiplier(locklevel)
	local lpQualCurFatigue, lpQualMaxFatigue

	getPlayerStats()

	-- https://en.uesp.net/wiki/Morrowind:Security
	-- lpmultminfull = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5)
	-- lpmulmintcurrent = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5 * fatcurrent/fatmax)
	lpQualCurFatigue = locklevel / ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue))
	lpQualMaxFatigue = locklevel / ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * (0.75 + 0.5))

	return lpQualCurFatigue, lpQualMaxFatigue
end


-- returns the chance to unlock a container with a lockpick
-- @param locklevel: lock level of the container
-- @param lpmult: quality of the lockpick
-- @return lockpick chance for current fatigue
-- @return lockpick chance for max fatigue
local function	getLockpickChance(locklevel, lpmult)
	local chancecurrent,chancefull

	getPlayerStats()

	-- ((Security + (Agility/5) + (Luck/10)) * Lockpick multiplier * (0.75 + 0.5 * Current Fatigue/Maximum Fatigue) - Lock Level)
	chancecurrent = ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * lpmult * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue)) - locklevel
	chancefull = ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * lpmult * (0.75 + 0.5)) - locklevel
	return chancecurrent, chancefull
end


-- Equip the items in parameter
-- @param item to equip or nil
local function equipLockPick(lp)
	if lp ~= nil then
		mwscript.equip{ reference = tes3.player, item = lp}
	end
end


--
local function onKeyDown(e)
	if e.keyCode == config.probeHotkey then
	
	elseif e.keyCode == config.lockpickHotkey then
	
	end
end


-- event OnMouseButton
-- @param e: event info
local function onMouseButtonDown(e)
	if tes3.menuMode() then
		return
	end
	
	if (e.button ~= 2) then
		return
	end
	
	if not config.modEnabled then
		return
	end
	
	if activatedTarget ~= nil then
		-- check for door or container
		if (activatedTarget.object.objectType == tes3.objectType.container) or (activatedTarget.object.objectType == tes3.objectType.door) then
			-- door or container
			local lockNode = activatedTarget.lockNode	-- peut être nil si pas locked, à verifier pour trapped
			if lockNode ~= nil then
				local isLocked = (lockNode.locked)
				local isTrapped = (lockNode.trap ~= nil)
				-- https://mwse.readthedocs.io/en/latest/lua/type/tes3lockNode.html
				local isKeyLock = (lockNode.key ~= nil) -- if a key exists to unlock this item
				
				-- TODO change the code for handling both options
			
				-- get the minimal quality of the lockpick
				local minQuality, minQualityMaxFat
				minQuality, minQualityMaxFat =  getMinLockPickMultiplier(lockNode.level)

				--
				local lockpick, lpcurqual
				lockpick, lpcurqual = getLockpick(minQuality)

				if lockpick ~= nil then
					-- there is an available lockpick
					equipLockPick(lockpick)
					-- why getPlayerStats call ??? 
					getPlayerStats()
				else
					-- no lockpick so lpcurqual = max lockpick quality available
					if lpcurqual > minQualityMaxFat then
						-- TODO equip anyway ?
						tes3.messageBox("You need to regain fatigue to be able to unlock this object.")
					else
						tes3.messageBox("You don't have a good enough lockpick to unlock this object. try a spell !")
					end
				end
			
				if isLocked and isTrapped then
					-- locked and trapped
					tes3.messageBox("DEBUG Trapped and Lock Level: " .. lockNode.level)

					local probe = getProbe()
					if probe ~= nil then
						-- equip probe
						equipLockPick(probe)
					else
						tes3.messageBox("You need to find probe to disarm this object")
					end
				else
					if isLocked then
						-- only locked
						tes3.messageBox("DEBUG Lock Level: " .. lockNode.level)
						tes3.messageBox("DEBUG Unlock chance %6.2f", getLockpickChance(lockNode.level, lpcurqual))
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
	event.register("mouseButtonDown", onMouseButtonDown)
	event.register("activationTargetChanged", onActivationTargetChanged)
	-- filtrer les hotkey à récuperer => necessite un refresh en cas de changement (unregister/register)
	mwse.log(modName)
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
	
	local catLockNProbe = page:createCategory(modName)
	catLockNProbe:createYesNoButton {
		label = "Enable " .. modName,
		description = "Allows you to Enable or Disable the mod",
		variable = createtableVar("modEnabled"),
		defaultSetting = true,
	}
	
	mwse.mcm.register(template)
end

event.register("modConfigReady", registerModConfig)