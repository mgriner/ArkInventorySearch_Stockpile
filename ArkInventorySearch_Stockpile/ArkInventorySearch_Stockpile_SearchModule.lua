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
	ArkInventory.Search.frame = StockpileFrame	--ARKINV_Search_Stockpile
	ArkInventory.Search.rebuild = true
	ArkInventory.Search.SourceTable = { }
	ArkInventorySearch_Stockpile.SearchModule.cache = { }
	
	-- registering global cache specific events
	ArkInventorySearch_Stockpile:RegisterEvent( "PLAYER_ALIVE", "EVENT_WOW_PLAYER_ALIVE" )
	ArkInventorySearch_Stockpile:RegisterEvent( "GET_ITEM_INFO_RECEIVED", "EVENT_WOW_GET_ITEM_INFO_RECEIVED" )
	ArkInventorySearch_Stockpile:RegisterMessage( "EVENT_ARKINV_BUILD_GLOBAL_CACHE" )
	ArkInventorySearch_Stockpile:RegisterBucketMessage( "EVENT_ARKINV_GET_ITEM_INFO_RECEIVED_BUCKET", 10)
	
	-- for auction UI
	ArkInventorySearch_Stockpile:RegisterMessage( "EVENT_STOCKPILE_CACHE_ITEM_LIST_UPDATE" )
	
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

function ArkInventorySearch_Stockpile.GetInventorySlotName(itemEquipLoc)
	local translation_table = {
		INVTYPE_AMMO = {""},
		INVTYPE_HEAD = {"HeadSlot"},
		INVTYPE_NECK = {"NeckSlot"},
		INVTYPE_SHOULDER = {"ShoulderSlot"},
		INVTYPE_BODY = {"ShirtSlot"},
		INVTYPE_CHEST = {"ChestSlot"},
		INVTYPE_ROBE = {"ChestSlot"},
		INVTYPE_WAIST = {"WaistSlot"},
		INVTYPE_LEGS = {"LegsSlot"},
		INVTYPE_FEET = {"FeetSlot"},
		INVTYPE_WRIST = {"WristSlot"},
		INVTYPE_HAND = {"HandsSlot"},
		INVTYPE_FINGER = {"Finger0Slot", "Finger1Slot"},
		INVTYPE_TRINKET = {"Trinket0Slot", "Trinket1Slot"},
		INVTYPE_CLOAK = {"BackSlot"},
		INVTYPE_WEAPON = {"MainHandSlot", "SecondaryHandSlot"},
		INVTYPE_SHIELD = {"SecondaryHandSlot"},
		INVTYPE_2HWEAPON = {"MainHandSlot"},
		INVTYPE_WEAPONMAINHAND = {"MainHandSlot"},
		INVTYPE_WEAPONOFFHAND = {"SecondaryHandSlot"},
		INVTYPE_HOLDABLE = {"SecondaryHandSlot"},
		INVTYPE_RANGED = {"MainHandSlot"},
		INVTYPE_THROWN = {"MainHandSlot"},
		INVTYPE_RANGEDRIGHT = {"MainHandSlot"},
		INVTYPE_RELIC = {"MainHandSlot"},
		INVTYPE_TABARD = {"TabardSlot"},
		INVTYPE_BAG = {"Bag0Slot", "Bag1Slot", "Bag2Slot", "Bag3Slot"},
		INVTYPE_QUIVER = {"Bag0Slot", "Bag1Slot", "Bag2Slot", "Bag3Slot"},
	}
	return translation_table[itemEquipLoc] or ""
end

function ArkInventorySearch_Stockpile.CleanText( text, exactMatch, escapeSpecial )
	if escapeSpecial then
		text = string.gsub(text, "%p", "%%%1")
	end
	if not exactMatch then
		text = string.lower(text)
	end
	if exactMatch and escapeSpecial and text ~= "" then
		text = "^" .. text .. "$"
	end
	return text
end

