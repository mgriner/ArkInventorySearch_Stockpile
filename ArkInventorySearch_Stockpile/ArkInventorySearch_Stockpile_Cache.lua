local _G = _G
local select = _G.select
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local type = _G.type
local error = _G.error
local table = _G.table

local item_statistics = { 
	item_types = { }
}

-- EVENTS ----------------------------------------------


-- Fired after PLAYER_ENTERING_WORLD
-- So player info should now be set.
function ArkInventorySearch_Stockpile:EVENT_WOW_PLAYER_ALIVE( )
	
	-- unregister cache events to avoid many unecessary calls at login/load
	ArkInventorySearch_Stockpile.UnregisterSearchCacheEvents( )
	-- build global search cache, will only fire once at login or when module is enabled
	-- then the event is unregistered
	ArkInventorySearch_Stockpile.BuildGlobalSearchCache( )
	
end

-- Fires when we need to update a specific container
-- INPUT (table) bag_table : a list of blizzard_id's (and count of events fired by that id)
function ArkInventorySearch_Stockpile:EVENT_ARKINV_SEARCH_CACHE_CONTAINER_UPDATE_BUCKET( bag_table )
	local player_id = ArkInventory.PlayerIDSelf( )
	local location_id, bag_id
	
	-- first clear all items in global cache that are in these bags
	for blizzard_id in pairs( bag_table ) do
		location_id, bag_id = ArkInventory.BlizzardBagIdToInternalId( blizzard_id )
		player_id = ArkInventorySearch_Stockpile.PlayerIDLocation( location_id )
		ArkInventorySearch_Stockpile.Clear_Container( player_id, location_id, bag_id )
	end
	
	-- now recache all items from these bags
	for blizzard_id in pairs( bag_table ) do
		location_id, bag_id = ArkInventory.BlizzardBagIdToInternalId( blizzard_id )
		player_id = ArkInventorySearch_Stockpile.PlayerIDLocation( location_id )
		ArkInventorySearch_Stockpile.RecacheContainer( player_id, location_id, bag_id )
	end
	
end

-- Fires when we need to update a location
-- INPUT (table) player_location_table : a table of player_location objects
-- (and count of events fired by that location)
-- a player_location object contains a player_id and location_id
function ArkInventorySearch_Stockpile:EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET( player_location_table )
	local player_id, location_id
	
	for player_location_object in pairs( player_location_table ) do
		player_id = player_location_object.player_id
		location_id = player_location_object.location_id
		ArkInventorySearch_Stockpile.RecacheLocation( player_id, location_id )
	end
	
end

-- Fires when a mail is sent, including auctions being cancelled/bought
function ArkInventorySearch_Stockpile:EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE( )

	local player_id = ArkInventory.Global.Cache.SentMail.to or ArkInventory.PlayerIDSelf( )
	local location_id = ArkInventory.Const.Location.Mail
	ArkInventorySearch_Stockpile.RecacheLocation( player_id, location_id )
	
end

-- Fires when item info has been received from the server
-- INPUT (string) event : what kind of event this is
-- INPUT (int) ... : should just contain the item_id fo the item info downloaded
function ArkInventorySearch_Stockpile:EVENT_WOW_GET_ITEM_INFO_RECEIVED( event, ... )
	local item_id = ...
	local objectid = string.format( "%s:%s", "item", item_id )

	-- only pass to bucket if it's in the loading queue
	if ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid] ~= nil then
		
		--print("removing item from queue")
		local h = ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid].h
		--print("h: " .. h)
		
		-- grab the item info now, it probably won't be available when the bucket triggers
		local info = ArkInventory.ObjectInfoArray( h )
		
		-- pull the p,l,b data before we clear entry from queue
		info.player_id = ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid].location_object.player_id
		info.location_id = ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid].location_object.location_id
		info.bag_id = ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid].location_object.bag_id
		
		-- clear entry from queue
		ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid] = nil
		
		--local name, h, q, _, _, itemtype, _, _, _, texture = GetItemInfo( objectid )
		--ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_GET_ITEM_INFO_RECEIVED_BUCKET", { objectid = objectid, name = name, h = h, q = q, texture = texture, itemtype = itemtype } )
		ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_GET_ITEM_INFO_RECEIVED_BUCKET", info )
	end
end

-- Fires after an interval of GET_ITEM_INFO_RECEIVED events are fired
-- Go through all of the items downlaoded and update their cache entries
-- INPUT (table) ... : should contain a table of item_info objects which have an
-- objectid, name, h, q, and texture
function ArkInventorySearch_Stockpile:EVENT_ARKINV_GET_ITEM_INFO_RECEIVED_BUCKET( ... )
	
	if ArkInventorySearch_Stockpile.IsBuilding then
		print("trying to update while building")
	end
	
	
	local item_info_table = ...
	local item_cache_table = { }
	local sd = { }
	local player_id, location_id, bag_id
	
	for info in pairs( item_info_table ) do
		if true then
		--if ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] ~= nil then
		
			
			player_id = info.player_id
			location_id = info.location_id
			bag_id = info.bag_id
			
			
			-- if the item already exists in cache grab its info
			-- for comparison in validation function
			if ArkInventorySearch_Stockpile.GlobalSearchCache[info.objectid] then
				sd = { h = ArkInventorySearch_Stockpile.GlobalSearchCache[info.objectid].h, q = ArkInventorySearch_Stockpile.GlobalSearchCache[info.objectid].q }
			else
				sd = { h = info.h, q = info.q }
			end
			
			-- try to validate info
			info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd, player_id, location_id, bag_id )

			-- if not valid add it back to the queue
			-- otherwise update/add the cache entry to local table
			if info.class == "item" and info.addToLoadingQueue then
				print("adding item to queue from GIIR")
				--ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = { h = info.h, q = info.q, player_id = player_id, location_id = location_id, bag_id = bag_id }
				ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = info
			elseif not item_cache_table[info.objectid] then
				-- item_cache_table[info.objectid] = { name = info.name, h = info.h, q = info.q, texture = info.texture, player_id = player_id, location_id = location_id, bag_id = bag_id, search_text = info.search_text }
				item_cache_table[info.objectid] = info
			end
		end
	end
	-- batch add this local update table to the global cache table
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
	ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
