local status, result =  pcall(function() local lfs=require('lfs');dofile(lfs.writedir()..[[Mods\Services\DCS-unicon\Scripts\DCS-unicon-GUI.lua]]); end,nil) 
 if not status then
 	net.log(result)
 end
 