#!/usr/bin/env luajit
local file = require 'ext.file'
local table = require 'ext.table'

local startTS, endTS = ...
assert(startTS and endTS, [[
expected (startTS) (endTS)
timestamps are in the format yyyymmddHHMM and are in UTC
seconds are ignored/omitted.
]])


local function parseTime(s)
	return os.time{
		year = tonumber(s:sub(1,4)),
		month = tonumber(s:sub(5,6)),
		day = tonumber(s:sub(7,8)),
		hour = tonumber(s:sub(9,10)),
		min = tonumber(s:sub(11,12)),
		sec = tonumber(s:sub(13,14)),
	}
end

local function roundDay(t)
	local d = os.date('*t', t)
	d.hour = 0
	d.min = 0
	d.sec = 0
	return os.time(d)
end

local function urlWithoutExtForTime(t)
	return os.date('https://www.ngdc.noaa.gov/stp/drap/data/%Y/%m/SWX_DRAP20_C_SWPC_%Y%m%d', t)
end

local function printAndReturn(...)
	print(...)
	return ...
end

local function exec(s)
	print('> '..s)
	return printAndReturn(os.execute(s))
end

local startTime = parseTime(startTS)
print('startTime', require 'ext.tolua'(startTime))
local endTime = parseTime(endTS)
print('endTime', require 'ext.tolua'(endTime))

local startDay = roundDay(startTime)
local endDay = roundDay(endTime)

file'cache':mkdir()

local function tryToDownload(url)
	local fn = url:match('[^/]*$')
	--print(url, fn)
	local cacheFn = 'cache/'..fn
	if not file(cacheFn):exists() then
		exec('cd cache && wget '..url)
	end
	return cacheFn
end

-- `https://services.swpc.noaa.gov/images/animations/d-rap/global/d-rap/SWX_DRAP20_C_SWPC_20230422142400_GLOBAL.png`
local fs = table()
-- this won't skip days ... right ... ?  rounding error?  weird time standards?  leap seconds? idk?
-- ig a better way to do it is inc the timestep by a day and a half then round it down to the nearest day's timestamp ...
for t=startDay,endDay,60*60*24 do
	local urlWithoutExt = urlWithoutExtForTime(t)
	local fn = tryToDownload(urlWithoutExt..'.zip')
	if fn then
		-- TODO convert .zip to .7z?  or extract both?
		fs:insert(fn)
	else
		fn = tryToDownload(urlWithoutExt..'.tar.gz')
		if fn then
			fs:insert(fn)
		else
			error("couldn't find")
		end
	end
end
fs:sort()
--[[
-- also in my obs-buildvideo project
-- mabye merge if it wasn't so simple
file'input.txt':write(fs:mapi(function(s) return "file '"..s..'"' end):concat'\n'..'\n')
exec('ffmpeg -y -i input.txt out.mp4')
--]]