end


-- UTILITY FUNCTIONS ----------------------------------------------

function ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
	--print("cleaning up queue")
	for objectid, objectinfo in pairs( ArkInventorySearch_Stockpile.ItemLoadingQueue ) do
		local refire = true
		
		-- had to add logic to check if the item is in global cache
		-- but wasnt removed from ItemLoadingQueue...not sure how this would happen
		-- should look into it
		
		if ArkInventorySearch_Stockpile.GlobalSearchCache[objectid] then
			local info = ArkInventorySearch_Stockpile.ValidateItemInfo( objectinfo, objectinfo, objectinfo.location_object.player_id, objectinfo.location_object.location_id, objectinfo.location_object.bag_id )
			if not info.addToLoadingQueue then
				print("it's all good baby...")
				ArkInventorySearch_Stockpile.ItemLoadingQueue[objectid] = nil
				refire = false
			else
				--print("still something wrong...")
			end
		end
		
		if refire then
			--print("oid: " .. objectid .. " oname: " .. objectinfo.name .. " olink: " .. objectinfo.h )
			--print(table.tostring(objectinfo.invalidReasons))
			GetItemInfo( objectid )
		end
	end
end

-- Registers events needed for cache
function ArkInventorySearch_Stockpile.RegisterSearchCacheEvents( )

	-- TODO make interval times an option in config/db?
	local short_interval = 0.25
	local medium_interval = 0.5
	if cache_bag_bucket == nil then
		cache_bag_bucket = ArkInventorySearch_Stockpile:RegisterBucketMessage( "EVENT_ARKINV_SEARCH_CACHE_CONTAINER_UPDATE_BUCKET", short_interval )
	end
	
	if cache_location_bucket == nil then
		cache_location_bucket = ArkInventorySearch_Stockpile:RegisterBucketMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", medium_interval )
	end
	
	ArkInventorySearch_Stockpile:RegisterMessage( "EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE" )

end

-- Unregisters events needed for cache
-- This can be useful to avoid when many unecessary events
-- are fired.  E.g. at player login/after loading screen
-- inventory events can fire way too many times.  If we just unregister
-- the cache events on screen load and then re-register the events after 5-10 seconds
-- we can avoid possibly hundreds of calls.
function ArkInventorySearch_Stockpile.UnregisterSearchCacheEvents( )

	if cache_bag_bucket ~= nil then
		ArkInventorySearch_Stockpile:UnregisterBucket( cache_bag_bucket )
		cache_bag_bucket = nil
	end
	
	if cache_location_bucket ~= nil then
		ArkInventorySearch_Stockpile:UnregisterBucket( cache_location_bucket )
		cache_location_bucket = nil
	end
	
	ArkInventorySearch_Stockpile:UnregisterMessage( "EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE" )
end

-- Inserts a location object into a location table
-- INPUT (table) location_table: location table where location object will be inserted
--                       may contain existing location objects
-- INPUT (table) location_object: object consisting of player_id, location_id, bag_id
-- RETURNS (table) the new location_table with the object inserted
function ArkInventorySearch_Stockpile.InsertLocationObject( location_table, location_object )
	if next( location_table ) ~= nil then
	
		for k,v in pairs( location_table ) do
			-- if the p,l,b pair already exists in table do nothing
			if v.player_id == location_object.player_id and v.location_id == location_object.location_id and v.bag_id == location_object.bag_id then
				return location_table
			end
		end
		
	end
	
	-- add the location object to table
	table.insert( location_table, location_object )
	return location_table
	
end

-- Gets the player_id based on the location
-- By default returns logged in player but may return guild_id or Account
-- depending on location
-- INPUT (int) location_id
-- RETURNS (string) the player_id that should be used for the location given
function ArkInventorySearch_Stockpile.PlayerIDLocation( location_id )
	local player_id = ArkInventory.PlayerIDSelf( )
	local player_data = ArkInventory.db.player.data[player_id]
	
	if location_id == ArkInventory.Const.Location.Vault then
		player_id = player_data.info.guild_id or player_id
	elseif location_id == ArkInventory.Const.Location.Pet or location_id == ArkInventory.Const.Location.Mount or location_id == ArkInventory.Const.Location.Toybox or location_id == ArkInventory.Const.Location.Heirloom then
		player_id = ArkInventory.PlayerIDAccount( )
	end
	
	return player_id
end

