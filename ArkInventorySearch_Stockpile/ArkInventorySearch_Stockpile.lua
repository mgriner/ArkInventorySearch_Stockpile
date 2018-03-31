
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

ArkInventorySearch_Stockpile.Lib = { -- libraries live here
	
	Config = LibStub( "AceConfig-3.0" ),
	
}

ArkInventorySearch_Stockpile:SetDefaultModuleState(false)

-- ArkInventorySearch_Stockpile.GlobalSearchCache
-- holds all cached items for search
-- Each entry contains:
-- { id = object_id, sorted = object_info.name, name = object_info.name, h = object_info.h, q = object_info.q, t = object_info.texture, location_table = location_table }
-- location_table is a table of entries containing (player_id, location_id, bag_id) for every p,l,b that contains this item
-- GlobalSearchCache is indexed by the objectid which has the format CLASS:ID, e.g. item:44571 so you can access item info
-- for this object like so: GlobalSearchCache["item:44571"] which would return cached item info for Bottle of Silvermoon Port
-- including a location table which tells us every p,l,b where that item exists
ArkInventorySearch_Stockpile.GlobalSearchCache = { }
ArkInventorySearch_Stockpile.IsBuilding = false
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

function ArkInventorySearch_Stockpile.OnInitialize( )
	-- config menu (blizzard)
	ArkInventorySearch_Stockpile.ConfigBlizzard( )
	ArkInventorySearch_Stockpile.Lib.Config:RegisterOptionsTable( "ArkInventory_StockpileConfigBlizzard", ArkInventorySearch_Stockpile.Config.Blizzard )
	ArkInventory.Lib.Dialog:AddToBlizOptions( "ArkInventory_StockpileConfigBlizzard", "ArkInventorySearch_Stockpile" )
end

function ArkInventorySearch_Stockpile:OnEnable()
	ArkInventorySearch_Stockpile:EnableModule( "ArkInventorySearch_Stockpile" )
end

function ArkInventorySearch_Stockpile:OnDisable()	
	ArkInventorySearch_Stockpile:DisableModule( "ArkInventorySearch_Stockpile" )
end

function ArkInventorySearch_Stockpile.ConfigBlizzard( )
	ArkInventorySearch_Stockpile.Config = {
		Blizzard = {
			type = "group",
			childGroups = "tree",
			name = "ArkInventorySearch_Stockpile",
			args = {
				enabled = {
					order = 400,
					name = ArkInventory.Localise["ENABLED"],
					type = "toggle",
					get = function( info )
						return ArkInventorySearch_Stockpile:GetModule( "ArkInventorySearch_Stockpile" ):IsEnabled( )
					end,
					set = function( info, v )
						if v then
							ArkInventorySearch_Stockpile:EnableModule( "ArkInventorySearch_Stockpile" )
						else
							ArkInventorySearch_Stockpile:DisableModule( "ArkInventorySearch_Stockpile" )
						end
					end,
				},
			},
		},
	}
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