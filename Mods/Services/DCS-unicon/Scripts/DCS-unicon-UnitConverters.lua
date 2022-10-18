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

-- lua
local require  = base.require
local string   = base.string
local math     = base.math

-- DCS
local log = base.log
local Terrain = require('terrain')

local converters = {
    coords = {
        parsers = {}
    }
}

-- MGRS Grid Alphabet.
local MGRSAlphabet = {
    -- No I nor O
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ" 
}

function MGRSAlphabet:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MGRSAlphabet:index(letter)
    return self.alphabet:find(letter, 1, true)
end

function MGRSAlphabet:char(index)
    return self.alphabet:sub(index, index)
end

-- utm = {UTMZone, Easting, Northing}
-- returns mgrs = {UTMZone, MGRSDigraph, Easting, Northing}
function converters.coords.UTMtoMGRS(utm)
    local grid, hemisphere = tonumber(utm.UTMZone:sub(1,-2)), utm.UTMZone:sub(-1)
    if hemisphere ~= 'N' and hemisphere ~= 'S' then
        return nil
    end

    local alphabet = MGRSAlphabet:new()

    local sq100k = {
        northing = math.floor(utm.Northing/1e5),
        easting = math.floor(utm.Easting/1e5)
    }
    
    -- Find GZD (Grid Zone Designator - UTMZone)
    -- 20 bands, since UTM excludes polar zones.
    -- Each is 8deg high, or about 889.6km.
    local latitude_band = math.floor(utm.Northing/889600)
    local gzd_start_offset = alphabet:index('N')
    if hemisphere == 'S' then
        gzd_start_offset = alphabet:index('B')
    end

     -- 100k square
     -- MGRS-New
     local rows = {'F', 'A'}
     local row_letter_index = alphabet:index(rows[(grid % 2) + 1]) + (sq100k.northing % 20)
     digraph = {}

     digraph.row = alphabet:char(row_letter_index)

     local zone_type = grid % 3
     local columns = {'S', 'A', 'J'}
     local column_start_letter = columns[zone_type + 1]

    digraph.column = alphabet:char(alphabet:index(column_start_letter) + math.floor(sq100k.easting) - 1)

    return {
        UTMZone = grid..alphabet:char(gzd_start_offset + latitude_band),
        MGRSDigraph = digraph.column..digraph.row,
        Easting = utm.Easting - sq100k.easting * 1e5,
        Northing = utm.Northing - sq100k.northing * 1e5
    }
end

-- mgrs = {UTMZone, MGRSDigraph, Easting, Northing}
-- returns utm = {UTMZone, Easting, Northing}
function converters.coords.MGRStoUTM(mgrs)
    -- GZD is nnA
    -- nn = Grid
    -- A is latitude band, <= M is southern, > is northern
    local alphabet = MGRSAlphabet:new()
    local latitude_band = alphabet:index(mgrs.UTMZone:sub(-1))
    local grid = tonumber(mgrs.UTMZone:sub(1,-2))

    local utm = {
        UTMZone = grid..' '..(latitude_band > alphabet:index('M') and 'N' or 'S')
    }

    -- Rebuild 100k square.
    local gsqid = {
        column = alphabet:index(mgrs.MGRSDigraph:sub(1, 1)),
        row = alphabet:index(mgrs.MGRSDigraph:sub(2, 2))
    }

    local sq100k = {}
    local zone_type = grid % 3
    local columns = {'S', 'A', 'J'}
    
    sq100k.easting = gsqid.column - alphabet:index(columns[zone_type + 1]) + 1

    -- Northing 100k: Figure out how many squares are before us.
    -- First, align the latitude band on a square boundary.
    
    local sq100knorthing_offset = latitude_band - alphabet:index(utm.UTMZone:sub(-1) == 'N' and 'N' or 'B')
    local sq100k_latitude_aligned = math.floor((sq100knorthing_offset * 889600) / 1e5)

    -- Find the first one that fits fully inside.
    sq100k_latitude_aligned = math.floor((sq100k_latitude_aligned + 14)/15) * 15

    -- Get our grid offset
    local rows = {'F', 'A'}
    local sq100knorthingmod20 = gsqid.row - alphabet:index(rows[(grid % 2) + 1])
    sq100k.northing = math.floor(sq100k_latitude_aligned/10) * 10 + (sq100knorthingmod20 % 10)

    utm.Northing = sq100k.northing * 1e5  + mgrs.Northing
    utm.Easting = sq100k.easting * 1e5 + mgrs.Easting

    return utm
end



-- Coordinate parsers.
local function MGRSToTerrainXY(mgrs)
    -- Change MGRS to a string.
    local mgrsString = string.format("%d %s %s %d %d",
        tonumber(mgrs.UTMZone:sub(1, 2)),
        mgrs.UTMZone:sub(3, 3),
        mgrs.MGRSDigraph,
        mgrs.Easting,
        mgrs.Northing
    )

    -- we cannot use the MGRStoLL() here, so rely on terrain.
    return Terrain.convertMGRStoMeters(mgrsString)
