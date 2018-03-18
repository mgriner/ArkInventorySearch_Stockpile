
--[[
	GLOBAL SEARCH CACHE
	Functions to build an in-memory local cache of
	inventory across global account.  This will store
	item information for all characters in a table accessible
	at ArkInventorySearch_Stockpile.GlobalSearchCache.
	
	Items are loaded once from SavedVariables at login.  After that
	updates are triggered when there is an inventory change.
	The container or location triggering the event will be cleared and re-cached.
	This avoids having to re-cache the entire global item cache.
	
	In the event that GetItemInfo has failed to retrieve item info due to either
	the item not being locally cached or a throttle on Blizzards side
	items will be added to a loading queue.  When the information is available
	from the server it will fire the GET_ITEM_INFO_RECEIVED event and cache the item.
]]--


local _G = _G
local select = _G.select
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local type = _G.type
local error = _G.error
local table = _G.table

ArkInventorySearch_Stockpile = LibStub( "AceAddon-3.0" ):NewAddon( "ArkInventorySearch_Stockpile", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceBucket-3.0" )

-- ArkInventorySearch_Stockpile.GlobalSearchCache
-- holds all cached items for search
-- Each entry contains:
-- { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, locationTable = location_table }
-- location_table is a table of entries containing (player_id, location_id, bag_id) for every p,l,b that contains this item
-- GlobalSearchCache is indexed by the objectid which has the format CLASS:ID, e.g. item:44571 so you can access item info
-- for this object like so: GlobalSearchCache["item:44571"] which would return cached item info for Bottle of Silvermoon Port
-- including a location table which tells us every p,l,b where that item exists
ArkInventorySearch_Stockpile.GlobalSearchCache = { }
-- ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup
-- holds index of all items in a container
-- ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id]
-- contains an index for the GlobalSearchCache table for each item found for the player, location, bag pair referenced
-- used to recache a container by only updating cache entries found in the p,l,b lookup
ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup = { }

-- ArkInventorySearch_Stockpile.ItemLoadingQueue
-- holds items that were missing info after a call to ArkInventorySearch_Stockpile.ObjectInfoArray
-- When a GET_ITEM_INFO_RECEIVED event is fired if the triggering event is for an item
-- waiting in the ItemLoadingQueue than it will get that info and update the cache entry
ArkInventorySearch_Stockpile.ItemLoadingQueue = { }

local cache_bag_bucket	-- variable to store bucket
local cache_location_bucket	-- variable to store bucket

function ArkInventorySearch_Stockpile:OnEnable()
	-- overriding the default search table refresh function
	ArkInventorySearch_Stockpile:RawHook(ArkInventory.Search, "Frame_Table_Refresh", ArkInventorySearch_Stockpile.Frame_Table_Refresh, true)
  
	-- registering global cache specific events
	ArkInventorySearch_Stockpile:RegisterEvent( "PLAYER_ALIVE", "EVENT_WOW_PLAYER_ALIVE" )
	ArkInventorySearch_Stockpile:RegisterEvent( "GET_ITEM_INFO_RECEIVED", "EVENT_WOW_GET_ITEM_INFO_RECEIVED" )
	ArkInventorySearch_Stockpile:RegisterMessage( "EVENT_ARKINV_BUILD_GLOBAL_CACHE" )
	ArkInventorySearch_Stockpile:RegisterBucketMessage( "EVENT_ARKINV_GET_ITEM_INFO_RECEIVED_BUCKET", 2)
	
	-- registering global cache specific hooks
	-- auction functions
	ArkInventorySearch_Stockpile:SecureHook( "PlaceAuctionBid", ArkInventorySearch_Stockpile.HookPlaceAuctionBid )
	ArkInventorySearch_Stockpile:Hook( "CancelAuction", ArkInventorySearch_Stockpile.HookCancelAuction, true )
	
	-- hooking off storage scan updates
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanBag", ArkInventorySearch_Stockpile.HookScanBag )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanVault", ArkInventorySearch_Stockpile.HookScanVault )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanLocation", ArkInventorySearch_Stockpile.HookScanLocation )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanMailInbox", ArkInventorySearch_Stockpile.HookScanMailInbox )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanMailSentData", ArkInventorySearch_Stockpile.HookScanMailSentData )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "HookMailReturn", ArkInventorySearch_Stockpile.HookHookMailReturn )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanAuction", ArkInventorySearch_Stockpile.HookScanAuction )	
	-- hooking off collection scan updates
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanCollectionHeirloom", ArkInventorySearch_Stockpile.HookScanCollectionHeirloom)
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanCollectionMount", ArkInventorySearch_Stockpile.HookScanCollectionMount)
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanCollectionPet", ArkInventorySearch_Stockpile.HookScanCollectionPet )
	ArkInventorySearch_Stockpile:SecureHook( ArkInventory, "ScanCollectionToybox", ArkInventorySearch_Stockpile.HookScanCollectionToybox )
	
