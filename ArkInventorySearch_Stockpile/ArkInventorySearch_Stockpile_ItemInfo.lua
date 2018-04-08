

function ArkInventorySearch_Stockpile.LookupItemType( class, itemtype_id )
	if class == "battlepet" and itemtype_id >= 1 then
		return GetItemSubClassInfo(LE_ITEM_CLASS_BATTLEPET, itemtype_id - 1);
	end
	for type_string, type_id in pairs( ArkInventory.Const.ItemClass ) do
		if itemtype_id == type_id then
			return type_string
		end
	end
	return itemtype_id
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
	info.invalidReasons = {} -- if info is invalid stores the source/cause
	info.isValid = true
	
	-- create location object
	info.location_object = { player_id = player_id, location_id = location_id, bag_id = bag_id }
	
	if info.h ~= sd.h then
		info.h = sd.h
	end
	
	-- if qualities don't match and info returns 1
	-- we most likely have the correct quality cached then, use sd
	if  sd.q ~= info.q and info.q == 1 then
		info.q = sd.q
	end
	
	if not info.q then info.q = 1 end
	
	-- reclassify battlepets
	if info.class == "battlepet" then
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
				
				if info.itemsubtypeid >= 1 then
					info.itemsubtype = GetItemSubClassInfo(LE_ITEM_CLASS_BATTLEPET, (info.itemsubtypeid - 1));
				end
			end
		end
	end
	
	-- reclassify currency and account mounts
	if info.class == "currency" then
		info.itemtypeid = LE_ITEM_CLASS_MISCELLANEOUS
		info.itemtype = "Currency"
		info.itemsubtypeid = LE_ITEM_MISCELLANEOUS_OTHER + 200
		info.itemsubtype = "Currency"
	elseif info.class == "spell" and location_id == ArkInventory.Const.Location.Mount then
		info.itemtype = "Account Mount"
		info.itemtypeid = LE_ITEM_CLASS_MISCELLANEOUS
		info.itemsubtypeid = LE_ITEM_MISCELLANEOUS_MOUNT + 10
		info.itemsubtype = "Account Mount"
	end
	
	-- move this h fix into our own getinfo function (similiar to ArkInventory.ObjectInfoArray)
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
		--info.isValid = false
		table.insert(info.invalidReasons, "bad_h1: " .. info.name .. " oldh: " .. oldh .. " h: " .. info.h)
	-- is a valid class:id pair, use it to build the rest of the link
	elseif not string.find(info.h, pattern_valid_link) and not string.find(info.h, pattern_valid_item_string) and string.find(info.h, pattern_valid_object_id) then
		local object_id = string.match(info.h, pattern_valid_object_id)
		local oldh = info.h
		local r, g, b, hex = GetItemQualityColor( info.q or 1 )
		info.h = "|c" .. hex .. "|H" .. info.h .. ":::::::::" .. "|h[" .. info.name .. "]|h|r"
		--info.isValid = false
		table.insert(info.invalidReasons, "bad_h2: " .. info.name .. " oldh: " .. oldh .. " h: " .. info.h)
	-- battlepet strings - can ignore
	elseif string.find(info.h, pattern_valid_battlepet_string) or string.find(info.h, pattern_valid_battlepet_string2) then
		-- battlepet string, do nothing
	-- no known itemstring format found...use for debugging
	elseif not string.find(info.h, pattern_valid_link) and not string.find(info.h, pattern_valid_item_string) and not string.find(info.h, pattern_valid_object_id) then
		table.insert(info.invalidReasons, "invalid_h: " .. string.gsub(info.h, "%|", "#"))
	end
	
	if not info.class or not info.id or info.class == "" or info.id == "" then
		print("missing ods")
		local osd = ArkInventory.ObjectStringDecode( info.h )
		info.class = osd.class
		info.id = info.osd.id
		print("class: " .. info.class)
		print("id:" .. info.id)
	end
		
	info.objectid = string.format( "%s:%s", info.class, info.id )

	-- if it is an item and it is missing name info we need to reload data
	if info.class == "item" and ( info.name == nil or info.name == "!---LOADING---!" or info.name == "" ) then
		info.name = "!---LOADING---!"
		info.isValid = false
		table.insert(info.invalidReasons, "missing_name")
		return info
	end
	
	-- TYPES AND SUBTYPES
	-- Handles invalid types and subtypes
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
		info.itemsubtypeid = info.info[13] or -2
	end

	
	if string.lower( info.itemtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
			info.itemtype = ArkInventorySearch_Stockpile.LookupItemType( info.class, info.itemtypeid )
	end
	
	if string.lower( info.itemsubtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
		info.itemsubtype = ArkInventorySearch_Stockpile.LookupItemType( info.class, info.itemsubtypeid )
	end
	
	if info.class == "item" and string.lower( info.itemtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
		info.isValid = false
		table.insert(info.invalidReasons, "missing_itemtype")
		return info
	end
	
	if info.class == "item" and string.lower( info.itemsubtype ) == string.lower( ArkInventory.Localise["UNKNOWN"] ) then
		info.isValid = false
		table.insert(info.invalidReasons, "missing_itemsubtype")
		return info
	end
	
	-- handles invalid ilvl and uselevel
	if info.class == "item" and info.ilvl == -2 then
		info.isValid = false
		table.insert(info.invalidReasons, "missing_ilvl")
		return info
	end
	
	if info.class == "item" and info.uselevel == -2 then
		info.isValid = false
		table.insert(info.invalidReasons, "missing_uselevel")
		return info
	end
	
	-- set the default text that is searchable
	info.search_text = ( info.name .. info.itemtype .. info.itemsubtype )
	
	-- reads an items tooltip info and stores the text for reference later
	-- also checks for any red text to see if the item is usable or not
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
		info.isValid = false
		table.insert(info.invalidReasons, "missing tooltip info")
		return info
	end
	
	local obj, txt1, txt2
	local r, g, b
	local color1, color2
	if num_lines > 0 then
		for i = 2, num_lines  do
			obj = _G[string.format( "%s%s%s", tooltip:GetName( ), "TextLeft", i )]
			if obj and obj:IsShown( ) then
				txt1 = obj:GetText( )
			end
			
			r, g, b = obj:GetTextColor( )
			color1 = string.format( "%02x%02x%02x", r * 255, g * 255, b * 255 )
			
			if color1 == "fe1f1f" or color1 == RED_FONT_COLOR_CODE then
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
			color2 = string.format( "%02x%02x%02x", r * 255, g * 255, b * 255 )
			
			if color2 == "fe1f1f" or color2 == RED_FONT_COLOR_CODE then
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
			txt = string.format( "%s #C%sC# #%s# #C%sC# #%s#", txt, color1, txt1 or "", color2, txt2 or "" )
		end
	end
	
	local is_usable = true
	
	if info.h and location_id then
		
		if location_id == ArkInventory.Const.Location.Pet or info.class == "battlepet" then
			
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
			trigger_text = tooltip_trigger_text
			is_usable = tooltip_canUse
		else
			trigger_text = tooltip_trigger_text
			is_usable = tooltip_canUse
		end
	else
		txt = txt .. "CAN_USE_ERROR: missing h or location"
	end
	
	info.canUse = is_usable
	info.tooltip_text = txt .. trigger_text
	
	return info
	
end