-- Helper function to make sure all the info fields we need from GetItemInfo and GetObjectInfoArray
-- are populated with some default value or reloaded from Blizzard servers
-- INPUT (table) info : info object, fields may vary but it should have class, name, id, h, q
-- RETURNS (table) info : info object with all fields needed or flagged for reload
function ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd, player_id, location_id, bag_id )
	info.invalidReasons = {}
	info.addToLoadingQueue = false
	
	-- if sd.h and info.h are both empty then we are missing some info
	-- set a default empty value and add to loading queue
	-- if ( sd.h == nil or sd.h == "[]" ) and ( info.h == nil or info.h == "[]" ) then
		-- --info.h = ( "|cff9d9d9d|H" .. info.objectid .. "::::::::::::|h[".. info.name .. "]|h|r" )
		-- info.addToLoadingQueue = true
		-- table.insert(info.invalidReasons, "missing_h")
	-- -- otherwise, if info is empty but we have it cached we should still reload
	-- elseif ( info.h == nil or info.h == "[]" ) and ( sd.h ~= nil and sd.h ~= "[]" ) then
		-- info.addToLoadingQueue = true
		-- table.insert(info.invalidReasons, "missing_h")
	-- end
	
	if info.h ~= sd.h then
		info.h = sd.h
	end
	
	-- if qualities don't match and info returns 1
	-- we most likely have the correct quality cached then, use sd
	if  sd.q ~= info.q and info.q == 1 then
		info.q = sd.q
	end
	
	if not info.q then info.q = 1 end
	
	-- if it is an item and it is missing name info we need to reload data
	if info.class == "item" and ( info.name == nil or info.name == "!---LOADING---!" or info.name == "" ) then
		info.name = info.name or "!---LOADING---!"
		info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "missing_name")
	end
	
	if info.name == nil or info.name == "" then
		info.name = "!---LOADING---!"
	end
	
	if info.class == "battlepet" then
		
		--info.itemtypeid = ArkInventory.Const.ItemClass.BATTLEPET
		--info.itemtype = ArkInventorySearch_Stockpile.LookupItemType( info.itemtypeid )
		info.itemtypeid = LE_ITEM_CLASS_BATTLEPET
		info.itemtype = AUCTION_CATEGORY_BATTLE_PETS
		info.uselevel = 0
		if info.sd == nil then
			info.sd = ArkInventory.Collection.Pet.ScanSpecies( info.id )
			if info.sd then
				info.name = info.sd.name or info.name
				info.texture = info.sd.icon or info.texture
				info.ilvl = info.sd.level or info.ilvl
				info.itemsubtypeid = info.sd.petType or info.itemsubtypeid
			end
		end
	end
	
	if info.class == "currency" then
		print("found currency")
		print("type: " .. info.itemtype)
		print("typeid: " .. info.itemtypeid)
		print("subtype: " .. info.itemsubtype)
		print("subtypeid: " .. info.itemsubtypeid)
		info.itemtypeid = LE_ITEM_CLASS_MISCELLANEOUS
		info.itemtype = "Currency"
		info.itemsubtypeid = LE_ITEM_MISCELLANEOUS_MOUNT + 200
		info.itemsubtype = "Currency"
		print("type: " .. info.itemtype)
		print("typeid: " .. info.itemtypeid)
		print("subtype: " .. info.itemsubtype)
		print("subtypeid: " .. info.itemsubtypeid)
	elseif info.class == "spell" and location_id == ArkInventory.Const.Location.Mount then
		info.itemtype = "Account Mount"
		info.itemtypeid = LE_ITEM_CLASS_MISCELLANEOUS
		info.itemsubtypeid = LE_ITEM_MISCELLANEOUS_MOUNT + 10
	end
	
	
	
	local pattern_valid_link = "^|cff%w%w%w%w%w%w|H%w+:[%-?%d:]+|h.-|h|r$"
	local pattern_valid_item_string = "^%w+:%-?%d+:[%-?%d:]+"
	local pattern_valid_object_id = "^%w+:%d+"
	local pattern_valid_battlepet_string = "^|cff%w%w%w%w%w%w|Hbattlepet:[%-?%d:]+:.-|h.-|h|r$"
	local pattern_valid_battlepet_string2 = "^battlepet:%-?%d+:[%-?%d:]+.-:$"
	
	-- is a valid item string, use it to build the rest of the link
	if not string.find(info.h, pattern_valid_link) and string.find(info.h, pattern_valid_item_string) then
		local item_string = string.match(info.h, pattern_valid_item_string)
		local oldh = info.h
		local r, g, b, hex = GetItemQualityColor( info.q or 1 )
		info.h = "|c" .. hex .. "|H" .. item_string .. "|h[" .. info.name .. "]|h|r"
		--info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "bad_h1: " .. info.name .. " oldh: " .. oldh .. " h: " .. info.h)
	-- is a valid class:id pair, use it to build the rest of the link
	elseif not string.find(info.h, pattern_valid_link) and not string.find(info.h, pattern_valid_item_string) and string.find(info.h, pattern_valid_object_id) then
		local object_id = string.match(info.h, pattern_valid_object_id)
		local oldh = info.h
		local r, g, b, hex = GetItemQualityColor( info.q or 1 )
		info.h = "|c" .. hex .. "|H" .. info.h .. ":::::::::" .. "|h[" .. info.name .. "]|h|r"
		--info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "bad_h2: " .. info.name .. " oldh: " .. oldh .. " h: " .. info.h)
	-- battlepet strings - can ignore
	elseif string.find(info.h, pattern_valid_battlepet_string) or string.find(info.h, pattern_valid_battlepet_string2) then
		-- battlepet string
	-- no known itemstring format found...
	-- use for debugging
	elseif not string.find(info.h, pattern_valid_link) and not string.find(info.h, pattern_valid_item_string) and not string.find(info.h, pattern_valid_object_id) then
		print("bad h with no fix: " .. info.h)
		print("bad h escaped: " .. string.gsub(info.h, "%|", "#"))
	end
	
	
	
	-- -- if sd.h and info.h are both empty then we are missing some info
	-- -- set a default empty value and add to loading queue
	-- if ( sd.h == nil or sd.h == "[]" ) and ( info.h == nil or info.h == "[]" ) then
		-- info.h = ( "|cff9d9d9d|H" .. info.objectid .. "::::::::::::|h[".. info.name .. "]|h|r" )
		-- info.addToLoadingQueue = true
	-- -- otherwise, if info is empty but we have it cached we should still reload
	-- elseif ( info.h == nil or info.h == "[]" ) and ( sd.h ~= nil and sd.h ~= "[]" ) then
		-- info.addToLoadingQueue = true
	-- end
	
	if not info.class or not info.id or info.class == "" or info.id == "" then
		print("missing ods")
		local osd = ArkInventory.ObjectStringDecode( info.h )
		info.class = osd.class
		info.id = info.osd.id
		print("class: " .. info.class)
		print("id:" .. info.id)
	end
		
	info.objectid = string.format( "%s:%s", info.class, info.id )
	
	if not info.itemtype then
		info.itemtype = info.info[6] or ArkInventory.Localise["UNKNOWN"]
	end
	
	if not info.itemsubtype then
		info.itemsubtype = info.info[7] or ArkInventory.Localise["UNKNOWN"]
	end
	
	if not info.itemtypeid then
		info.itemtypeid = info.info[12] or -2
	end
	
	if not info.itemsubtypeid then
		info.itemsubtypeid = info.info[12] or -2
	end

	
	if string.lower( info.itemtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
			info.itemtype = ArkInventorySearch_Stockpile.LookupItemType( info.itemtypeid )
	end
	
	if string.lower( info.itemsubtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
		info.itemsubtype = ArkInventorySearch_Stockpile.LookupItemType( info.itemsubtypeid )
	end
	
	if info.class == "item" and string.lower( info.itemtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
		info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "missing_itemtype")
	end
	
	if info.class == "item" and string.lower( info.itemsubtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
		info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "missing_itemsubtype")
	end
	
	if info.class == "item" and info.ilvl == -1 then
		info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "missing_ilvl")
	end
	
	if info.class == "item" and info.uselevel == -1 then
		info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "missing_uselevel")
	end
	
	info.search_text = ( info.name .. info.itemtype .. info.itemsubtype )
	
	info.location_object = { player_id = player_id, location_id = location_id, bag_id = bag_id }
	
	
	--local tooltip = StockpileScrollFrameTooltips[i]
	--local tooltip = StockpileGetScanningTooltip()
	
	local tooltip = ArkInventory.Global.Tooltip.Scan
	tooltip:ClearLines()
	
	
	if info.h then
		ArkInventory.TooltipSetHyperlink( tooltip, info.h )
	end
	
	local line1 = _G[string.format( "%sTextLeft1", tooltip:GetName( ) )]:GetText( ) or "EMPTY"
	local num_lines = tooltip:NumLines( ) or 0
	local tooltip_canUse = true
	local txt = ""
	local tooltip_trigger_text = ""
	local trigger_text = "!!"
	
	txt = "(" .. num_lines .. ")" .. line1
	
	if info.class == "item" and ( num_lines < 1 or line1 == "Retrieving item information"  or line1 == "EMPTY" ) then
		info.addToLoadingQueue = true
		table.insert(info.invalidReasons, "missing tooltip info")
		-- print("missing tooltip info")
	end
	
	local obj, txt1, txt2
	
	if num_lines > 0 then
		for i = 2, num_lines  do
			obj = _G[string.format( "%s%s%s", tooltip:GetName( ), "TextLeft", i )]
			if obj and obj:IsShown( ) then
				txt1 = obj:GetText( )
			end
			
			local r, g, b = obj:GetTextColor( )
			local c = string.format( "%02x%02x%02x", r * 255, g * 255, b * 255 )
			if c == "fe1f1f" or c == RED_FONT_COLOR_CODE then
				if txt1 == ArkInventory.Localise["ALREADY_KNOWN"] then
					tooltip_trigger_text = trigger_text .. "ALREADYKNOWN!!"
					tooltip_canUse = false
				elseif txt1 and txt1 ~= "" and txt1 ~= ArkInventory.Localise["NOT_DISENCHANTABLE"] and txt1 ~= ArkInventory.Localise["TOOLTIP_NOT_READY"] then
					tooltip_trigger_text = trigger_text .. txt1 .. "!!"
					tooltip_canUse = false
				end
			end
			
			obj = _G[string.format( "%s%s%s", tooltip:GetName( ), "TextRight", i )]
			if obj and obj:IsShown( ) then
				txt2 = obj:GetText( )
			end
			
			r, g, b = obj:GetTextColor( )
			local c2 = string.format( "%02x%02x%02x", r * 255, g * 255, b * 255 )
			if c2 == "fe1f1f" or c2 == RED_FONT_COLOR_CODE then
				if txt2 == ArkInventory.Localise["ALREADY_KNOWN"] then
					tooltip_trigger_text = trigger_text .. "ALREADYKNOWN!!"
					tooltip_canUse = false
				elseif txt2 and txt2 ~= "" and txt2 ~= ArkInventory.Localise["NOT_DISENCHANTABLE"] and txt2 ~= ArkInventory.Localise["TOOLTIP_NOT_READY"] then
					tooltip_trigger_text = trigger_text .. txt2 .. "!!"
					tooltip_canUse = false
				end
			end
			
			-- this would be better as a table, then we could store lines at an index
			-- and store tooltip lines at index i
			txt = string.format( "%s #C%s#C #%s# #C%s#C #%s#", txt, c, txt1 or "", c2, txt2 or "" )
		end
	end
	
	local is_usable = true
	
	--if info.location_table and info.location_table[1] then
		-- we only need location_id for collections so
		-- can just use the first entry in location table as it
		-- should be the only one or the same throughout
		--local location_id = info.location_table[1].location_id or -1
		if info.h and location_id then
			
			--local osd = ArkInventory.ObjectStringDecode( info.h )
			
			if location_id == ArkInventory.Const.Location.Pet or info.class == "battlepet" then
				
				-- local player_id = ArkInventory.PlayerIDAccount( )
				-- local account = ArkInventory.GetPlayerStorage( player_id )
				
				if info.uselevel and ( UnitLevel("player") < info.uselevel ) then
					trigger_text = trigger_text .. "BATTLEPETNOUSE!!"
					is_usable = false
				end
				
			elseif location_id == ArkInventory.Const.Location.Mount then
				local item_string = { strsplit(":", info.id) }
				local item_id = item_string[2]
				if not IsUsableSpell( item_id ) then
					trigger_text = trigger_text .. "MOUNTNOUSE!!"
					is_usable = false
				end
				
			elseif location_id == ArkInventory.Const.Location.Heirloom or location_id == ArkInventory.Const.Location.Toybox then
				
				--ArkInventory.TooltipSetHyperlink( tooltip, info.h )
				
				-- if not ArkInventory.TooltipCanUse( tooltip, true ) then
					-- is_usable = false
				-- end
				trigger_text = tooltip_trigger_text
				is_usable = tooltip_canUse
			else
				
				--ArkInventory.TooltipSetHyperlink( tooltip, info.h )
				trigger_text = tooltip_trigger_text
				is_usable = tooltip_canUse
				
			end
		else
			txt = "missing h or location"
		end
	--end
	
	info.canUse = is_usable
	info.tooltip_text = txt .. trigger_text
	
	return info
	
