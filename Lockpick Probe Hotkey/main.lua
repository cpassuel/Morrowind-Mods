--[[
	Lockpick and Probe Hotkey
	@author		cpassuel
	@version	
	@changelog	1.0 Initial version
]]--


-- Informations about the mod
local modName = "Lockpick and Probe Hotkey"
local modVersion = "V1.0"
local modConfig = "LockPickProbeHotkey"
local modAuthor= "cpassuel"


--[[
	Ideas
	
	In case of no usable lockpick check formula with full fatigue restaured and write message if ok
	
	Gestion de Hidden trap
	
	mininalUnlockChance
	
	Lockpick : equiper le lockpick minimal qui permet de dévérouiller
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

-- TODO calculer la quality minimale du lockpick pour le niveau de lock donné
--[[
	event handlers 
]]

-- Called when the player looks at a new object that would show a tooltip, or transfers off of such an object.
-- keep track of object looked at by the player
local function onActivationTargetChanged(e)
	activatedTarget = e.current
end


--
local function getPlayerStats()
	-- sklil et attributes
	local player = tes3.mobilePlayer
	
	playerAttribute.security = player.security.current
	playerAttribute.agility = player.agility.current
	playerAttribute.luck = player.luck.current

	playerAttribute.currentFatigue = player.fatigue.current
	playerAttribute.maxFatigue = player.fatigue.base
end


-- 1262702412 	LOCK 	Lockpick
-- 1112494672 	PROB 	Probe
-- return a lockpick with a minimium quality
-- https://en.uesp.net/wiki/Morrowind:Security
local function getLockpick(minQuality)
	local inventory = tes3.player.object.inventory

    for _, v in pairs(inventory) do
        if v.object.objectType == 1262702412 then
			--mwse.log("object = %s - %s - %d", v.object.name, v.object.objectType, v.count)
			if v.object.quality >= minQuality then
				-- Warning quality is a float value
				mwse.log("Lockpick %s quality %f Condition %d", v.object.name, v.object.quality , v.object.condition)
				return v.object
			end
        end
    end
	return nil
end


--
local function getProbe()
	local inventory = tes3.player.object.inventory

    for _, v in pairs(inventory) do
        if v.object.objectType == 1112494672 then
			if v.object.quality >= minQuality then
				-- Warning quality is a float value
				mwse.log("Probe %s quality %f Condition %d", v.object.name, v.object.quality , v.object.condition)
				return v.object
			end
        end
    end
	return nil
end


-- returns the minimal lockpick quality for the given locklevel
local function getMinLockPickMultiplier(locklevel)
	getPlayerStats()

	-- lpmultminfull = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5)
	-- lpmulmintcurrent = locklevel / (security + agility/5 + luck/10) / (0.75 + 0.5 * fatcurrent/fatmax)
	return locklevel / ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue))
end


-- return can be negative
local function	getLockpickChance(locklevel, lpmult)
	local chancecurrent,chancefull

	getPlayerStats()

	-- ((Security + (Agility/5) + (Luck/10)) * Lockpick multiplier * (0.75 + 0.5 * Current Fatigue/Maximum Fatigue) - Lock Level)
	chancecurrent = ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * lpmult * (0.75 + 0.5 * playerAttribute.currentFatigue/playerAttribute.maxFatigue)) - locklevel
	chancefull = ((playerAttribute.security + playerAttribute.agility/5 + playerAttribute.luck/10) * lpmult * (0.75 + 0.5)) - locklevel
	return chancecurrent
end


--
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

-- 
local function onMouseButtonDown(e)
	if tes3.menuMode() then
		return
	end
	
	if (e.button ~= 2) then
		return
	end
	
	if activatedTarget ~= nil then
		if (activatedTarget.object.objectType == tes3.objectType.container) or (activatedTarget.object.objectType == tes3.objectType.door) then
			-- door or container
			local lockNode = activatedTarget.lockNode	-- peut être nil si pas locked, à verifier pour trapped
			if lockNode ~= nil then
				local isLocked = (lockNode.locked)
				local isTrapped = (lockNode.trap ~= nil)
				local isKeyLock = (lockNode.key ~= nil)
			
				equipLockPick(getLockpick(level))
				getPlayerStats()
			
				if isLocked and isTrapped then
					-- locked and trapped
					--tes3.messageBox("Trapped and Lock Level: " .. lockNode.level)
				else
					if isLocked then
						-- only locked
						--tes3.messageBox("Lock Level: " .. lockNode.level)
						tes3.messageBox("Unlock chance %6.2f", getLockpickChance(lockNode.level, 1.1))
					elseif isTrapped then
						-- only trapped
						--tes3.messageBox("Trapped")
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
		description = "Allows you to Enable or Disable the mod",
		variable = createtableVar("modEnabled"),
		defaultSetting = true,
	}
	
	mwse.mcm.register(template)
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
event.register("modConfigReady", registerModConfig)