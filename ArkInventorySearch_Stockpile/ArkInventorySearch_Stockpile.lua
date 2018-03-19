
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
ArkInventorySearch_Stockpile:SetDefaultModuleState(false)

local search = ArkInventorySearch_Stockpile:NewModule( "ArkInventorySearch_Stockpile" )

function search:OnEnable( )
	ArkInventory.Search.frame = ARKINV_Search_Stockpile
	ArkInventory.Search.rebuild = true
	ArkInventory.Search.SourceTable = { }
	
	search.cache = { }
	
end

function search:OnDisable( )
	
	ArkInventory.Search.Frame_Hide( )
	table.wipe( ArkInventory.Search.SourceTable )
	
	table.wipe( search.cache )
	
end

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
	ArkInventory:DisableModule( "ArkInventorySearch" )
	ArkInventorySearch_Stockpile:EnableModule( "ArkInventorySearch_Stockpile" )
	-- overriding the default search table refresh function
	--ArkInventorySearch_Stockpile:RawHook(ArkInventory.Search, "Frame_Table_Refresh", ArkInventorySearch_Stockpile.Frame_Table_Refresh, true)
  
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

function ArkInventorySearch_Stockpile:OnDisable()
	ArkInventorySearch_Stockpile:UnhookAll( )
	
	ArkInventorySearch_Stockpile:UnregisterEvent( "PLAYER_ALIVE", "EVENT_WOW_PLAYER_ALIVE" )
	ArkInventorySearch_Stockpile:UnregisterEvent( "GET_ITEM_INFO_RECEIVED", "EVENT_WOW_GET_ITEM_INFO_RECEIVED" )
	ArkInventorySearch_Stockpile:UnregisterMessage( "EVENT_ARKINV_BUILD_GLOBAL_CACHE" )
	ArkInventorySearch_Stockpile.UnregisterSearchCacheEvents( )
	ArkInventorySearch_Stockpile:UnregisterAllBuckets( )
	
	ArkInventory:DisableModule( "ArkInventorySearch_Stockpile" )
	ArkInventorySearch_Stockpile:EnableModule( "ArkInventorySearch" )
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
		frame = ARKINV_Search_StockpileFrameViewSearchFilter
	end
	f = frame:GetParent( ):GetParent( ):GetParent( ):GetName( )
	f = string.format( "%s%s", f, "View" )

	ArkInventory.Search.Frame_Table_Reset( f )
	
	local filter = _G[string.format( "%s%s", f, "SearchFilter" )]:GetText( )
	filter = ArkInventory.Search.CleanText( filter )
	--ArkInventory.Output( "filter = [", filter, "]" )
	
	--filter = string.gsub( filter, "-", "--" ) -- escape hyphens or they won't work right
	
	local newSearchTable = { }
	local c = 0
	if ArkInventorySearch_Stockpile.GlobalSearchCache then
		for id, itemData in pairs(ArkInventorySearch_Stockpile.GlobalSearchCache) do
			--if string.find( string.lower( itemData.name or "" ), string.lower( filter ) ) or filter == "" then
			if string.find( itemData.search_text, filter, nil, true ) or filter == "" then
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