end


-- CACHE FUNCTIONS ----------------------------------------------


-- Batch adds all info objects passed in as table to the global cache then refresh search table
-- INPUT (table) object_info_table : a table containing item info to be added to global cache
--							 		 Each object should have name, h, q, texture, location_object
function ArkInventorySearch_Stockpile.AddItemsToSearchCache( object_info_table )
	local location_table
	local cache_object
	for object_id, object_info in pairs( object_info_table ) do
		location_table = { }
		cache_object = { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, search_text = object_info.search_text, itemtypeid = object_info.itemtypeid, itemsubtypeid = object_info.itemsubtypeid, itemtype = object_info.itemtype, itemsubtype = object_info.itemsubtype, class = object_info.class, equiploc = object_info.equiploc, ilvl = object_info.ilvl, uselevel = object_info.uselevel, canUse = object_info.canUse, tooltip_text = object_info.tooltip_text }
		
		-- if not already cached create a fresh location table
		if not ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] then
			location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, object_info.location_object )
			ArkInventorySearch_Stockpile.AddItemStatistics( object_info )
			-- ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, location_table = location_table, search_text = object_info.search_text }
		-- else, if it is already cached make sure we copy any existing location data
		else
			location_table = ArkInventorySearch_Stockpile.GlobalSearchCache[object_id].location_table
			location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, object_info.location_object )
			-- ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, location_table = location_table, search_text = object_info.search_text }
		end
		
		-- add location table to cache object
		cache_object.location_table = location_table
		
		-- add or update the cache entry in global cache
		ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = cache_object

		-- Make sure we add a search cache index entry for reverse lookups
		ArkInventorySearch_Stockpile.AddSearchCacheIndex( object_info.location_object.player_id, object_info.location_object.location_id, object_info.location_object.bag_id, object_id )
		
	end
	
	-- Make sure the UI exists, ignore table refresh if we are building the whole cache (performance)
	if ARKINV_Search_Stockpile and not ArkInventorySearch_Stockpile.IsBuilding then
		print("refreshing table...")
		ArkInventorySearch_Stockpile.Frame_Table_Refresh( )
	end
	
