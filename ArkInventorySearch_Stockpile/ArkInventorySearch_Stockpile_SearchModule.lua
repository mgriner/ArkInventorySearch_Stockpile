local _G = _G
local select = _G.select
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local type = _G.type
local error = _G.error
local table = _G.table

ArkInventorySearch_Stockpile.SearchModule = ArkInventorySearch_Stockpile:NewModule( "ArkInventorySearch_Stockpile" )

function ArkInventorySearch_Stockpile.SearchModule:OnEnable( )
	ArkInventory.Search.Frame_Hide( )
	ArkInventory:DisableModule( "ArkInventorySearch" )
	ArkInventory.Search.frame = ARKINV_Search_Stockpile
	ArkInventory.Search.rebuild = true
	ArkInventory.Search.SourceTable = { }
	ArkInventorySearch_Stockpile.SearchModule.cache = { }
	
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
	
	ArkInventorySearch_Stockpile.BuildGlobalSearchCache( )
end

function ArkInventorySearch_Stockpile.SearchModule:OnDisable( )
	ArkInventory.Search.Frame_Hide( )
	table.wipe( ArkInventory.Search.SourceTable )
	table.wipe( ArkInventorySearch_Stockpile.SearchModule.cache )
	
	ArkInventorySearch_Stockpile:UnhookAll( )
	
	ArkInventorySearch_Stockpile:UnregisterEvent( "PLAYER_ALIVE", "EVENT_WOW_PLAYER_ALIVE" )
	ArkInventorySearch_Stockpile:UnregisterEvent( "GET_ITEM_INFO_RECEIVED", "EVENT_WOW_GET_ITEM_INFO_RECEIVED" )
	ArkInventorySearch_Stockpile:UnregisterMessage( "EVENT_ARKINV_BUILD_GLOBAL_CACHE" )
	ArkInventorySearch_Stockpile.UnregisterSearchCacheEvents( )
	ArkInventorySearch_Stockpile:UnregisterAllBuckets( )
	
	table.wipe( ArkInventorySearch_Stockpile.GlobalSearchCache )
	table.wipe( ArkInventorySearch_Stockpile.GlobalSearchCacheIndexLookup )
	print("re-enabling old search")
	ArkInventory:EnableModule( "ArkInventorySearch" )
end

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
	
	local newSearchTable = { }
	local c = 0
	if ArkInventorySearch_Stockpile.GlobalSearchCache then
		for id, itemData in pairs(ArkInventorySearch_Stockpile.GlobalSearchCache) do
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