function ArkInventorySearch_Stockpile.QueryStockpileCacheItems( text, filterData, minLevel, maxLevel, minItemLevel, maxItemLevel, useable, rarity, exactMatch )
	
	text = ArkInventorySearch_Stockpile.CleanText( text, exactMatch, exactMatch )
	
	local newSearchTable = { }
	local c = 0
	local rarity_match = true
	local level_match_min = true
	local level_match_max = true
	local level_match = true
	local filter_match = true
	if ArkInventorySearch_Stockpile.GlobalSearchCache then
		for id, itemData in pairs(ArkInventorySearch_Stockpile.GlobalSearchCache) do
			
			rarity_match = true
			level_match_min = true
			level_match_max = true
			level_match = true
			
			item_level_match_min = true
			item_level_match_max = true
			item_level_match = true
			
			filter_match = true
		
			if not useable or ( itemData.canUse and useable ) then
				if itemData.q and rarity and ( not rarity[-1] ) and ( not rarity[itemData.q] ) then
					rarity_match = false
				else
					if itemData.ilvl and minItemLevel and minItemLevel > -2 and ( itemData.ilvl < minItemLevel ) then
						item_level_match_min = false;
					end
					
					if itemData.ilvl and maxItemLevel and maxItemLevel > -2 and itemData.ilvl > 0 and ( itemData.ilvl > maxItemLevel ) then
						item_level_match_max = false;
					end
					
					if item_level_match_min and item_level_match_max then
				
						if (itemData.uselevel and minLevel) and minLevel > -2 and ( itemData.uselevel < minLevel ) then
							level_match_min = false
						end
						
						if (itemData.uselevel and maxLevel) and maxLevel > -2 and itemData.uselevel > 0 and ( itemData.uselevel > maxLevel ) then
							level_match_max = false
						end
						
						level_match = level_match_min and level_match_max
						
						if itemData.ilvl and itemData.uselevel and itemData.name == "Husk of Naraxis" then
							print("ilvl: " .. itemData.ilvl)
							print("uselevel: " .. itemData.uselevel)
							print("minLevel: " .. minLevel)
							print("maxLevel: " .. maxLevel)
							print("min: " .. tostring(level_match_min))
							print("max: " .. tostring(level_match_max))
							print("< " .. tostring((itemData.uselevel < minLevel)))
						end
						
						
						if level_match then
						
							if filterData then
								filter_match = false
								
								for _, filter in pairs(filterData) do
									if itemData.itemtypeid == filter.classID then
										-- workaround because GetPetInfoBySpeciesID returns petType 1-9
										-- but GetAuctionItemSubClasses() returns subclass types 0-8
										if filter.classID == LE_ITEM_CLASS_BATTLEPET and itemData.itemsubtypeid == ( filter.subClassID + 1 ) then
											filter_match = true
										
										elseif filter.classID ~= LE_ITEM_CLASS_BATTLEPET and itemData.itemsubtypeid == filter.subClassID then
											if filter.inventoryType then
												local equiploc
												if itemData.equiploc and itemData.equiploc ~= "" then
													local invSlotNames = ArkInventorySearch_Stockpile.GetInventorySlotName(itemData.equiploc)
													for _, slot_name in pairs(invSlotNames) do
														slot_id = GetInventorySlotInfo( slot_name )
														if slot_id == filter.inventoryType then
															filter_match = true
														end
													end
													--equiploc = GetInventorySlotInfo( tostring(itemData.equiploc) )
													--print("!!!!!!!!!!!!!!-equiploc: " .. equiploc)
												end
												-- if filter.inventoryType == equiploc then
													-- filter_match = true
												-- end
											else
												filter_match = true
											end
										end
									end
								end
							end
						end
						
						local hasMatch = false
						
						if level_match and filter_match and text == "" then
							hasMatch = true
						elseif level_match and filter_match then
							local search_queries = { itemData.search_text, itemData.name, itemData.itemtype, itemData.itemsubtype }
							for _, query_text in pairs(search_queries) do
								query_text = ArkInventorySearch_Stockpile.CleanText( query_text, exactMatch)
								if string.find( query_text, text, nil, (not exactMatch) )  then
									hasMatch = true
									break
								end
							end
						end
						
						if hasMatch then
							c = c + 1
							newSearchTable[c] = itemData
						end
						-- if filter_match and ( string.find( searchable_text, text, nil, (not exactMatch) ) or text == "" ) then
							-- c = c + 1
							-- newSearchTable[c] = itemData
						-- end
					end
				end
			end
		end
	end
	ArkInventory.Search.SourceTable = newSearchTable
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_STOCKPILE_CACHE_ITEM_LIST_UPDATE")
	-- if #ArkInventory.Search.SourceTable > 0 then
		-- table.sort( ArkInventory.Search.SourceTable, function( a, b ) return a.sorted < b.sorted end )
	-- end
end

function ArkInventorySearch_Stockpile.FilterSelect( self, arg1, arg2, checked )
	if checked ~= nil then
		ArkInventorySearch_Stockpile.FilterValues[arg1.filter_name].checked = not checked
	end
	CloseDropDownMenus()
end

