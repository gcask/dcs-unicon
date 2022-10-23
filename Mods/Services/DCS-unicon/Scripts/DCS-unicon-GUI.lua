-- SPDX-License-Identifier: MIT
--[[
MIT License

Copyright (c) 2022 gcask

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

local base = _G

-- lua standard libs
local require  = base.require
local string   = base.string
local math     = base.math

local log = base.log


-- DCS.
local DCS               = require('DCS')
--local Gui               = require('dxgui')
--local i18n				= require('i18n')
local lfs               = require('lfs')
local net               = require('net')
--local Skin              = require('Skin')
local Terrain           = require('terrain')

-- This mod.
package.path = package.path..';'..lfs.writedir()..'/Mods/Services/DCS-unicon/Scripts/?.lua'
local converters = require('DCS-unicon-UnitConverters')


--i18n.setup(_M)


local cdata = 
{
	Metric				        = _("Metric"),
	Decimal_Degrees	            = _("Decimal Degrees"),
    Decimal_Minutes             = _("Decimal Minutes"),
    Degrees_Minutes_Seconds     = _("DMS"),
	MGRS		                = _("MGRS"),
    UTM                         = _('UTM'),
	Knots 			= _("Knots"),
    KPH             = _("KPH"),
	Feet			= _('feet'),
	Meters			= _('meters'),
}

local version = "1.0.0"

local Dialog = {
    initialSizeW = 0,
    initialSizeH = 0
}

local window = nil
local keyboardLocked = false

-- Resets all coordinates fields.
function Dialog:clearCoordinates()
    self.ui.e_MGRS:setText("")
    self.ui.e_UTM:setText("")
    self.ui.e_Decimal_Degrees:setText("")
    self.ui.e_Decimal_Minutes:setText("")
    self.ui.e_Degrees_Minutes_Seconds:setText("")
end

-- Updates all coordinates from (x,y) in terrain coordinates.
function Dialog:updateCoordinates(x, y)
    -- MGRS
    local mgrsString = Terrain.GetMGRScoordinates(x, y)
    self.ui.e_MGRS:setText(mgrsString)

    -- 38 T KM 12345 98761 (always the same format)
    local mgrs = {}
    mgrs.UTMZone, mgrs.MGRSDigraph, mgrs.Easting, mgrs.Northing = mgrsString:match("^(%d+%s+%a)%s+(%a%a)%s+(%d+)%s+(%d+)$")
    mgrs.Easting = tonumber(mgrs.Easting)
    mgrs.Northing = tonumber(mgrs.Northing)

    local utm = converters.coords.MGRStoUTM(mgrs)
    self.ui.e_UTM:setText(string.format("%s %d %d", utm.UTMZone, utm.Easting, utm.Northing))

    local lat, long = Terrain.convertMetersToLatLon(x, y)
    local hemisphere = 'N'
    if lat < 0 then
        hemisphere = 'S'
        lat = -lat
    end

    local east_west = 'E'
    if long < 0 then
        east_west = 'W'
        long = -long
    end

    -- Decimal degrees: DD.ddddd (1-meter precision)
    self.ui.e_Decimal_Degrees:setText(string.format("%s %10.5f %s %10.5f", hemisphere, lat, east_west, long))

    -- Decimal Minutes: DD MM.mmm
    local degrees = {
        lat = math.floor(lat),
        long = math.floor(long)
    }

    local minutes = {
        lat = (lat - degrees.lat) * 60,
        long = (long - degrees.long) * 60
    }

    self.ui.e_Decimal_Minutes:setText(string.format(
        "%s %3d° %.3f' %s %4d° %06.3f'",
        hemisphere, degrees.lat, minutes.lat,
        east_west, degrees.long, minutes.long))

    -- DMS: DD MM SS.ss (half a meter)
    local seconds = {
        lat = (minutes.lat - math.floor(minutes.lat)) * 60,
        long = (minutes.long - math.floor(minutes.long)) * 60,
    }

    self.ui.e_Degrees_Minutes_Seconds:setText(string.format(
        "%s %3d° %02d' %05.2f\" %s %4d° %02d' %05.2f\"",
        hemisphere, degrees.lat, math.floor(minutes.lat), seconds.lat,
        east_west, degrees.long, math.floor(minutes.long), seconds.long))
end

-- Try to interpret the string as various formats.
-- input is prefiltered with whitespaces stripped and normalized.
function Dialog:tryConvert(input)
    for _, parser in ipairs(converters.coords.parsers) do
        local x, y = parser(input)
        if x ~= nil then
            self:updateCoordinates(x, y)
            return
        end
    end

    -- No match, clear everything.
    self:clearCoordinates()
end

-- Locks/unlocks keyboard wrt game actions.
local function lockKeyboard(lock)
	if lock == keyboardLocked then
        return
    end

    local Input = require("Input")

    if lock then
        local keyboardEvents = Input.getDeviceKeys(Input.getKeyboardDeviceName())
        DCS.lockKeyboardInput(keyboardEvents)
    else
        DCS.unlockKeyboardInput(true)
	end

    keyboardLocked = lock
end

-- Toggle Dialog visibility.
function Dialog:getEditBoxes()
    return {
        self.ui.e_Input,
        self.ui.e_MGRS,
        self.ui.e_UTM,
        self.ui.e_Decimal_Degrees,
        self.ui.e_Decimal_Minutes,
        self.ui.e_Degrees_Minutes_Seconds,

        self.ui.e_Speed_Knots,
        self.ui.e_Speed_KPH,
        self.ui.e_Distance_Feet,
        self.ui.e_Distance_Meters
    }
end

function Dialog:blur()
    local editBoxes = self:getEditBoxes()

    for _, editbox in ipairs(editBoxes) do
        editbox:setFocused(false)
    end

    lockKeyboard(false)
end

function Dialog:toggle()
    local w, h = self.ui:getSize()
    if w > 0 then
        -- clear focus and release keyboard, we're hiding.
        self:blur()
    end

    self.ui:setSize(self.initialSizeW - w, self.initialSizeH - h)
end

-- Creates the dialog.
function Dialog:new(config)
    local DialogLoader = require('DialogLoader')
    local dialog = {}
    setmetatable(dialog, self)
    self.__index = self

    dialog.ui = DialogLoader.spawnDialogFromFile(lfs.writedir() .. 'Mods/Services/DCS-unicon/UI/DCS-unicon.dlg', cdata)

    local lockOnFocused = function(self)
        lockKeyboard(self:getFocused())
	end

    local editBoxes = dialog:getEditBoxes()

    for _, editbox in ipairs(editBoxes) do
        editbox:addFocusCallback(lockOnFocused)
    end

    function dialog.ui.e_Input:onChange()
        -- strip surrounding whitespaces.
        -- Collapse all whitespaces to one space.
        local needle = self:getText():gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
        dialog:tryConvert(needle)
    end

    -- Metric/Imperial conversions.
    function dialog.ui.e_Speed_Knots:onChange()
        local knots = tonumber(self:getText())

        local kph = ""
        if knots then
            kph = string.format("%.0f", knots * 1.852)
        end

        dialog.ui.e_Speed_KPH:setText(kph)
    end

    function dialog.ui.e_Speed_KPH:onChange()
        local kph = tonumber(self:getText())

        local knots = ""
        if kph then
            local knots = string.format("%.0f", kph / 1.852)
        end

        dialog.ui.e_Speed_Knots:setText(knots)
    end

    function dialog.ui.e_Distance_Feet:onChange()
        local feet = tonumber(self:getText())

        local meters = ""
        if feet then
            local meters = string.format("%.1f", feet * 0.3048)
        end

        dialog.ui.e_Distance_Meters:setText(meters)
    end

    function dialog.ui.e_Distance_Meters:onChange()
        local meters = tonumber(self:getText())

        local feet = ""
        if meters then
            local feet = string.format("%.0f", meters / 0.3048)
        end

        dialog.ui.e_Distance_Feet:setText(feet)
    end

    dialog.ui:addHotKeyCallback("escape", function()
        -- Clear focus (which will unlock keyboard)
        dialog:blur()
    end)

    dialog.ui:addHotKeyCallback(config.hotkey, function()
        dialog:toggle()
    end)

    -- Release any keyboard lock when the mouse leaves the window
    -- unless the user has the input field focused.
    dialog.ui:addMouseLeaveCallback(function()
		if not dialog.ui.e_Input:getFocused() then
            dialog:blur()
        end
	end)

    function dialog.ui:onClose()
        dialog:toggle()
	end
    
    dialog.ui:setVisible(true) -- if you make the window invisible, its destroyed
    
    dialog.initialSizeW, dialog.initialSizeH = 390, 270
    dialog.ui:setSize(0, 0)

    log.info('DCS UNICON: Window created.')
    return dialog
end


-- Settings handling.
local Settings = {}

function Settings.getPath()
    return lfs.writedir() .. 'Config/unicon.lua'
end

function Settings.load()
    log.info('DCS UNICON: loading configuration.')
    local Tools = require('tools')
    local tbl = Tools.safeDoFile(Settings.getPath(), false)

    -- Defaults.
    local config = {
        hotkey = "Ctrl+Shift+Z",
        version = version
    }
    if (tbl and tbl.config) then
        config = tbl.config
    else
        Settings.save()
    end

    return config
end

function Settings.save()
    log.info('DCS UNICON: saving configuration.')
    local U = require('me_utilities')
    U.saveInFile(config, 'config', Settings.getPath())
end



-- DCS callbacks.
local callbacks = {
    onSimulationStart = function()
        if window == nil then
            log.info('DCS UNICON: creating window.')
            window = Dialog:new(Settings.load())
        end
    end,

    onSimulationStop = function()
        if window ~= nil then
            window = nil
        end
    end
}



DCS.setUserCallbacks(callbacks)

log.info("DCS unicon v"..version.." set up")