end


-- EVENTS ----------------------------------------------


-- Fired after PLAYER_ENTERING_WORLD
-- So player info should now be set.
function ArkInventorySearch_Stockpile:EVENT_WOW_PLAYER_ALIVE( )
	
	-- unregister cache events to avoid many unecessary calls at login/load
	ArkInventorySearch_Stockpile.UnregisterSearchCacheEvents( )
	-- build global search cache, will only fire once at login
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
		-- grab the item info now, it probably won't be available when the bucket triggers
		local name, h, q, _, _, _, _, _, _, texture = GetItemInfo( objectid )
		ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_GET_ITEM_INFO_RECEIVED_BUCKET", { objectid = objectid, name = name, h = h, q = q, texture = texture } )
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
		if ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] ~= nil then
		
			-- pull the p,l,b data before we clear entry from queue
			player_id = ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid].player_id
			location_id = ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid].location_id
			bag_id = ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid].bag_id
			
			-- clear entry from queue
			ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = nil
			
			-- if the item already exists in cache grab its info
			-- for comparison in validation function
			if ArkInventorySearch_Stockpile.GlobalSearchCache[info.objectid] then
				sd = { h = ArkInventorySearch_Stockpile.GlobalSearchCache[info.objectid].h, q = ArkInventorySearch_Stockpile.GlobalSearchCache[info.objectid].q }
			else
				sd = { h = info.h, q = info.q }
			end
			
			-- try to validate info
			info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd )

			-- if not valid add it back to the queue
			-- otherwise update/add the cache entry to local table
			if info.addToLoadingQueue then
				ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = { h = info.h, q = info.q, player_id = player_id, location_id = location_id, bag_id = bag_id }
			elseif not item_cache_table[info.objectid] then
				item_cache_table[info.objectid] = { name = info.name, h = info.h, q = info.q, texture = info.texture, player_id = player_id, location_id = location_id, bag_id = bag_id }
			end
		end
	end
	-- batch add this local update table to the global cache table
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
end


-- UTILITY FUNCTIONS ----------------------------------------------


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
function ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd )
	info.addToLoadingQueue = false
	
	-- if it is an item and it is missing name info we need to reload data
	if info.class == "item" and ( info.name == nil or info.name == "!---LOADING---!" or info.name == "" ) then
		info.name = info.name or "!---LOADING---!"
		info.addToLoadingQueue = true
	end
	
	if info.class == "battlepet" and info.sd == nil then
		info.sd = ArkInventory.Collection.Pet.ScanSpecies( info.id )
		if info.sd then
			info.name = info.sd.name or info.name
			info.texture = info.sd.icon or info.texture
			info.ilvl = info.sd.level or info.ilvl
			info.itemsubtypeid = info.sd.petType or info.itemsubtypeid
		end
	end
	
	if info.name == nil or info.name == "" then
		info.name = "!---LOADING---!"
	end
	
	-- if info.objectid is not populated yet try to do so
	-- may already populated from previous call to ValidateItemInfo
	-- e.g. items already stored in loading queue
	if not info.objectid then
		if not info.class or not info.id then
			info.class = info.class or "unknown"
			info.id = info.id or "unknown"
		end
		
		info.objectid = string.format( "%s:%s", info.class, info.id )
	end
	
	-- if sd.h and info.h are both empty then we are missing some info
	-- set a default empty value and add to loading queue
	if ( sd.h == nil or sd.h == "[]" ) and ( info.h == nil or info.h == "[]" ) then
		info.h = ( "|cff9d9d9d|H" .. info.objectid .. "::::::::::::|h[".. info.name .. "]|h|r" )
		info.addToLoadingQueue = true
	-- otherwise, if info is empty but we have it cached we should still reload
	elseif ( info.h == nil or info.h == "[]" ) and ( sd.h ~= nil and sd.h ~= "[]" ) then
		info.addToLoadingQueue = true
	end
	
	-- if qualities don't match and info returns 1
	-- we most likely have the correct quality cached then, use sd
	if  sd.q ~= info.q and info.q == 1 then
		info.q = sd.q
	end
	
	return info
	
end


-- CACHE FUNCTIONS ----------------------------------------------