end

-- Adds a search cache index to the GlobalSearchCacheIndexLookup table
-- INPUT (string) player_id
-- INPUT (int) location_id
-- INPUT (int) bag_id
-- INPUT (string) object_id (format is CLASS:ID e.g. item:44571)
function ArkInventorySearch_Stockpile.AddSearchCacheIndex( player_id, location_id, bag_id, object_id )

	ArkInventorySearch_Stockpile.ValidateSearchCacheIndex( player_id, location_id, bag_id )
	if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id][object_id] then
		ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id][object_id] = object_id
	end
	
end

-- Checks if there is a table in the GlobalSearchCacheIndexLookup
-- given a p,l,b.  If the p,l,b does not yet exist it is created
-- INPUT (string) player_id
-- INPUT (int) location_id
-- INPUT (int) bag_id
function ArkInventorySearch_Stockpile.ValidateSearchCacheIndex( player_id, location_id, bag_id )

	if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id] then
		ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id] = { }
	end
	
	if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id] then
		ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id] = { }
	end
	
	if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id] then
		ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id] = { }
	end
end

-- Clears all items from the global cache that are found in a specific container given a p,l,b
-- Note, if the item exists somewhere else (e.g. p2,l2,b2) the location for p,l,b is cleared
-- in the global cache entries location table but the item remains in the global cache
-- as it still exists at p2,l2,b2
-- INPUT (string) player_id
-- INPUT (int) location_id
-- INPUT (int) bag_id
function ArkInventorySearch_Stockpile.Clear_Container( player_id, location_id, bag_id )

	ArkInventorySearch_Stockpile.ValidateSearchCacheIndex( player_id, location_id, bag_id )
	
	local info
	-- use GlobalSearchCacheIndexLookup to reverse lookup all items in this p,l,b
	for object_id, _ in pairs( ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id] ) do
		if ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] then
			
			info = ArkInventorySearch_Stockpile.GlobalSearchCache[object_id]
			
			if next( info ) ~= nil and next( info.location_table ) ~= nil then
				-- loop through all locations for this item, if it matches this p,l,b remove it
				for index, location_object in pairs( info.location_table ) do
					if location_object.player_id == player_id and location_object.location_id == location_id and location_object.bag_id == bag_id then
						info.location_table[index] = nil
						ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id][object_id] = nil
						ArkInventorySearch_Stockpile.RemoveItemStatistics( info )
					end
				end
				
				-- if there are no locations left for this item remove it entirely from cache
				if next( info.location_table ) == nil then
					ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = nil
				end
				
			end
			
		end
		
	end
	
