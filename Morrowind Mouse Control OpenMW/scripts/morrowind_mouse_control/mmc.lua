--[[
    Morrowind Mouse Control - Open MW version

    https://openmw.readthedocs.io/en/latest/reference/lua-scripting/index.html

    History

]]


local core = require("openmw.core")
local input = require("openmw.input")
local self = require("openmw.self")
--local storage = require('openmw.storage')
local types = require("openmw.types")
local ui = require("openmw.ui")
local I = require('openmw.interfaces')

--[[
	Constantes
]]
local MOD_NAME = "Morrowing Mouse Control"
local MOD_CODE = "MMC"
local MOD_VERSION = "0.1"


--[[
	Variables
]]

local mouseWheelNotReadyOptions = {
	{ label = "NONE", value = 0 },
	{ label = "Cycle Spells", value = 1 },
	{ label = "Cycle Weapons", value = 2 },
	{ label = "Swap Light On and Off", value = 3 },
}


--[[
	Menu
]]

-- https://openmw.readthedocs.io/en/latest/reference/lua-scripting/setting_renderers.html

I.Settings.registerPage {
    key = MOD_CODE,
    l10n = "morrowind_mouse_control",
    name = MOD_NAME,
    description = "\n\nThis mod allows you to replace all keyboard commands for Weapon Ready/Spell Ready with mouse click and to select Weapons/Spells/Light with mouse wheel."
}

I.Settings.registerGroup {
    key = "SettingsPlayer" .. MOD_CODE,
    l10n = "morrowind_mouse_control",
    name = MOD_NAME,
    page = MOD_CODE,
    description = "Mod options",
    permanentStorage = false,
    settings = {
        {
            key = "enableMMC",
            name = "Enable " .. MOD_NAME,
            default = true,
            renderer = "checkbox"
        },
        {
            key = "drawWeaponNotReady",
            name = "Draw weapon with left mouse click in Not Ready mode (i.e. Skyrim mode)",
            default = true,
            renderer = "checkbox"
        },
        {
            key = "selectDay",
            name ="Day Selection",
            l10n = "morrowind_mouse_control",
            renderer = "select",
            items = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
        }
    }
}


--[[
	Events
]]

-- https://openmw.readthedocs.io/en/latest/reference/lua-scripting/engine_handlers.html?highlight=onInputAction#engine-handlers-reference
local function onControllerButtonRelease()
    ui.showMessage("onControllerButtonRelease")
end

local function onKeyRelease(key)
    ui.showMessage("onKeyRelease " .. key)
end

local function onControllerButtonPress()
    ui.showMessage("onControllerButtonPress")
end

-- Retrieve an action https://openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_input.html##(ACTION)
local function onInputAction(id)
    ui.showMessage("onInputAction ".. id)
end

-- https://openmw.readthedocs.io/en/latest/reference/lua-scripting/engine_handlers.html#engine-handlers-reference
return {
    engineHandlers = {
        --onControllerButtonRelease=onControllerButtonRelease,
        onKeyRelease=onKeyRelease,
        --onControllerButtonPress,onControllerButtonPress,
        onInputAction=onInputAction
        --onMouseMove = onMouseButtonDown,
        --onMousePress = onMouseButtonDown
    }
}