-- Batch adds all info objects passed in as table to the global cache then refresh search table
-- INPUT (table) object_info_table : a table containing item info to be added to global cache
--							 		 Each object should have name, h, q, texture, player_id, location_id, and bag_id
function ArkInventorySearch_Stockpile.AddItemsToSearchCache( object_info_table )

	for object_id, object_info in pairs( object_info_table ) do
		local location_object = { player_id = object_info.player_id, location_id = object_info.location_id, bag_id = object_info.bag_id }
		local location_table = { }
		
		-- if not already cached add it
		if not ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] then
			location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, location_object )
			ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, locationTable = location_table }
		-- else, if it is already cached make sure we copy any existing location data
		else
			location_table = ArkInventorySearch_Stockpile.GlobalSearchCache[object_id].locationTable
			location_table = ArkInventorySearch_Stockpile.InsertLocationObject( location_table, location_object )
			ArkInventorySearch_Stockpile.GlobalSearchCache[object_id] = { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, locationTable = location_table }
		end

		-- Make sure we add a search cache index entry for reverse lookups
		ArkInventorySearch_Stockpile.AddSearchCacheIndex( object_info.player_id, object_info.location_id, object_info.bag_id, object_id )
		
	end
	
	if ARKINV_Search then
		ArkInventory.Search.Frame_Table_Refresh( )
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
			
			if next( info ) ~= nil and next( info.locationTable ) ~= nil then
				-- loop through all locations for this item, if it matches this p,l,b remove it
				for index, location_object in pairs( info.locationTable ) do
					if location_object.player_id == player_id and location_object.location_id == location_id and location_object.bag_id == bag_id then
						info.locationTable[index] = nil
						ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup[player_id][location_id][bag_id][object_id] = nil
					end
				end
				
				-- if there are no locations left for this item remove it entirely from cache
				if next( info.locationTable ) == nil then
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

			info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd )
			
			-- if info is missing data add this item to loading queue
			if info.class == "item" and info.addToLoadingQueue then
				ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = {h = info.h, q = info.q, player_id = player_id, location_id = location_id, bag_id = bag_id}
			-- otherwise, add it to local cache table if not already
			elseif not item_cache_table[info.objectid] and info.class ~= "copper" then
				item_cache_table[info.objectid] = { name = info.name, h = info.h, q = info.q, texture = info.texture, player_id = player_id, location_id = location_id, bag_id = bag_id }	
			end
		end	
	end
	
	-- batch add local cache table to global cache
	ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
	
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

-- Loops through all p,l,b in ArkInventory.db and builds global cache
-- Items that are missing data are put in the loading queue
function ArkInventorySearch_Stockpile:EVENT_ARKINV_BUILD_GLOBAL_CACHE( )

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
						
						info = ArkInventorySearch_Stockpile.ValidateItemInfo( info, sd )
						
						if info.class == "item" and info.addToLoadingQueue then
							-- this should only happen when an item is not cached or cached item is missing info
							-- send item to loading queue to be handled on EVENT_WOW_GET_ITEM_INFO_RECEIVED
							ArkInventorySearch_Stockpile.ItemLoadingQueue[info.objectid] = { h = info.h, q = info.q, player_id = p, location_id = l, bag_id = b }
						elseif not item_cache_table[info.objectid] then
							item_cache_table[info.objectid] = { name = info.name, h = info.h, q = info.q, texture = info.texture, player_id = p, location_id = l, bag_id = b }
						end
					end
				end
				
				ArkInventorySearch_Stockpile.AddItemsToSearchCache( item_cache_table )
				
			end
			
		end
		
	end
	
end


-- DEPENDENCIES ------------------------------------------------------------------------------
--
-- Listed here are references called from original ArkInventory addon, just for documentation
-- These are functions we would need to keep an eye on for changes that may affect
-- ArkInventorySearch_Stockpile (e.g. if the return value changes, or the function name changes)
--
-- ArkInventory.BlizzardBagIdToInternalId( blizzard_id )
-- ArkInventory.Collection.Pet.ScanSpecies( info.id )
-- ArkInventory.Const.Location.Heirloom
-- ArkInventory.Const.Location.Mail
-- ArkInventory.Const.Location.Mount
-- ArkInventory.Const.Location.Pet
-- ArkInventory.Const.Location.Toybox
-- ArkInventory.Const.Location.Vault
-- ArkInventory.db.player.data[player_id]
-- ArkInventory.Global.Cache.SentMail
-- ArkInventory.Global.Cache.SentMail.age
-- ArkInventory.Global.Cache.SentMail.from
-- ArkInventory.Global.Cache.SentMail.to
-- ArkInventory.LocationIsMonitored( loc_id )
-- ArkInventory.ObjectInfoArray( sd.h )
-- ArkInventory.PlayerIDSelf( )
-- ArkInventory.PlayerIDAccount( )
-- ArkInventory.ScanMailSentData( )
-- ArkInventory.Search.Frame_Table_Refresh( )
-- ArkInventory.spairs( ArkInventory.db.player.data )
-- ArkInventory.TimeAsMinutes( )