end

-- This will, for a given player, location pair, remove all items from global cache
-- in that location and then repopulate the cache for that location
-- INPUT (string) player_id
-- INPUT (int) location_id
function ArkInventorySearch_Stockpile.RecacheLocation( player_id, location_id )
	local player_data = ArkInventory.db.player.data[player_id]
	-- first clear all items in global cache that are in these bags
	for bag_id, bag_data in pairs( player_data.location[location_id].bag ) do
		ArkInventorySearch_Stockpile.Clear_Container( player_id, location_id, bag_id )
	end
	-- now recache all items from these bags
	for bag_id, bag_data in pairs( player_data.location[location_id].bag ) do
		ArkInventorySearch_Stockpile.RecacheContainer( player_id, location_id, bag_id )
	end
end

-- For a given p,l,b recache all items in that container
-- Don't need to clear container here as we assume it was already done
-- or we are only operating on a single container so it is irrelevant
-- INPUT (string) player_id
-- INPUT (int) location_id
-- INPUT (int) bag_id
function ArkInventorySearch_Stockpile.RecacheContainer( player_id, location_id, bag_id )

	local player_data = ArkInventory.db.player.data[player_id]
	
	local bag = player_data.location[location_id].bag[bag_id]
	
	local item_cache_table = { }
	
	-- loop through every slot in this bag
	for s, sd in pairs( bag.slot ) do
		if sd.h then
			local info = ArkInventory.ObjectInfoArray( sd.h )

			info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd, player_id, location_id, bag_id  )
			
			-- if info is missing data add this item to loading queue
			if info.class == "item" and info.addToLoadingQueue then
				--ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = {h = info.h, q = info.q, player_id = player_id, location_id = location_id, bag_id = bag_id}
				ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = info
			-- otherwise, add it to local cache table if not already
			elseif not item_cache_table[info.objectid] and info.class ~= "copper" then
				-- item_cache_table[info.objectid] = { name = info.name, h = info.h, q = info.q, texture = info.texture, player_id = player_id, location_id = location_id, bag_id = bag_id, search_text = info.search_text }
				item_cache_table[info.objectid] = info
			end
		end	
	end
	
	-- batch add local cache table to global cache
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
	ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
end


-- Called after an auction bid, post-hook is after default function,
-- If the bid was a buyout grab the item info and store as sent mail
-- then trigger a mail cache update
function ArkInventorySearch_Stockpile.HookPlaceAuctionBid( auction_type, index, bid )
	
	if not ArkInventory:IsEnabled( ) then return end
	
	local loc_id = ArkInventory.Const.Location.Mail
	
	if not ArkInventory.LocationIsMonitored( loc_id ) then return end
	
	table.wipe( ArkInventory.Global.Cache.SentMail )
	
	local player_id = ArkInventory.PlayerIDSelf( )
	
	local name, texture, count, _, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo( auction_type, index )
	
	if bid >= buyoutPrice then
		ArkInventory.Global.Cache.SentMail.to = player_id
		ArkInventory.Global.Cache.SentMail.from = "Auction House"
		ArkInventory.Global.Cache.SentMail.age = ArkInventory.TimeAsMinutes( )
		
		if name then
			ArkInventory.Global.Cache.SentMail[1] = { n = name, c = count, h = GetAuctionItemLink( auction_type, index ) }
		end
		
		ArkInventory.ScanMailSentData( )
		ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE" )
	end
	
end

-- Called when an auction is cancelled.  Pre-hook before normal function
-- grabs the item info and stores it as a sent mail then trigger
-- a mail cache update
function ArkInventorySearch_Stockpile.HookCancelAuction( index )
	
	if not ArkInventory:IsEnabled( ) then return end
	
	local loc_id = ArkInventory.Const.Location.Mail
	
	if not ArkInventory.LocationIsMonitored( loc_id ) then return end
	
	table.wipe( ArkInventory.Global.Cache.SentMail )
	
	local player_id = ArkInventory.PlayerIDSelf( )
	
	-- known character, store sent mail data
	ArkInventory.Global.Cache.SentMail.to = player_id
	ArkInventory.Global.Cache.SentMail.from = "Auction House"
	ArkInventory.Global.Cache.SentMail.age = ArkInventory.TimeAsMinutes( )
	
	local name, texture, count = GetAuctionItemInfo( "owner", index )
	if name then
		ArkInventory.Global.Cache.SentMail[1] = { n = name, c = count, h = GetAuctionItemLink( "owner", index ) }
	end
	
	ArkInventory.ScanMailSentData( )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE" )
end

-- Wrapper for building global search cache
-- Sends ace message to trigger actual cache building function
-- Then unregisters the ace message.  This way we only build the entire
-- cache once.  All furthre updates should be triggered on inventory events
-- and only rebuild parts of the cache.
-- Finally, register the cache events after some interval using a timer
-- allowing us to avoid many unnecessary event triggers after screen loads.
function ArkInventorySearch_Stockpile.BuildGlobalSearchCache( )

	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_BUILD_GLOBAL_CACHE" )
	ArkInventorySearch_Stockpile:UnregisterMessage( "EVENT_ARKINV_BUILD_GLOBAL_CACHE" )
	C_Timer.After( 10, ArkInventorySearch_Stockpile.RegisterSearchCacheEvents )
	
