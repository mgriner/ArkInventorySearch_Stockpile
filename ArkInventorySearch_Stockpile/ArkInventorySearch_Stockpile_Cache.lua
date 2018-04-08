local _G = _G
local select = _G.select
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local type = _G.type
local error = _G.error
local table = _G.table

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
	-- print(item_id)
	-- if item_id == 102248 or item_id == 127829 then
		-- print("got info for: " .. objectid)
	-- end
	-- only pass to bucket if it's in the loading queue
	if ArkInventorySearch_Stockpile.ItemLoadingPool[objectid] ~= nil then
		
		local h = ArkInventorySearch_Stockpile.ItemLoadingPool[objectid].h
		
		-- grab the item info now, it probably won't be available when the bucket triggers
		local info = ArkInventory.ObjectInfoArray( h )
		
		-- pull the p,l,b data before we clear entry from queue
		info.player_id = ArkInventorySearch_Stockpile.ItemLoadingPool[objectid].location_object.player_id
		info.location_id = ArkInventorySearch_Stockpile.ItemLoadingPool[objectid].location_object.location_id
		info.bag_id = ArkInventorySearch_Stockpile.ItemLoadingPool[objectid].location_object.bag_id
		
		-- clear entry from queue
		ArkInventorySearch_Stockpile.ItemLoadingPool[objectid] = nil
		
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
	
	local item_info_table = ...
	local item_cache_table = { }
	local sd = { }
	local player_id, location_id, bag_id
	
	for info in pairs( item_info_table ) do
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
		if info.class == "item" and not info.isValid then
			ArkInventorySearch_Stockpile.ItemLoadingPool[info.objectid] = info
		elseif not item_cache_table[info.objectid] then
			item_cache_table[info.objectid] = info
		end
	end
	-- batch add this local update table to the global cache table
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
	ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
end


-- UTILITY FUNCTIONS ----------------------------------------------

function ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
	local item_cache_table = { }
	local info
	for objectid, objectinfo in pairs( ArkInventorySearch_Stockpile.ItemLoadingPool ) do
		
		-- clear from queue
		ArkInventorySearch_Stockpile.ItemLoadingPool[objectid] = nil
			
		info = ArkInventory.ObjectInfoArray( objectinfo.h )
					
		info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, info, objectinfo.location_object.player_id, objectinfo.location_object.location_id, objectinfo.location_object.bag_id )

		-- if item is not ready back into the queue, otherwise into the cache
		if info.class == "item" and not info.isValid then
			ArkInventorySearch_Stockpile.ItemLoadingPool[info.objectid] = info
		elseif not item_cache_table[info.objectid] then
			item_cache_table[info.objectid] = info
		end
	end
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
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
		-- else, if it is already cached make sure we copy any existing location data
		else
			location_table = ArkInventorySearch_Stockpile.GlobalSearchCache[object_id].location_table
			location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, object_info.location_object )
		end
		
		-- add location table to cache object
		cache_object.location_table = location_table
		
		-- add or update the cache entry in global cache
		ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = cache_object

		-- Make sure we add a search cache index entry for reverse lookups
		ArkInventorySearch_Stockpile.AddSearchCacheIndex( object_info.location_object.player_id, object_info.location_object.location_id, object_info.location_object.bag_id, object_id )
		
		-- Flag that the search cache has been updated
		ArkInventorySearch_Stockpile.IsGlobalSearchCacheUpdated = true;
		
	end
	
	-- Make sure the UI exists, ignore table refresh if we are building the whole cache (performance)
	if StockpileFrame and not ArkInventorySearch_Stockpile.IsBuilding then
		ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search();
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
			if info.class == "item" and not info.isValid then
				ArkInventorySearch_Stockpile.ItemLoadingPool[info.objectid] = info
			-- otherwise, add it to local cache table if not already
			elseif not item_cache_table[info.objectid] and info.class ~= "copper" then
				item_cache_table[info.objectid] = info
			end
		end	
	end
	
	-- batch add local cache table to global cache
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
	ArkInventorySearch_Stockpile.CleanUpLoadingQueue( )
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
	C_Timer.After( 6, ArkInventorySearch_Stockpile.RegisterSearchCacheEvents )
	
end

local empty_count = 0
-- Loops through all p,l,b in ArkInventory.db and builds global cache
-- Items that are missing data are put in the loading queue
function ArkInventorySearch_Stockpile:EVENT_ARKINV_BUILD_GLOBAL_CACHE( )

	ArkInventorySearch_Stockpile.IsBuilding = true
	ArkInventorySearch_Stockpile.GlobalSearchCache = { }
	ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup = { }
	ArkInventorySearch_Stockpile.ItemLoadingPool = { }
	
	empty_count = 0
	
	local item_cache_table = { }
	local info
	
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
						info = ArkInventory.ObjectInfoArray( sd.h )
						
						info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd, p, l, b )
						
						if info.class == "item" and not info.isValid then
							ArkInventorySearch_Stockpile.ItemLoadingPool[info.objectid] = info
						elseif not info.isValid then
							print("add to queue but not item!!!!!!!!!!!!!!!!!")
						elseif not item_cache_table[info.objectid] then
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
	if StockpileFrame and not ArkInventorySearch_Stockpile.IsBuilding then
		ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search();
	end
end