-- local filter_menu = {
	-- [1] = {
		-- item_type = {
			-- info = {
				-- text = "Item Type",
				-- hasArrow = true,
				-- notCheckable = true,
				-- value = "item_type",
				-- menuList = "item_type",
			-- },
		-- },
		-- item_slot = {
			-- info = {
				-- text = "Item Slot",
				-- hasArrow = true,
				-- notCheckable = true,
				-- value = "item_slot",
				-- menuList = "item_slot",
			-- },
		-- },
	-- },
	-- [2] = {
		-- item_type = {
			-- gear = {
				-- info = {
					-- text = "Gear",
					-- value = "item_type_gear",
					-- func = ArkInventorySearch_Stockpile.FilterSelect,
				-- },
			-- },
		-- },
		-- item_slot = {
			-- head_slot = {
				-- info = {
					-- text = "Head Slot",
					-- value = "item_slot_head",
					-- func = ArkInventorySearch_Stockpile.FilterSelect,
				-- },
			-- },
			-- neck_slot = {
				-- info = {
					-- text = "Neck Slot",
					-- value = "item_slot_neck",
					-- func = ArkInventorySearch_Stockpile.FilterSelect,
				-- },
			-- },
		-- },
	-- },
-- }

function table.val_to_str ( v )
  if "string" == type( v ) then
    v = string.gsub( v, "\n", "\\n" )
    if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type( v ) and table.tostring( v ) or
      tostring( v )
  end
end

function table.key_to_str ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str( k ) .. "]"
  end
end

function table.tostring( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
end

ArkInventorySearch_Stockpile.FilterValues = {
	item_type_gear = { checked = false, },
	item_slot_head = { checked = false, },
	item_slot_neck = { checked = false, },
}

function ArkInventorySearch_Stockpile.GetFilterValues( filter_name )
	return ArkInventorySearch_Stockpile.FilterValues[ filter_name ]
end

ArkInventorySearch_Stockpile.MenuList = {
    { text = "Select a Filter", isTitle = true},
    {
		text = "Item Type",
		hasArrow = true,
		notCheckable = true,
		menuList = {
			{
				text = "Gear",
				isNotRadio = true,
				arg1 = { filter_name = "item_type_gear", },
				func = ArkInventorySearch_Stockpile.FilterSelect,
			},
		},
	},
	{
		text = "Item Slot",
		hasArrow = true,
		notCheckable = true,
		menuList = {
			{
				text = "Head Slot",
				isNotRadio = true,
				arg1 = { filter_name = "item_slot_head", },
				func = ArkInventorySearch_Stockpile.FilterSelect,
			},
			{
				text = "Neck Slot",
				isNotRadio = true,
				arg1 = { filter_name = "item_slot_neck", },
				func = ArkInventorySearch_Stockpile.FilterSelect,
			},
		},
	},
}

function ArkInventorySearch_Stockpile.FilterDropDownMenu_OnLoad( frame, level, menuList )
	for index = 1, #menuList do
		local filter = menuList[index]
		if (filter.text) then
			filter.index = index;
			if (filter.arg1) then
				filter.checked = ArkInventorySearch_Stockpile.GetFilterValues( filter.arg1.filter_name ).checked
			end
			UIDropDownMenu_AddButton( filter, level );
		end
	end
end

-- function ArkInventorySearch_Stockpile.FilterDropDownMenu_OnLoad( frame, level, menuList )
	
	-- -- info            = { };
	-- -- info.text       = "This is an option in the menu.";
	-- -- info.value      = "OptionVariable";
	-- -- info.func       = FunctionCalledWhenOptionIsClicked 
			 -- -- can also be done as function() FunctionCalledWhenOptionIsClicked() end;

	-- -- Add the above information to the options menu as a button.
	-- -- UIDropDownMenu_AddButton(info);
	-- if level == 1 then
		-- for key, menu_option in pairs( filter_menu[1] ) do
			-- UIDropDownMenu_AddButton( menu_option.info, 1 )
		-- end
	-- elseif menuList then
		-- for key, sub_menu_option in pairs ( filter_menu[level][menuList] ) do
			-- UIDropDownMenu_AddButton( sub_menu_option.info, level )
		-- end
	-- end
-- end

function ArkInventorySearch_Stockpile.FilterDropDownButton_OnClick( frame )
	local filter_dropdown_menu, filter_dropdown_button
	if frame then
		print(frame:GetParent( ):GetName( ))
		print(frame:GetName())
		filter_dropdown_menu = frame:GetParent( )
		filter_dropdown_button = frame
	end
	ToggleDropDownMenu( 1, nil, filter_dropdown_menu, filter_dropdown_button, 0, 0, ArkInventorySearch_Stockpile.MenuList );
end