end

local empty_count = 0
-- Loops through all p,l,b in ArkInventory.db and builds global cache
-- Items that are missing data are put in the loading queue
function ArkInventorySearch_Stockpile:EVENT_ARKINV_BUILD_GLOBAL_CACHE( )

	ArkInventorySearch_Stockpile.IsBuilding = true
	ArkInventorySearch_Stockpile.GlobalSearchCache = { }
	ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup = { }
	
	empty_count = 0
	
	local item_cache_table = { }

	for p, pd in ArkInventory.spairs( ArkInventory.db.player.data ) do
		
		if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[p] then
			ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[p] = { }
		end
		
		for l, ld in pairs( pd.location ) do
			
			if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[p][l] then
				ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[p][l] = { }
			end
			
			for b, bd in pairs( ld.bag ) do
				
				if not ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[p][l][b] then
					ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[p][l][b] = { }
				end
				
				item_cache_table = { }
				
				for s, sd in pairs( bd.slot ) do
					if sd.h then
						local info = ArkInventory.ObjectInfoArray( sd.h )
						
						info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd, p, l, b )
						
						if info.class == "item" and info.addToLoadingQueue then
							-- this should only happen when an item is not cached or cached item is missing info
							-- send item to loading queue to be handled on EVENT_WOW_GET_ITEM_INFO_RECEIVED
							-- ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = { h = info.h, q = info.q, player_id = p, location_id = l, bag_id = b }
							ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = info
						elseif info.addToLoadingQueue then
							print("add to queue but not item!!!!!!!!!!!!!!!!!")
						elseif not item_cache_table[info.objectid] then
							-- item_cache_table[info.objectid] = { name = info.name, h = info.h, q = info.q, texture = info.texture, player_id = p, location_id = l, bag_id = b, search_text = info.search_text }
							item_cache_table[info.objectid] = info
						end
					else
						empty_count = empty_count + 1
					end
				end
				
				ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
				ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
			end
			
		end
		
	end
	ArkInventorySearch_Stockpile.IsBuilding = false
	print("Empty count: " .. empty_count)
	if ARKINV_Search_Stockpile and not ArkInventorySearch_Stockpile.IsBuilding then
		ArkInventorySearch_Stockpile.Frame_Table_Refresh( )
	end
end

function ArkInventorySearch_Stockpile.AddItemStatistics( info )
	-- local itemtype = info.itemtype
	-- local subtype = info.itemsubtype
	-- if itemtype == ArkInventory.Localise["UNKNOWN"] then
		-- itemtype = ArkInventorySearch_Stockpile.LookupItemType( info.itemtypeid )
	-- end
	
	-- if subtype == ArkInventory.Localise["UNKNOWN"] then
		-- subtype = ArkInventorySearch_Stockpile.LookupItemType( info.subtypeid )
	-- end
	
	-- local location_table = {}
	-- if not item_statistics.item_types[itemtype] then
		
		-- location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, info.location_object )
		-- item_statistics.item_types[itemtype] = { count = 1, location_table = location_table }
	-- else
		-- local found = false
		-- for id, loc_obj in pairs( item_statistics.item_types[itemtype].location_table ) do
			-- if info.location_object == loc_obj then
				-- found = true
			-- end
		-- end
		
		-- if not found then
			-- location_table = item_statistics.item_types[itemtype].location_table
			-- location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, info.location_object )
			-- item_statistics.item_types[itemtype] = { count = ( item_statistics.item_types[itemtype].count + 1 ), location_table = location_table }
		-- end
	-- end
end

function ArkInventorySearch_Stockpile.LookupItemType( itemtype_id )
	for type_string, type_id in pairs( ArkInventory.Const.ItemClass ) do
		if itemtype_id == type_id then
			return type_string
		end
	end
	return itemtype_id
end

function ArkInventorySearch_Stockpile.RemoveItemStatistics( info )
	-- local itemtype = info.itemtype
	-- if itemtype == ArkInventory.Localise["UNKNOWN"] then
		-- itemtype = ArkInventorySearch_Stockpile.LookupItemType( info.itemtypeid )
		-- if itemtype == -2 then
			-- itemtype = info.class
		-- end
	-- end
	-- if item_statistics.item_types[itemtype] then
		-- for id, loc_obj in pairs( item_statistics.item_types[itemtype].location_table ) do
			-- if loc_obj == info.location_object then
				-- loc_obj = nil
				-- item_statistics.item_types[itemtype].count = item_statistics.item_types[itemtype].count - 1
			-- end
		-- end
		-- if next( item_statistics.item_types[itemtype].location_table ) == nil then
			-- item_statistics.item_types[itemtype] = nil
		-- end
	-- end
end

ArkInventorySearch_Stockpile:RegisterChatCommand("stockpile_print_stats", "PrintItemStatistics")

