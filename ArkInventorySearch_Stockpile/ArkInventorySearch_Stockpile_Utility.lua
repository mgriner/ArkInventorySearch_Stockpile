local item_statistics = {
	item_types = { }
}

ArkInventorySearch_Stockpile:RegisterChatCommand("stockpile_print_stats", "PrintItemStatistics")

function ArkInventorySearch_Stockpile:PrintItemStatistics( )
	
	-- just reallocate vs table.wipe?
	-- want to look into this but people said
	-- just let lua GC take care of it, table.wipe is more
	-- expensive then just making a new table
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
	if StockpileFrame and not ArkInventorySearch_Stockpile.IsBuilding then
		print("refreshing table...")
		ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search();
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
	for objectid, objectinfo in pairs( ArkInventorySearch_Stockpile.ItemLoadingPool ) do
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