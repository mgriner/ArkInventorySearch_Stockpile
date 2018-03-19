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
	ArkInventory.Search.frame = ARKINV_Search_Stockpile
	ArkInventory.Search.rebuild = true
	ArkInventory.Search.SourceTable = { }
	ArkInventorySearch_Stockpile.SearchModule.cache = { }
end

function ArkInventorySearch_Stockpile.SearchModule:OnDisable( )
	ArkInventory.Search.Frame_Hide( )
	table.wipe( ArkInventory.Search.SourceTable )
	table.wipe( ArkInventorySearch_Stockpile.SearchModule.cache )
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