end

local function DMSToLatLon(dms)
    return
        (dms.lat.degrees + dms.lat.minutes/60 + dms.lat.seconds/3600) * (dms.lat.ns == 'N' and 1 or -1),
        (dms.lon.degrees + dms.lon.minutes/60 + dms.lon.seconds/3600) * (dms.lon.ew == 'E' and 1 or -1)
end

local function buildDMSMatcherWithNormalizedNeedle(input, wants_seconds)
    -- Looking for N/S dd(.ddd) mm(.mmm) ss(.sss)
   -- Ditto for E/W.
   -- N/S, E/W can be either in front or at end, but it should be consistent
   -- (both at front, or both at end)
   -- Spacing characters may include the degree/minutes/seconds symbols.

   -- Enforce single space after special symbols.
   -- Enforce no spaces around degree/minutes/seconds symbols.
   -- replace degree symbol with letter d.
   local needle = input:gsub("°", "d"):gsub("%s*([d'\"])%s*", "%1"):gsub("%s*([NSEWnsew])%s*", " %1 ")
   local coord_matcher = "([^%sd]+)[ d]([^%s']+)"
   if wants_seconds then
       coord_matcher = coord_matcher.."[ ']([^%s\"]+)\"?"
   else
       coord_matcher = coord_matcher.."'?"
   end

   return needle, coord_matcher
end

function converters.coords.parsers.decodeMGRS(input)
    -- strip any non-alphanumeric characters.
    local mgrsRaw = input:gsub("%W", '')
    -- Check if we have a valid MGRS grid.
    local utmZone, band, grid, easting_and_northing = mgrsRaw:match("^(%d+)(%a)(%a%a)(%d+)$")
    if utmZone == nil or band == nil or grid == nil or easting_and_northing == nil then

        -- Check if it's a partial MGRS, that does not include the UTMZone
        -- (which encompasses most of the terrain).

        grid, easting_and_northing = mgrsRaw:match("^(%a%a)(%d+)$")
        if grid == nil or easting_and_northing == nil then
            return nil
        end

        -- Got a partial grid - infer band from a random point on terrain.
        local mgrsTerrainFormat = "^(%d+)%s+(%a)%s+(%a%a)%s+%d+%s+%d+$"
        local terrainMGRS = Terrain.GetMGRScoordinates(0, 0)
        utmZone, band, terrainGrid = terrainMGRS:match(mgrsTerrainFormat)

        if utmZone == nil or band == nil or terrainGrid == nil then
            -- Safety net, this is very unlikely.
            return nil
        end

        -- We got a zone, check if the grid matches. If not, try the next zone going West.
        if grid:upper() ~= terrainGrid then
            utmZone = tonumber(utmZone) + 1
            terrainMGRS = Terrain.GetMGRScoordinates(Terrain.convertMGRStoMeters(string.format("%d %s %s 1 1", utmZone, band, grid:upper())))
            utmZone, band, terrainGrid = terrainMGRS:match(mgrsTerrainFormat)
            if utmZone == nil or band == nil or terrainGrid ~= grid:upper() then
                log.info('UNICON: '..terrainGrid..'<>'..grid:upper())
                return nil
            end
        end
    end

    -- easting and northing having the same number of digits
    -- and must be 2,4,6,8, or 10.
    local easting_and_northing_digits = easting_and_northing:len()
    if (easting_and_northing_digits % 2) == 1 or easting_and_northing_digits > 10 then
        return nil
    end

    -- TODO: extended checks.
    easting_and_northing_digits = easting_and_northing_digits / 2
    local mgrs = {
        UTMZone = utmZone..band:upper(), -- 37T
        MGRSDigraph = grid:upper(), -- GG
        Easting = tonumber(easting_and_northing:sub(1, easting_and_northing_digits)),
        Northing = tonumber(easting_and_northing:sub(easting_and_northing_digits + 1, easting_and_northing_digits + 1 + easting_and_northing_digits)),
    }

   return MGRSToTerrainXY(mgrs)
end

function converters.coords.parsers.decodeUTM(input)
    -- Somewhat similar to MGRS.
     -- Check if we have a valid MGRS grid.
     local utmZone, hemisphere, easting, northing = input:match("^(%d+)%s*([NSns])%s*(%d+) (%d+)$")

     utmZone = tonumber(utmZone)
     easting = tonumber(easting)
     northing = tonumber(northing)

     if utmZone == nil or hemisphere == nil or easting == nil or northing == nil then

        -- Check for a partial UTM zone.
        -- Easting should be 5+ digits
        local easting, northing = input:match("^(%d%d%d%d%d+) (%d+)$")
        if easting == nil or northing == nil then
            return nil
        end

        -- Looks OK, infer zone and hemisphere from random terrain point.
        utmZone, hemisphere = Terrain.GetMGRScoordinates(0, 0):match("^(%d+)%s+(%a)%s+%a%a%s+%d+%s+%d+$")

        utmZone = tonumber(utmZone)
        if utmZone == nil or hemisphere == nil then
            -- Safety net, this is very unlikely.
            return nil
        end
        local alphabet = MGRSAlphabet:new()
        hemisphere = alphabet:index(hemisphere) > alphabet:index('M') and 'N' or 'S'
     end

     local utm = {
        UTMZone = utmZone..hemisphere:upper(),
        Easting = easting,
        Northing = northing
     }

     return MGRSToTerrainXY(converters.coords.UTMtoMGRS(utm))
