## Make-Your-Own-DRAP-Video

Note to self:
- add module dependencies.
- get the downloader, extractor, re-compressor working (or alternatively make some tgz lua class wrappers like I did the zip ones)

I kept missing good flare DRAP movies and kept wondering how to find them in the archives.
Took me a while to realize there was no movie archives.  It's just a bunch of PNG files. 
Example:

`https://services.swpc.noaa.gov/images/animations/d-rap/global/d-rap/SWX_DRAP20_C_SWPC_20230422142400_GLOBAL.png`

That's for pictures in the last 12 hours.

Then it seems data gets shifted to the archives.

`https://www.ngdc.noaa.gov/stp/drap/data/2023/04/SWX_DRAP20_C_SWPC_20230422.tar.gz` where files are stored at root-level. 

But you can't get archived data within the last 3 days.

Then the next two days worth or so are .zips.  Which are 2x as big (less-compressed) as the .tar.gz, but contain identical info, except that the .zip stores its folders in an 'archive-something' subfolder.

Then from that point in time on back everything is .tar.gz's.


For a given folder, the .tar.gz is about 70 mb, the .zip is about 120 mb ... and me recompressing as .7z is 45 mb ... and me recompressing as .zip is 20mb ... How come NOAA's own .zips are 10x as big as mine?