-- DIRECT OVERRIDES --------------------------------------------------------------------------
--
-- Any functions found in this section are direct overrides of the original ArkInventory
-- function.
--

-- Overrides table refresh function so that we can use our cached search data rather than
-- the normal search data from ArkInventory
function ArkInventorySearch_Stockpile.Frame_Table_Refresh( frame )
	local f
	if not frame then
		frame = ARKINV_SearchFrameViewSearchFilter
	end
	f = frame:GetParent( ):GetParent( ):GetParent( ):GetName( )
	f = string.format( "%s%s", f, "View" )
	
	ArkInventory.Search.Frame_Table_Reset( f )
	
	local filter = _G[string.format( "%s%s", f, "SearchFilter" )]:GetText( )
	--ArkInventory.Output( "filter = [", filter, "]" )
	filter = string.gsub( filter, "-", "--" ) -- escape hyphens or they won't work right
	
	local newSearchTable = {}
	local c = 0
	if ArkInventorySearch_Stockpile.GlobalSearchCache then
		for id, itemData in pairs(ArkInventorySearch_Stockpile.GlobalSearchCache) do
			if string.find( string.lower( itemData.name or "" ), string.lower( filter ) ) or filter == "" then
				c = c + 1
				newSearchTable[c] = itemData
			end
			
		end
		
	end
	ArkInventory.Search.SourceTable = newSearchTable
	
	if #ArkInventory.Search.SourceTable > 0 then
		table.sort( ArkInventory.Search.SourceTable, function( a, b ) return a.sorted < b.sorted end )
		ArkInventory.Search.Frame_Table_Scroll( frame )
	end

end


-- HOOKS -------------------------------------------------------------------------------------
--
-- Any functions found in this section are post hooks on functions triggered in ArkInventory.
-- They will not modify the original function but just do something else after the original
-- function has finished (e.g. letting ArkInventorySearch_Stockpile know some update happened)
--

-- STORAGE -----------------------------------------------------------------------------------


-- Used by Bag and Bank
function ArkInventorySearch_Stockpile.HookScanBag( blizzard_id )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_CONTAINER_UPDATE_BUCKET", blizzard_id)
end

function ArkInventorySearch_Stockpile.HookScanVault(  )
	local loc_id = ArkInventory.Const.Location.Vault
	local player_id = ArkInventorySearch_Stockpile.PlayerIDLocation( loc_id )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end

-- Used by Void Storage, Wearing, Currency
function ArkInventorySearch_Stockpile.HookScanLocation( loc_id )
	local player_id = ArkInventorySearch_Stockpile.PlayerIDLocation(loc_id)
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end

function ArkInventorySearch_Stockpile.HookScanMailInbox( )
	local loc_id = ArkInventory.Const.Location.Mail
	local player_id = ArkInventorySearch_Stockpile.PlayerIDLocation( loc_id )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end

function ArkInventorySearch_Stockpile.HookScanMailSentData( )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE")
end

function ArkInventorySearch_Stockpile.HookHookMailReturn( index )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_MAIL_SENT_UPDATE")
end

-- Used by AUCTION_UPDATE and AUCTION_UPDATE_MASSIVE
function ArkInventorySearch_Stockpile.HookScanAuction( massive )
	local loc_id = ArkInventory.Const.Location.Auction
	local player_id = ArkInventorySearch_Stockpile.PlayerIDLocation( loc_id )
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end


-- COLLECTIONS -------------------------------------------------------------------------------


function ArkInventorySearch_Stockpile.HookScanCollectionHeirloom( )
	local player_id = ArkInventory.PlayerIDAccount( )
	local loc_id = ArkInventory.Const.Location.Heirloom
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end

function ArkInventorySearch_Stockpile.HookScanCollectionMount( )
	local player_id = ArkInventory.PlayerIDAccount( )
	local loc_id = ArkInventory.Const.Location.Mount
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end

function ArkInventorySearch_Stockpile.HookScanCollectionPet( )
	local player_id = ArkInventory.PlayerIDAccount( )
	local loc_id = ArkInventory.Const.Location.Pet
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end

function ArkInventorySearch_Stockpile.HookScanCollectionToybox( )
	local player_id = ArkInventory.PlayerIDAccount( )
	local loc_id = ArkInventory.Const.Location.Toybox
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_ARKINV_SEARCH_CACHE_LOCATION_UPDATE_BUCKET", {player_id = player_id, location_id = loc_id} )
end