#!/usr/bin/env luajit
local file = require 'ext.file'
local table = require 'ext.table'
local Zip = require 'zip'

local startTS, endTS = ...
assert(startTS and endTS, [[
expected (startTS) (endTS)
timestamps are in the format yyyy/mm/dd/HH:MM:SS and are in UTC
seconds are ignored/omitted.
I don't care what separators you use in the timestamps.
Also, seconds are thrown away. Resolution is to the minute.
]])


local function parseTimestamp(s)
	-- I'm not using match because i want optional args
	return os.time{
		year = tonumber(s:sub(1,4)),
		month = tonumber(s:sub(6,7)),
		day = tonumber(s:sub(9,10)),
		hour = tonumber(s:sub(12,13)),
		min = tonumber(s:sub(15,16)),
		sec = tonumber(s:sub(18,17)),
	}
end

local function roundMin(t)
	local d = os.date('*t', t)
	d.sec = 0
	return os.time(d)
end

-- TODO how about a day-iter between timestamps?
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

local startMin = roundMin(parseTimestamp(startTS))
print('startMin', os.date(nil, startMin))
local endMin = roundMin(parseTimestamp(endTS))
print('endMin', os.date(nil, endMin))

local startDay = roundDay(startMin)
local endDay = roundDay(endMin)

local cachedir = 'cache'
-- assert(file(cachedir):mkdir()) ?
file(cachedir):mkdir()
assert(file(cachedir):isdir())

local function tryToDownload(url)
	local fn = url:match('[^/]*$')
	--print(url, fn)
	local cacheFn = cachedir..'/'..fn
	if not file(cacheFn):exists() then
		exec('cd "'..cachedir..'" && wget '..url)
	end
	return cacheFn
end

-- TODO download either, then extract-and-recompress it ... in cachedir/%Y%m%d.zip or .something
local function download(t)
	error("still gotta do unzipping")
	local urlWithoutExt = urlWithoutExtForTime(t)
	local fn = tryToDownload(urlWithoutExt..'.zip')
	if fn then
		-- TODO convert .zip to .7z?  or extract both?
		return fn
	else
		fn = tryToDownload(urlWithoutExt..'.tar.gz')
		if fn then
			return fn
		else
			error("couldn't find")
		end
	end
end

-- TODO instead of a table, just save the last one, since we are iterating through in order
local zipArchivesForFileName = {}
local function getZipArchive(zipFileName)
	local zipArchive = zipArchivesForFileName[zipFileName]
	if zipArchive then return zipArchive end
	if not file(zipFileName):exists() then
		download(t)
		assert(file(zipFileName):exists())
	end
	zipArchive = Zip(zipFileName)
	zipArchivesForFileName[zipFileName] = zipArchive
	return zipArchive
end

file'tmp':mkdir()
assert(file'tmp':isdir())
for f in file'tmp':dir() do
	file('tmp/'..f):remove()
end

-- `https://services.swpc.noaa.gov/images/animations/d-rap/global/d-rap/SWX_DRAP20_C_SWPC_20230422142400_GLOBAL.png`
local fs = table()
-- this won't skip days ... right ... ?  rounding error?  weird time standards?  leap seconds? idk?
-- ig a better way to do it is inc the timestep by a day and a half then round it down to the nearest day's timestamp ...
local failCount = 0
local count = 0
for t=startMin,endMin,60 do
	count = count + 1
	local zipFileName = cachedir..'/'..os.date('%Y%m%d', t)..'.zip'
	local zipArchive = getZipArchive(zipFileName)
	local fileNameInArchive = os.date('SWX_DRAP20_C_SWPC_%Y%m%d%H%M00_GLOBAL.png', t)
	local zipPath = zipArchive:file(fileNameInArchive)
print('zipArchive', zipArchive)	
print('zipPath', zipPath)	
	if not zipPath:exists() then
		print("failed to find filename "..fileNameInArchive)
		failCount = failCount + 1
		fs:insert(fs:last())	-- insert last frame anyways if it's there so there's no skips
	else
		-- extract to tmp
		local dstfn = count..'.png' 
		file('tmp/'..dstfn):write((zipPath:read()))
		fs:insert(dstfn)	-- relative to the tmp dir
	end
end
print('found '..(count - failCount)..' of '..count..' files')
if #fs == 0 then error("can't go any further") end
file'tmp/input.txt':write(fs:mapi(function(s,i)
	return "file '"..s.."'\n"
		..(i < #fs and 'duration 1\n' or '')
end):append{
	#fs > 0 and ("file '"..fs:last().."'\n") or nil
}:concat())
exec('ffmpeg -r 24 -y -f concat -i tmp/input.txt out.mp4')
-- ok at 24 fps , 1 frame per second, 1 day becomes 1 minute
-- and our 1 min vid is about 1.7 mb