function ArkInventorySearch_Stockpile:PrintItemStatistics( )
	item_statistics = { 
		item_types = { }
	}
	print( " " )
	print( "-- ITEM STATISTICS ------------------------------------" )
	print( " " )
	
	local total_count = 0
	for objectid, objectinfo in pairs( ArkInventorySearch_Stockpile.GlobalSearchCache ) do 
		total_count = total_count + 1 
		
		if not item_statistics.item_types[objectinfo.itemtype] then
			if not objectinfo.itemtype or not objectinfo.itemsubtype then
				if not objectinfo.itemtype then
					print("missing itemtype")
				end
				if not objectinfo.itemsubtype then
					print("missing itemsubtype")
				end
			else
				item_statistics.item_types[objectinfo.itemtype] = { itemtypeid = objectinfo.itemtypeid, count = 1, subtypes = { }, classes = { }, items = {} }
				item_statistics.item_types[objectinfo.itemtype].subtypes[objectinfo.itemsubtype] = { count = 1 }
				item_statistics.item_types[objectinfo.itemtype].classes[objectinfo.class] = { count = 1 }
				item_statistics.item_types[objectinfo.itemtype].items[objectid] = objectinfo
			end
		else
			item_statistics.item_types[objectinfo.itemtype].count = item_statistics.item_types[objectinfo.itemtype].count + 1
			local found = false
			for subtype, subtype_info in pairs( item_statistics.item_types[objectinfo.itemtype].subtypes ) do
				if subtype == objectinfo.itemsubtype then
					found = true
					break
				end
			end
			if not found then
				item_statistics.item_types[objectinfo.itemtype].subtypes[objectinfo.itemsubtype] = { count = 1 }
			else
				item_statistics.item_types[objectinfo.itemtype].subtypes[objectinfo.itemsubtype].count = item_statistics.item_types[objectinfo.itemtype].subtypes[objectinfo.itemsubtype].count + 1
			end
			
			found = false
			for class, class_info in pairs( item_statistics.item_types[objectinfo.itemtype].classes ) do
				if class == objectinfo.class then
					found = true
					break
				end
			end
			if not found then
				item_statistics.item_types[objectinfo.itemtype].classes[objectinfo.class] = { count = 1 }
			else
				item_statistics.item_types[objectinfo.itemtype].classes[objectinfo.class].count = item_statistics.item_types[objectinfo.itemtype].classes[objectinfo.class].count + 1
			end
			
			found = false
			for item_id, item_info in pairs( item_statistics.item_types[objectinfo.itemtype].items ) do
				if item_id == objectid then
					found = true
					break
				end
			end
			if not found then
				item_statistics.item_types[objectinfo.itemtype].items[objectid] = objectinfo
			end
		end
	end
	
	
	
	local item_type_total = 0
	local item_subtype_total = 0
	local item_name_count = 0
	for item_type, item_info in pairs( item_statistics.item_types ) do
		print("+" .. item_type .. "[" .. item_info.itemtypeid .. "] ( " .. item_info.count .. " )" )
		for item_subtype, item_subtype_info in pairs( item_info.subtypes ) do
			--print(" |__" .. item_subtype .. "( " .. item_subtype_info.count .. " )" )
			item_subtype_total = item_subtype_total + 1
		end
		
		if string.lower( item_type ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
			for item_class, item_class_info in pairs( item_info.classes ) do
				--print("   |__" .. item_class .. "( " .. item_class_info.count .. " )" )
				
				--if item_class == "item" then
					for item_id, item_info in pairs( item_info.items ) do
						print( "     |__" .. item_info.name .. ": " .. item_id .. " : " .. item_info.h)
						item_name_count = item_name_count + 1
						if item_name_count == 10 then
							break
						end
					end
				--end
				
			end
		end
		item_type_total = item_type_total + item_info.count
	end
	print( "SUMMARY:")
	print( "Cache total: " .. total_count )
	print( "Item Type total: " .. item_type_total )
	print( "Item SubType total: " .. item_subtype_total )
	print( " " )
	print( "-- END ITEM STATISTICS --------------------------------" )
	print( " " )
end

ArkInventorySearch_Stockpile:RegisterChatCommand("aisp-build", "CommandBuildGlobalSearchCache")

function ArkInventorySearch_Stockpile.CommandBuildGlobalSearchCache( )
	ArkInventorySearch_Stockpile:EVENT_ARKINV_BUILD_GLOBAL_CACHE( )
end

ArkInventorySearch_Stockpile:RegisterChatCommand("aisp-refreshtable", "CommandRefreshSearchTable")

function ArkInventorySearch_Stockpile.CommandRefreshSearchTable( )
	if ARKINV_Search_Stockpile and not ArkInventorySearch_Stockpile.IsBuilding then
		print("refreshing table...")
		ArkInventorySearch_Stockpile.Frame_Table_Refresh( )
	end
end

ArkInventorySearch_Stockpile:RegisterChatCommand("aisp-petprint", "PetPrint")

function ArkInventorySearch_Stockpile.PetPrint( )
	local speciesName, speciesIcon, petType, companionID, tooltipSource, tooltipDescription, isWild, canBattle, isTradeable, isUnique, obtainable, creatureDisplayID = C_PetJournal.GetPetInfoBySpeciesID(731)

	print("speciesName: " .. speciesName)
	print("petType: " .. petType)
	print("companionID: " .. companionID)
	print("creatureDisplayID: " .. creatureDisplayID)
end


ArkInventorySearch_Stockpile:RegisterChatCommand("aisp-showq", "ShowLoadingQueue")

function ArkInventorySearch_Stockpile.ShowLoadingQueue( )
	local count = 0
	for objectid, objectinfo in pairs( ArkInventorySearch_Stockpile.ItemLoadingQueue ) do
		if count < 3 then
			print("oid: " .. objectid .. " oinfo: " .. table.tostring(objectinfo))
			if ArkInventorySearch_Stockpile.GlobalSearchCache[objectid] then
				print("found in cache...")
				print("oid: " .. objectid .. " oinfo: " .. table.tostring(ArkInventorySearch_Stockpile.GlobalSearchCache[objectid]))
			end
		end
		count = count + 1
	end
	print( "queue count: " .. count )
end

ArkInventorySearch_Stockpile:RegisterChatCommand("aisp-runq", "RunLoadingQueue")

function ArkInventorySearch_Stockpile.RunLoadingQueue( )
	ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
end