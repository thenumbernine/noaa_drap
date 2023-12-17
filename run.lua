#!/usr/bin/env luajit
local path = require 'ext.path'
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
-- assert(path(cachedir):mkdir()) ?
path(cachedir):mkdir()
assert(path(cachedir):isdir())

--[[ this is also in christopheremoore.net/solarsystem/jpl-ssd-smallbody/getdata.lua
-- but I don't have it built for luajit so...
local https = require 'ssl.https'
local ltn12 = require 'ltn12'
local function downloadAndCache(filename, url, dontReadIfNotNecessary)
	if path(filename):exists() then
		--print('already have file '..filename..', so skipping the download and using the cached version')
		if dontReadIfNotNecessary then
			return true
		end
		return path(filename):read()
	end
	--print('downloading url '..url..' ...')
	local data = table()
	local result = table.pack(https.request{
		url = url,
		sink = ltn12.sink.table(data),
		protocol = 'tlsv1',
	})
	if not result[1] then return result:unpack() end
	data = data:concat()
	--print('writing file '..filename..' with this much data: '..#data)
	path(filename):write(data)
	return data
end
--]]
-- [[
local function downloadAndCache(filename, url, dontReturnData)
	assert(dontReturnData, "")
	assert(exec('wget "'..url..'" -O "'..filename..'"'))
	return dontReturnData and path(filename):read() or true
end
--]]

-- TODO download either, then extract-and-recompress it ... in cachedir/%Y%m%d.zip or .something
local function downloadDRAPArchive(t)
	local Y = os.date('%Y', t)
	local m = os.date('%m', t)
	local d = os.date('%d', t)
	local ts = Y..m..d
	local filenameWithoutExt = 'SWX_DRAP20_C_SWPC_'..ts
	local urlWithoutExt = 'https://www.ngdc.noaa.gov/stp/drap/data/'..Y..'/'..m..'/' .. filenameWithoutExt 
	local found = downloadAndCache('cache/'..ts..'.zip', urlWithoutExt..'.zip', true)
	if not found then
		error("this is where I should download the .tar.gz version but I'm too lazy")
	end
	-- now that it's found ... re-zip in the proper place?  or just use as-is with its weird archive-whatever path?
	return true
end

-- TODO instead of a table, just save the last one, since we are iterating through in order
local zipArchivesForFileName = {}
local function getZipArchive(t)
	local zipFileName = cachedir..'/'..os.date('%Y%m%d', t)..'.zip'
	local zipArchive = zipArchivesForFileName[zipFileName]
	if zipArchive then return zipArchive end
	if not path(zipFileName):exists() then
		assert(downloadDRAPArchive(t))
		assert(path(zipFileName):exists())
	end
	zipArchive = Zip(zipFileName)
	zipArchivesForFileName[zipFileName] = zipArchive
print('zipArchive', zipArchive)
	return zipArchive
end

local tmppath = path'tmp'
tmppath:mkdir()
assert(tmppath:isdir())
for f in tmppath:dir() do
	(tmppath/f):remove()
end

-- `https://services.swpc.noaa.gov/images/animations/d-rap/global/d-rap/SWX_DRAP20_C_SWPC_20230422142400_GLOBAL.png`
local fs = table()
-- this won't skip days ... right ... ?  rounding error?  weird time standards?  leap seconds? idk?
-- ig a better way to do it is inc the timestep by a day and a half then round it down to the nearest day's timestamp ...
local failCount = 0
local count = 0
for t=startMin,endMin,60 do
	count = count + 1
	local zipArchive = getZipArchive(t)
	local fileNameInArchive = os.date('SWX_DRAP20_C_SWPC_%Y%m%d%H%M00_GLOBAL.png', t)
	local zipPath
	for _,prefix in ipairs{'', 'archive_images/'} do
		zipPath = zipArchive:file(prefix..fileNameInArchive)
print('trying zipPath', zipPath)
		if zipPath:exists() then break end
		zipPath = nil
	end
	if not zipPath then
		print("failed to find filename "..fileNameInArchive)
		failCount = failCount + 1
		fs:insert(fs:last())	-- insert last frame anyways if it's there so there's no skips
	else
		-- extract to tmp
		local dstfn = count..'.png'
		path('tmp/'..dstfn):write((zipPath:read()))
		fs:insert(dstfn)	-- relative to the tmp dir
	end
end
print('found '..(count - failCount)..' of '..count..' files')
if #fs == 0 then error("can't go any further") end
path'tmp/input.txt':write(fs:mapi(function(s,i)
	return "file '"..s.."'\n"
		..(i < #fs and 'duration 1\n' or '')
end):append{
	#fs > 0 and ("file '"..fs:last().."'\n") or nil
}:concat())
exec('ffmpeg -r 24 -y -f concat -i tmp/input.txt out.mp4')
-- ok at 24 fps , 1 frame per second, 1 day becomes 1 minute
-- and our 1 min vid is about 1.7 mb
-- TODO better output filename?