end

function converters.coords.parsers.decodeDMS(input)
    local lat = {}
    local lon = {}

    local needle, coord_matcher = buildDMSMatcherWithNormalizedNeedle(input, true)
    lat.ns, lat.degrees, lat.minutes, lat.seconds,
    lon.ew, lon.degrees, lon.minutes, lon.seconds =
    needle:match("^ ([NSns]) "..coord_matcher.." ([EWew]) "..coord_matcher.."$")
    if lat.ns == nil or lat.degrees == nil or lat.minutes == nil or lat.seconds == nil or
        lon.ew == nil or lon.degrees == nil or lon.minutes == nil or lon.seconds == nil then

        -- Try with cardinals at end.
        lat.degrees, lat.minutes, lat.seconds, lat.ns,
        lon.degrees, lon.minutes, lon.seconds, lon.ew =
        needle:match("^"..coord_matcher.." ([NSns]) "..coord_matcher.." ([EWew]) $")
    end

    lat.degrees = tonumber(lat.degrees)
    lat.minutes = tonumber(lat.minutes)
    lat.seconds = tonumber(lat.seconds)

    lon.degrees = tonumber(lon.degrees)
    lon.minutes = tonumber(lon.minutes)
    lon.seconds = tonumber(lon.seconds)

    if lat.ns == nil or lat.degrees == nil or lat.minutes == nil or lat.seconds == nil or
        lon.ew == nil or lon.degrees == nil or lon.minutes == nil or lon.seconds == nil then
        return nil
    end

    return Terrain.convertLatLonToMeters(DMSToLatLon({ lat = lat, lon = lon }))
end

function converters.coords.parsers.decodeDDM(input)
    local lat = {}
    local lon = {}
    local needle, coord_matcher = buildDMSMatcherWithNormalizedNeedle(input, false)
    lat.ns, lat.degrees, lat.minutes,
    lon.ew, lon.degrees, lon.minutes =
    needle:match("^ ([NSns]) "..coord_matcher.." ([EWew]) "..coord_matcher.."$")
    if lat.ns == nil or lat.degrees == nil or lat.minutes == nil or
        lon.ew == nil or lon.degrees == nil or lon.minutes == nil then

        -- Try with cardinals at end.
        lat.degrees, lat.minutes, lat.ns,
        lon.degrees, lon.minutes, lon.ew =
        needle:match("^"..coord_matcher.." ([NSns]) "..coord_matcher.." ([EWew]) $")
    end

    lat.degrees = tonumber(lat.degrees)
    lat.minutes = tonumber(lat.minutes)

    lon.degrees = tonumber(lon.degrees)
    lon.minutes = tonumber(lon.minutes)

    if lat.ns == nil or lat.degrees == nil or lat.minutes == nil or
        lon.ew == nil or lon.degrees == nil or lon.minutes == nil then
        return nil
    end

    lat.seconds = 0
    lon.seconds = 0
    return Terrain.convertLatLonToMeters(DMSToLatLon({ lat = lat, lon = lon }))
end

function converters.coords.parsers.decodeLatLon(input)
    -- Looking for two numbers, with whitespace around.
    local lat, lon = input:match("^(%S+)%s+(%S+)$")
    lat = tonumber(lat)
    lon = tonumber(lon)

    if lat == nil or lon == nil then
        -- See if we have cardinal directions, NS/EW before or after.
        local north_south, east_west = nil, nil
        north_south, lat, east_west, lon = input:match("^([NSns])%s*(%S+)%s+([EWew])%s*(%S+)$")

        if north_south == nil or lat == nil or east_west == nil or lon == nil then
            -- Try at the end.
            north_south, lat, east_west, lon = input:match("^(%S+)%s*([NSns])%s+(%S+)%s*([EWew])$")

            if north_south == nil or lat == nil or east_west == nil or lon == nil then
                return nil
            end
        end

        lat = tonumber(lat)
        lon = tonumber(lon)

        if lat == nil or lon == nil then
            return nil
        end

        if north_south == 'S' then
            lat = -lat
        end

        if east_west == 'W' then
            lon = -lon
        end
    end
    -- If there were no match (nils), or the conversion fails,
    -- results will be
    return Terrain.convertLatLonToMeters(lat, lon)
end


return converters