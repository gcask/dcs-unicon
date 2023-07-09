-- SPDX-License-Identifier: MIT
--[[
MIT License

Copyright (c) 2023 gcask https://github.com/gcask/dcs-unicon

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

package.path = package.path..';'..lfs.writedir()..'/Mods/Services/DCS-unicon/Scripts/?.lua'
local converters = require('DCS-unicon-UnitConverters')
local Terrain = require('terrain')

addButton(0, 0, 95, 30, "COORDS", function (text)
    -- Grab the first non-blank line.
    local input = text:getText():match("%s*([^\n]+)")
    for parserId, parser in ipairs(converters.coords.parsers) do
        local x, y = parser(input)
        if x ~= nil then
            local coordsText = ''

            -- MGRS
            local mgrsString = Terrain.GetMGRScoordinates(x, y)
            coordsText = coordsText .. 'MGRS: ' .. mgrsString .. '\n'

            -- 38 T KM 12345 98761 (always the same format)
            local mgrs = {}
            mgrs.UTMZone, mgrs.MGRSDigraph, mgrs.Easting, mgrs.Northing = mgrsString:match("^(%d+%s+%a)%s+(%a%a)%s+(%d+)%s+(%d+)$")
            mgrs.Easting = tonumber(mgrs.Easting)
            mgrs.Northing = tonumber(mgrs.Northing)

            local utm = converters.coords.MGRStoUTM(mgrs)
            coordsText = coordsText .. string.format("UTM: %s %d %d\n", utm.UTMZone, utm.Easting, utm.Northing)

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
            coordsText = coordsText .. string.format("Decimal Degrees: %s %10.5f %s %10.5f\n", hemisphere, lat, east_west, long)

            -- Decimal Minutes: DD MM.mmm
            local degrees = {
                lat = math.floor(lat),
                long = math.floor(long)
            }

            local minutes = {
                lat = (lat - degrees.lat) * 60,
                long = (long - degrees.long) * 60
            }

            coordsText = coordsText .. string.format(
                "DDM: %s %3d° %.3f' %s %4d° %06.3f'\n",
                hemisphere, degrees.lat, minutes.lat,
                east_west, degrees.long, minutes.long)

            -- DMS: DD MM SS.ss (half a meter)
            local seconds = {
                lat = (minutes.lat - math.floor(minutes.lat)) * 60,
                long = (minutes.long - math.floor(minutes.long)) * 60,
            }

            coordsText = coordsText .. string.format(
                "DMS: %s %3d° %02d' %05.2f\" %s %4d° %02d' %05.2f\"\n",
                hemisphere, degrees.lat, math.floor(minutes.lat), seconds.lat,
                east_west, degrees.long, math.floor(minutes.long), seconds.long)
            
            text:insertBelow(coordsText)
            return
        end
    end
end)