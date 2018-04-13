
local BROWSE_PARAM_INDEX_PAGE = 9;
local BROWSE_PARAM_RARITY_TABLE = 11;

UIPanelWindows["StockpileFrame"] = { area = "doublewide", pushable = 0, width = 840 };

local StockpileCurrentSort = { list = { existingSortColumn = "name", existingSortReverse = false }, }
StockpileBrowseRarityFilters = {}
local SelectedStockpileItem = nil;

function ArkInventorySearch_Stockpile.StockpileFrame_OnLoad (self)
	
	self:RegisterForDrag("LeftButton");
	
	-- Tab Handling code
	PanelTemplates_SetNumTabs(self, 1);
	PanelTemplates_SetTab(self, 1);

	StockpileBrowseFilterScrollFrame.ScrollBar.scrollStep = BROWSE_FILTER_HEIGHT;
	
	-- Init search dot count
	StockpileFrameBrowse.dotCount = 0;
	StockpileFrameBrowse.isSearchingThrottle = 0;
	
	-- Init status dot count
	StockpileCacheStatus.dotCount = 0;
	StockpileCacheStatus.isSearchingThrottle = 0;

	StockpileFrameBrowse.page = 0;
	FauxScrollFrame_SetOffset(StockpileBrowseScrollFrame,0);
	
	MoneyFrame_SetMaxDisplayWidth(StockpileFrameMoneyFrame, 160);
	
	-- Init rarity filters
	ArkInventorySearch_Stockpile.Stockpile_PopulateRarity()
	
end

function ArkInventorySearch_Stockpile.StockpileFrame_OnShow (self)
	ArkInventorySearch_Stockpile.StockpileFrameTab_OnClick(StockpileFrameTab1);
	SetPortraitTexture(StockpilePortraitTexture, "player");
	StockpileBrowseNoResultsText:SetText(BROWSE_SEARCH_TEXT);
	PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN);

	SetUpSideDressUpFrame(self, 840, 1020, "TOPLEFT", "TOPRIGHT", -2, -28);
end

function ArkInventorySearch_Stockpile.StockpileFrameTab_OnClick(self, button, down, index)
	local index = self:GetID();
	PanelTemplates_SetTab(StockpileFrame, index);
	StockpileFrameBrowse:Hide();
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
	if ( index == 1 ) then
		-- Browse tab
		StockpileFrameTopLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft");
		StockpileFrameTop:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Top");
		StockpileFrameTopRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopRight");
		StockpileFrameBotLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotLeft");
		StockpileFrameBot:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Auction-Bot");
		StockpileFrameBotRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotRight");
		StockpileFrameBrowse:Show();
		StockpileFrame.type = "list";
	end
end

-- Browse tab functions

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_OnLoad(self)
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE");

	-- set default sort
	--ArkInventorySearch_Stockpile.StockpileFrame_SetSort("list", "quality", false);
	ArkInventorySearch_Stockpile.StockpileFrame_SetSort("list", "name", false);
end

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_OnShow()
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Update();
	ArkInventorySearch_Stockpile.StockpileFrameFilters_Update();
end

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_UpdateArrows()
	ArkInventorySearch_Stockpile.SortButton_UpdateArrow(StockpileBrowseNameSort, "list", "name");
	ArkInventorySearch_Stockpile.SortButton_UpdateArrow(StockpileBrowseNameSort, "list", "quality");
	ArkInventorySearch_Stockpile.SortButton_UpdateArrow(StockpileBrowseLevelSort, "list", "level");
	ArkInventorySearch_Stockpile.SortButton_UpdateArrow(StockpileBrowseItemLevelSort, "list", "itemLevel");
	ArkInventorySearch_Stockpile.SortButton_UpdateArrow(StockpileBrowseItemTypeColumnSort, "list", "itemType");
	ArkInventorySearch_Stockpile.SortButton_UpdateArrow(StockpileBrowseItemSubtypeSort, "list", "itemSubtype");
end

function ArkInventorySearch_Stockpile:EVENT_STOCKPILE_SEARCH_TABLE_UPDATED( )
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Update();
	-- Stop "searching" messaging
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_isSearching = nil;
	StockpileBrowseNoResultsText:SetText(BROWSE_NO_RESULTS);
	-- update arrows now that we're not searching
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_UpdateArrows();
end

function ArkInventorySearch_Stockpile.GetSearchTableItemLink( index )
	return ArkInventorySearch_Stockpile.SearchResultsTable[index].h or ""
end

function ArkInventorySearch_Stockpile.StockpileBrowseButton_OnClick(button)
	assert(button);
	
	if ( GetCVarBool("auctionDisplayOnCharacter") ) then
		if ( not DressUpItemLink(ArkInventorySearch_Stockpile.GetSearchTableItemLink(button:GetID() + FauxScrollFrame_GetOffset(StockpileBrowseScrollFrame))) ) then
			ArkInventorySearch_Stockpile.DressUpBattlePetLink(ArkInventorySearch_Stockpile.GetSearchTableItemLink(button:GetID() + FauxScrollFrame_GetOffset(StockpileBrowseScrollFrame)));
		end
	end
	
	ArkInventorySearch_Stockpile.SetSelectedStockpileItem(button:GetID() + FauxScrollFrame_GetOffset(StockpileBrowseScrollFrame))
	button:LockHighlight();

	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Update();
end

function ArkInventorySearch_Stockpile.DressUpBattlePetLink(link)
	if( link ) then 
		print(string.gsub(link, "%|", "#"))
		local _, _, _, linkType, speciesIDString = strsplit(":|H", link);
		local _, _, _, creatureID, _, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(tonumber(speciesIDString))
		if ( linkType == "battlepet" ) then
			return DressUpBattlePet(creatureID, displayID);
		end
	end
	return false
end

function ArkInventorySearch_Stockpile.SetSelectedStockpileItem(item_number)
	if item_number ~= SelectedStockpileItem then
		SelectedStockpileItem = item_number;
	else
		SelectedStockpileItem = nil;
	end
end

function ArkInventorySearch_Stockpile.GetSelectedStockpileItem()
	return SelectedStockpileItem;
end

function ArkInventorySearch_Stockpile.StockpileBrowseDropDown_OnLoad(self)
	UIDropDownMenu_Initialize(self, ArkInventorySearch_Stockpile.StockpileBrowseDropDown_Initialize);
	--UIDropDownMenu_SetSelectedValue(StockpileBrowseDropDown,-1);
	UIDropDownMenu_SetText(self, RARITY)
end

function ArkInventorySearch_Stockpile.Stockpile_PopulateRarity()
	StockpileBrowseRarityFilters[-1] = true;
	for i=0, getn(ITEM_QUALITY_COLORS)  do
		StockpileBrowseRarityFilters[i] = true;
	end
end

function ArkInventorySearch_Stockpile.StockpileBrowseDropDown_Initialize()
	local info = UIDropDownMenu_CreateInfo();
	info.text = ALL;
	info.colorCode = "|cffffd100";
	info.value = -1;
	info.func = ArkInventorySearch_Stockpile.StockpileBrowseDropDown_OnClick;
	info.checked = StockpileBrowseRarityFilters[-1];
	info.keepShownOnClick = true;
	UIDropDownMenu_AddButton(info);
	for i=0, getn(ITEM_QUALITY_COLORS)  do
		local _, _, _, colorCode = GetItemQualityColor(i);
		info.text = _G["ITEM_QUALITY"..i.."_DESC"];
		info.colorCode = "|c" .. colorCode;
		info.value = i;
		info.func = ArkInventorySearch_Stockpile.StockpileBrowseDropDown_OnClick;
		info.checked = StockpileBrowseRarityFilters[i];
		info.isNotRadio = true;
		info.keepShownOnClick = true;
		UIDropDownMenu_AddButton(info);
	end
end

function ArkInventorySearch_Stockpile.StockpileBrowseDropDown_OnClick(self, arg1, arg2, checked)
	StockpileBrowseRarityFilters[self.value] = not StockpileBrowseRarityFilters[self.value]

	if self.value == -1 then
		ArkInventorySearch_Stockpile.StockpileBrowseDropDownToggleAll( StockpileBrowseRarityFilters[self.value] )
	elseif StockpileBrowseRarityFilters[-1] then
		StockpileBrowseRarityFilters[-1] = false
	else
		local allChecked = true
		for index, isChecked in pairs( StockpileBrowseRarityFilters ) do
			if index >= 0 and not isChecked then
				allChecked = false
			end
		end
		if allChecked then
			StockpileBrowseRarityFilters[-1] = true
		end
	end
	-- toggle menu off then on otherwise checkboxes won't update
	ToggleDropDownMenu(1, nil, StockpileBrowseDropDown)
	ToggleDropDownMenu(1, nil, StockpileBrowseDropDown)
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search()
end

function ArkInventorySearch_Stockpile.StockpileBrowseDropDownToggleAll( allChecked )
	for index, isChecked in pairs( StockpileBrowseRarityFilters ) do
		StockpileBrowseRarityFilters[index] = allChecked
	end
end

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_Reset(self)
	StockpileBrowseName:SetText("");
	StockpileBrowseMinLevel:SetText("");
	StockpileBrowseMaxLevel:SetText("");
	StockpileBrowseMinItemLevel:SetText("");
	StockpileBrowseMaxItemLevel:SetText("");
	StockpileIsUsableCheckButton:SetChecked(false);
	StockpileExactMatchCheckButton:SetChecked(false);
	
	ArkInventorySearch_Stockpile.Stockpile_PopulateRarity();
	
	StockpileBrowseNoResultsText:Show();
	StockpileBrowseNameSort:Show();
	StockpileBrowseLevelSort:Show();
	StockpileBrowseItemLevelSort:Show();
	StockpileBrowseItemTypeColumnSort:Show();
	StockpileBrowseItemSubtypeSort:Show();

	-- reset the filters
	OPEN_FILTER_LIST = {};
	StockpileFrameBrowse.selectedCategoryIndex = nil;
	StockpileFrameBrowse.selectedSubCategoryIndex = nil;
	StockpileFrameBrowse.selectedSubSubCategoryIndex = nil;

	StockpileBrowseLevelSort:SetText(ArkInventorySearch_Stockpile.GetDetailColumnString(StockpileFrameBrowse.selectedCategoryIndex, StockpileFrameBrowse.selectedSubCategoryIndex));
	ArkInventorySearch_Stockpile.StockpileFrameFilters_Update();

	self:Disable();
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search();
end

function ArkInventorySearch_Stockpile.StockpileBrowseResetButton_OnUpdate(self, elapsed)
	if ( (StockpileBrowseName:GetText() == "") and (StockpileBrowseMinLevel:GetText() == "") and (StockpileBrowseMaxLevel:GetText() == "") and
		 (StockpileBrowseMinItemLevel:GetText() == "") and (StockpileBrowseMaxItemLevel:GetText() == "") and
	     (not StockpileIsUsableCheckButton:GetChecked()) and (not StockpileExactMatchCheckButton:GetChecked()) and (StockpileBrowseRarityFilters[-1]) and
	     (not StockpileFrameBrowse.selectedCategoryIndex) and (not StockpileFrameBrowse.selectedSubCategoryIndex) and (not StockpileFrameBrowse.selectedSubSubCategoryIndex) )
	then
		self:Disable();
	else
		self:Enable();
	end
end

function ArkInventorySearch_Stockpile.StockpileFrame_SortStockpileDoSort(sortTable, sortColumn, sortOptions)
	if not ArkInventorySearch_Stockpile.SearchResultsTable then
		return
	end
	if sortTable == "list" then
		table.sort( ArkInventorySearch_Stockpile.SearchResultsTable, function(a, b)
			for _, sortRow in pairs( sortOptions ) do
				-- default a-z sort when not explicitly sorting by name
				if sortColumn ~= "name" and sortRow.column == "name" then
					if a[sortRow.column] < b[sortRow.column] then
						return true;
					end
				else
					if a[sortRow.column] > b[sortRow.column] then
						return sortRow.reverse;
					end
					if a[sortRow.column] < b[sortRow.column] then
						return not sortRow.reverse;
					end
				end
			end
		end);
	end
end

function ArkInventorySearch_Stockpile.StockpileFrame_SetSort(sortTable, sortColumn, oppositeOrder)

	ArkInventorySearch_Stockpile.StockpileFrame_SetCurrentSort(sortTable, sortColumn, oppositeOrder)
	local sortOptions = {};
	local sortRow = {};
	-- set the columns
	for index, row in pairs(ArkInventorySearch_Stockpile.StockpileSort[sortTable.."_"..sortColumn]) do
		sortRow = {};
		sortRow.column = row.column;
		if (oppositeOrder) then
			sortRow.reverse = not row.reverse;
			--ArkInventorySearch_Stockpile.StockpileFrame_SortStockpileDoSort(sortTable, row.column, not row.reverse);
		else
			sortRow.reverse = row.reverse;
			--ArkInventorySearch_Stockpile.StockpileFrame_SortStockpileDoSort(sortTable, row.column, row.reverse);
		end
		table.insert(sortOptions, sortRow);
	end
	ArkInventorySearch_Stockpile.StockpileFrame_SortStockpileDoSort(sortTable, sortColumn, sortOptions);
	ArkInventorySearch_Stockpile:SendMessage( "EVENT_STOCKPILE_SEARCH_TABLE_UPDATED")
end

function ArkInventorySearch_Stockpile.StockpileFrame_GetStockpileSort(sortTable)
	if sortTable == "list" then
		return StockpileCurrentSort[sortTable].existingSortColumn, StockpileCurrentSort[sortTable].existingSortReverse;
	end
end

function ArkInventorySearch_Stockpile.StockpileFrame_SetCurrentSort(sortTable, sortColumn, sortReverse)
	StockpileCurrentSort[sortTable].existingSortColumn = sortColumn
	StockpileCurrentSort[sortTable].existingSortReverse = sortReverse
end

function ArkInventorySearch_Stockpile.StockpileFrame_OnClickSortColumn(sortTable, sortColumn)
	-- change the sort as appropriate
	--local existingSortColumn, existingSortReverse = GetAuctionSort(sortTable, 1);
	local existingSortColumn, existingSortReverse = ArkInventorySearch_Stockpile.StockpileFrame_GetStockpileSort(sortTable);
	local oppositeOrder = false;
	if (existingSortColumn and (existingSortColumn == sortColumn)) then
		oppositeOrder = not existingSortReverse;
	-- elseif (sortColumn == "level") then
		-- oppositeOrder = true;
	end
	-- set the new sort order
	ArkInventorySearch_Stockpile.StockpileFrame_SetSort(sortTable, sortColumn, oppositeOrder);

	-- apply the sort
	if (sortTable == "list") then
		ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search();
	end
end

local prevBrowseParams;
local function StockpileFrameBrowse_SearchHelper(...)
	local text, minLevel, maxLevel, minItemLevel, maxItemLevel, categoryIndex, subCategoryIndex, subSubCategoryIndex, page, useable, rarity, exactMatch = ...;
	
	-- editbox returns 0 if empty
	-- convert to -2 because 0 is a valid level
	-- using -2 we can know whether or not there is no editbox entry
	if minLevel == 0 then minLevel = -2 end;
	if maxLevel == 0 then maxLevel = -2 end;
	if minItemLevel == 0 then minItemLevel = -2 end;
	if maxItemLevel == 0 then maxItemLevel = -2 end;
	
	local filterData;
	if categoryIndex and subCategoryIndex and subSubCategoryIndex then
		filterData = ArkInventorySearch_Stockpile.StockpileCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters;
	elseif categoryIndex and subCategoryIndex then
		filterData = ArkInventorySearch_Stockpile.StockpileCategories[categoryIndex].subCategories[subCategoryIndex].filters;
	elseif categoryIndex then
		filterData = ArkInventorySearch_Stockpile.StockpileCategories[categoryIndex].filters;
	else
		-- not filtering by category, leave nil for all
	end
	
	local should_update = ArkInventorySearch_Stockpile.IsGlobalSearchCacheModified
	local should_filter = ArkInventorySearch_Stockpile.IsGlobalSearchCacheModified
	if ( not prevBrowseParams ) then
		-- if we are doing a search for the first time then create the browse param cache
		prevBrowseParams = { };
		should_update = true
		should_filter = true
	else
		-- if we have already done a browse then see if any of the params have changed (except for the page number)
		local param;
		for i = 1, select('#', ...) do
			if ( i == BROWSE_PARAM_RARITY_TABLE ) then
				-- see if there was a change to rarity filters
				for index, isChecked in pairs( select(i, ...) ) do
					if isChecked ~= prevBrowseParams[i][index] then
						should_update = true
						should_filter = true
						break
					end
				end
			elseif ( i ~= BROWSE_PARAM_INDEX_PAGE and select(i, ...) ~= prevBrowseParams[i] ) then
				-- if we detect a change then we want to reset the page number back to the first page
				page = 0;
				StockpileFrameBrowse.page = page;
				should_update = true
				should_filter = true
				break;
			end
		end
	end
	
	if should_update or should_filter then
		-- Start "searching" messaging
		ArkInventorySearch_Stockpile.StockpileFrameBrowse_isSearching = 1;
	end
	
	if should_update then
		-- we only need to update the data if there was a change
		ArkInventorySearch_Stockpile.QueryStockpileCacheItems( text, filterData, minLevel, maxLevel, minItemLevel, maxItemLevel, useable, rarity, exactMatch );
	end
	
	if should_filter then
		local sortTable = "list"
		local sortColumn = StockpileCurrentSort[sortTable].existingSortColumn
		local sortReverse = StockpileCurrentSort[sortTable].existingSortReverse
		ArkInventorySearch_Stockpile.StockpileFrame_SetSort( sortTable, sortColumn, sortReverse )
	end

	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Update()
	
	-- store this query's params so we can compare them with the next set of params we get
	for i = 1, select('#', ...) do
		if ( i == BROWSE_PARAM_INDEX_PAGE ) then
			prevBrowseParams[i] = page;
		elseif ( i == BROWSE_PARAM_RARITY_TABLE ) then
			if not prevBrowseParams[i] then
				prevBrowseParams[i] = {};
			else
				table.wipe(prevBrowseParams[i]);
			end
			for index, isChecked in pairs( select(i, ...) ) do
				prevBrowseParams[i][index] = isChecked;
			end
		else
			prevBrowseParams[i] = select(i, ...);
		end
	end
	-- reset update flag
	ArkInventorySearch_Stockpile.IsGlobalSearchCacheModified = false;
end

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search()
	if ( not StockpileFrameBrowse.page ) then
		StockpileFrameBrowse.page = 0;
	end
	
	StockpileFrameBrowse_SearchHelper(StockpileBrowseName:GetText(), StockpileBrowseMinLevel:GetNumber(), StockpileBrowseMaxLevel:GetNumber(), StockpileBrowseMinItemLevel:GetNumber(), StockpileBrowseMaxItemLevel:GetNumber(), StockpileFrameBrowse.selectedCategoryIndex, StockpileFrameBrowse.selectedSubCategoryIndex, StockpileFrameBrowse.selectedSubSubCategoryIndex, StockpileFrameBrowse.page, StockpileIsUsableCheckButton:GetChecked(), StockpileBrowseRarityFilters, StockpileExactMatchCheckButton:GetChecked());
end

function StockpileCacheStatusFrame_OnUpdate(self, elapsed)
	if (ArkInventorySearch_Stockpile.IsItemLoading) or (ArkInventorySearch_Stockpile.IsBuilding) then
		if ( StockpileCacheStatus.isSearchingThrottle <= 0 ) then
			StockpileCacheStatus.dotCount = StockpileCacheStatus.dotCount + 1;
			if ( StockpileCacheStatus.dotCount > 3 ) then
				StockpileCacheStatus.dotCount = 0
			end
			local dotString = "";
			for i=1, StockpileCacheStatus.dotCount do
				dotString = dotString..".";
			end
			
			StockpileBrowseStatusDotsText:Show();
			StockpileBrowseStatusDotsText:SetText(dotString);
			StockpileBrowseStatusText:Show();
			
			StockpileCacheStatus.isSearchingThrottle = 0.3;
		else
			StockpileCacheStatus.isSearchingThrottle = StockpileCacheStatus.isSearchingThrottle - elapsed;
		end
	else
		StockpileBrowseStatusDotsText:Hide();
		StockpileBrowseStatusText:Hide();
	end
end

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search()
	if ( not StockpileFrameBrowse.page ) then
		StockpileFrameBrowse.page = 0;
	end
	
	StockpileFrameBrowse_SearchHelper(StockpileBrowseName:GetText(), StockpileBrowseMinLevel:GetNumber(), StockpileBrowseMaxLevel:GetNumber(), StockpileBrowseMinItemLevel:GetNumber(), StockpileBrowseMaxItemLevel:GetNumber(), StockpileFrameBrowse.selectedCategoryIndex, StockpileFrameBrowse.selectedSubCategoryIndex, StockpileFrameBrowse.selectedSubSubCategoryIndex, StockpileFrameBrowse.page, StockpileIsUsableCheckButton:GetChecked(), StockpileBrowseRarityFilters, StockpileExactMatchCheckButton:GetChecked());
end

function StockpileBrowseSearchButton_OnUpdate(self, elapsed)
	if ArkInventorySearch_Stockpile.StockpileFrameBrowse_isSearching then
		if ( StockpileFrameBrowse.isSearchingThrottle <= 0 ) then
			StockpileFrameBrowse.dotCount = StockpileFrameBrowse.dotCount + 1;
			if ( StockpileFrameBrowse.dotCount > 3 ) then
				StockpileFrameBrowse.dotCount = 0
			end
			local dotString = "";
			for i=1, StockpileFrameBrowse.dotCount do
				dotString = dotString..".";
			end
			StockpileBrowseSearchDotsText:Show();
			StockpileBrowseSearchDotsText:SetText(dotString);
			
			StockpileBrowseNoResultsText:SetText(SEARCHING_FOR_ITEMS);
			StockpileFrameBrowse.isSearchingThrottle = 0.3;
		else
			StockpileFrameBrowse.isSearchingThrottle = StockpileFrameBrowse.isSearchingThrottle - elapsed;
		end
	else
		StockpileBrowseSearchDotsText:Hide();
	end
end

function ArkInventorySearch_Stockpile.StockpileFrameFilters_Update(forceSelectionIntoView)
	ArkInventorySearch_Stockpile.StockpileFrameFilters_UpdateCategories(forceSelectionIntoView);
	-- Update scrollFrame
	FauxScrollFrame_Update(StockpileBrowseFilterScrollFrame, #OPEN_FILTER_LIST, NUM_FILTERS_TO_DISPLAY, BROWSE_FILTER_HEIGHT);
end

function ArkInventorySearch_Stockpile.StockpileFrameFilters_UpdateCategories(forceSelectionIntoView)
	-- Initialize the list of open filters
	OPEN_FILTER_LIST = {};

	for categoryIndex, categoryInfo in ipairs(ArkInventorySearch_Stockpile.StockpileCategories) do
		local selected = StockpileFrameBrowse.selectedCategoryIndex and StockpileFrameBrowse.selectedCategoryIndex == categoryIndex;

		tinsert(OPEN_FILTER_LIST, { name = categoryInfo.name, type = "category", categoryIndex = categoryIndex, selected = selected, });

		if ( selected ) then
			ArkInventorySearch_Stockpile.StockpileFrameFilters_AddSubCategories(categoryInfo.subCategories);
		end
	end
	
	-- Display the list of open filters
	local offset = FauxScrollFrame_GetOffset(StockpileBrowseFilterScrollFrame);
	if ( forceSelectionIntoView and StockpileFrameBrowse.selectedCategoryIndex and ( not StockpileFrameBrowse.selectedSubCategoryIndex and not StockpileFrameBrowse.selectedSubSubCategoryIndex ) ) then
		if ( StockpileFrameBrowse.selectedCategoryIndex <= offset ) then
			FauxScrollFrame_OnVerticalScroll(StockpileBrowseFilterScrollFrame, math.max(0.0, (StockpileFrameBrowse.selectedCategoryIndex - 1) * BROWSE_FILTER_HEIGHT), BROWSE_FILTER_HEIGHT);
			offset = FauxScrollFrame_GetOffset(StockpileBrowseFilterScrollFrame);
		end
	end
	
	local dataIndex = offset;

	local hasScrollBar = #OPEN_FILTER_LIST > NUM_FILTERS_TO_DISPLAY;
	for i = 1, NUM_FILTERS_TO_DISPLAY do
		local button = StockpileFrameBrowse.StockpileFilterButtons[i];
		button:SetWidth(hasScrollBar and 136 or 156);

		dataIndex = dataIndex + 1;

		if ( dataIndex <= #OPEN_FILTER_LIST ) then
			local info = OPEN_FILTER_LIST[dataIndex];

			if ( info ) then
				ArkInventorySearch_Stockpile.StockpileFilterButton_SetUp(button, info);
				
				if ( info.type == "category" ) then
					button.categoryIndex = info.categoryIndex;
				elseif ( info.type == "subCategory" ) then
					button.subCategoryIndex = info.subCategoryIndex;
				elseif ( info.type == "subSubCategory" ) then
					button.subSubCategoryIndex = info.subSubCategoryIndex;
				end
				
				if ( info.selected ) then
					button:LockHighlight();
				else
					button:UnlockHighlight();
				end
				button:Show();
			end
		else
			button:Hide();
		end
	end
end

function ArkInventorySearch_Stockpile.StockpileFrameFilters_AddSubCategories(subCategories)
	if subCategories then
		for subCategoryIndex, subCategoryInfo in ipairs(subCategories) do
			local selected = StockpileFrameBrowse.selectedSubCategoryIndex and StockpileFrameBrowse.selectedSubCategoryIndex == subCategoryIndex;

			tinsert(OPEN_FILTER_LIST, { name = subCategoryInfo.name, type = "subCategory", subCategoryIndex = subCategoryIndex, selected = selected });
		 
			if ( selected ) then
				ArkInventorySearch_Stockpile.StockpileFrameFilters_AddSubSubCategories(subCategoryInfo.subCategories);
			end
		end
	end
end

function ArkInventorySearch_Stockpile.StockpileFrameFilters_AddSubSubCategories(subSubCategories)
	if subSubCategories then
		for subSubCategoryIndex, subSubCategoryInfo in ipairs(subSubCategories) do
			local selected = StockpileFrameBrowse.selectedSubSubCategoryIndex and StockpileFrameBrowse.selectedSubSubCategoryIndex == subSubCategoryIndex;
			local isLast = subSubCategoryIndex == #subSubCategories;

			tinsert(OPEN_FILTER_LIST, { name = subSubCategoryInfo.name, type = "subSubCategory", subSubCategoryIndex = subSubCategoryIndex, selected = selected, isLast = isLast});
		end
	end
end

function ArkInventorySearch_Stockpile.StockpileFilterButton_SetUp(button, info)
	local normalText = _G[button:GetName().."NormalText"];
	local normalTexture = _G[button:GetName().."NormalTexture"];
	local line = _G[button:GetName().."Lines"];
	local tex = button:GetNormalTexture();
	tex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg");
	tex:SetTexCoord(0, 0.53125, 0, 0.625);

	if ( info.type == "category" ) then
		button:SetNormalFontObject(GameFontNormalSmallLeft);
		button:SetText(info.name);
		normalText:SetPoint("LEFT", button, "LEFT", 4, 0);
		normalTexture:SetAlpha(1.0);	
		line:Hide();
	elseif ( info.type == "subCategory" ) then
		button:SetNormalFontObject(GameFontHighlightSmallLeft);
		button:SetText(info.name);
		normalText:SetPoint("LEFT", button, "LEFT", 12, 0);
		normalTexture:SetAlpha(0.4);
		line:Hide();
	elseif ( info.type == "subSubCategory" ) then
		button:SetNormalFontObject(GameFontHighlightSmallLeft);
		button:SetText(info.name);
		normalText:SetPoint("LEFT", button, "LEFT", 20, 0);
		normalTexture:SetAlpha(0.0);	
		
		if ( info.isLast ) then
			line:SetTexCoord(0.4375, 0.875, 0, 0.625);
		else
			line:SetTexCoord(0, 0.4375, 0, 0.625);
		end
		line:Show();
	end
	button.type = info.type; 
end

function ArkInventorySearch_Stockpile.StockpileFrameFilter_OnClick(self, button)
	if ( self.type == "category" ) then
		if ( StockpileFrameBrowse.selectedCategoryIndex == self.categoryIndex ) then
			StockpileFrameBrowse.selectedCategoryIndex = nil;
		else
			StockpileFrameBrowse.selectedCategoryIndex = self.categoryIndex;
		end
		StockpileFrameBrowse.selectedSubCategoryIndex = nil;
		StockpileFrameBrowse.selectedSubSubCategoryIndex = nil;
		
		StockpileBrowseNameSort:Show();
		StockpileBrowseLevelSort:Show();
		StockpileBrowseItemLevelSort:Show();
		StockpileBrowseItemTypeColumnSort:Show();
		StockpileBrowseItemSubtypeSort:Show();
	elseif ( self.type == "subCategory" ) then
		if ( StockpileFrameBrowse.selectedSubCategoryIndex == self.subCategoryIndex ) then
			StockpileFrameBrowse.selectedSubCategoryIndex = nil;
			StockpileFrameBrowse.selectedSubSubCategoryIndex = nil;
		else
			StockpileFrameBrowse.selectedSubCategoryIndex = self.subCategoryIndex;
			StockpileFrameBrowse.selectedSubSubCategoryIndex = nil;
		end
	elseif ( self.type == "subSubCategory" ) then
		if ( StockpileFrameBrowse.selectedSubSubCategoryIndex == self.subSubCategoryIndex ) then
			StockpileFrameBrowse.selectedSubSubCategoryIndex = nil;
		else
			StockpileFrameBrowse.selectedSubSubCategoryIndex = self.subSubCategoryIndex
		end
	end
	StockpileBrowseLevelSort:SetText(ArkInventorySearch_Stockpile.GetDetailColumnString(StockpileFrameBrowse.selectedCategoryIndex, StockpileFrameBrowse.selectedSubCategoryIndex));
	ArkInventorySearch_Stockpile.StockpileFrameFilters_Update(true)
	ArkInventorySearch_Stockpile.StockpileFrameBrowse_Search()
end

function ArkInventorySearch_Stockpile.StockpileFrameBrowse_Update()
		local numBatchAuctions, totalAuctions;
		local button, buttonName, buttonHighlight, iconTexture, itemName, color, itemCount;
		local offset = FauxScrollFrame_GetOffset(StockpileBrowseScrollFrame);
		local index;
		local isLastSlotEmpty;
		local name, texture, count, quality, canUse, level, itemId;

		-- Update sort arrows
		ArkInventorySearch_Stockpile.StockpileFrameBrowse_UpdateArrows();

		numBatchAuctions = #ArkInventorySearch_Stockpile.SearchResultsTable
		totalAuctions = #ArkInventorySearch_Stockpile.SearchResultsTable

		-- Show the no results text if no items found
		if ( numBatchAuctions == 0 ) then
			StockpileBrowseNoResultsText:Show();
		else
			StockpileBrowseNoResultsText:Hide();
		end
		
		for i=1, NUM_BROWSE_TO_DISPLAY do
			local item_info
			index = offset + i + (NUM_AUCTION_ITEMS_PER_PAGE * StockpileFrameBrowse.page);
			
			button = _G["StockpileBrowseButton"..i];
			local shouldHide = index > (numBatchAuctions + (NUM_AUCTION_ITEMS_PER_PAGE * StockpileFrameBrowse.page));
			if ( not shouldHide ) then
				item_info =  ArkInventorySearch_Stockpile.SearchResultsTable[index];
				item_info.count = 2
				
				name = item_info.name
				texture = item_info.t
				count = item_info.count
				quality = item_info.q
				canUse = item_info.canUse
				level = item_info.uselevel
				itemId = item_info.h
			end
			
			-- Show or hide auction buttons
			if ( shouldHide ) then
				button:Hide();
				-- If the last button is empty then set isLastSlotEmpty var
				if ( i == NUM_BROWSE_TO_DISPLAY ) then
					isLastSlotEmpty = 1;
				end
			else
				button:Show();

				buttonName = "StockpileBrowseButton"..i;

				-- Resize button if there isn't a scrollbar
				buttonHighlight = _G["StockpileBrowseButton"..i.."Highlight"];
				buttonLastColumn = _G["StockpileBrowseButton"..i.."ItemSubtypeColumn"];
				if ( numBatchAuctions < NUM_BROWSE_TO_DISPLAY ) then
					button:SetWidth(625);
					buttonHighlight:SetWidth(589);
					StockpileBrowseItemSubtypeSort:SetWidth(158);
					buttonLastColumn:SetWidth(138);
				elseif ( numBatchAuctions == NUM_BROWSE_TO_DISPLAY and totalAuctions <= NUM_BROWSE_TO_DISPLAY ) then
					button:SetWidth(625);
					buttonHighlight:SetWidth(589);
					StockpileBrowseItemSubtypeSort:SetWidth(158);
					buttonLastColumn:SetWidth(138);
				else
					button:SetWidth(600);
					buttonHighlight:SetWidth(562);
					StockpileBrowseItemSubtypeSort:SetWidth(135);
					buttonLastColumn:SetWidth(115);
				end
				-- Set name and quality color
				color = ITEM_QUALITY_COLORS[quality];
				itemName = _G[buttonName.."ItemNameColumnText"];
				itemName:SetText(name);
				itemName:SetVertexColor(color.r, color.g, color.b);
				local itemButton = _G[buttonName.."Item"];

				SetItemButtonQuality(itemButton, quality, itemId);
				
				-- local rarityString = _G["ITEM_QUALITY"..quality.."_DESC"];
				-- _G[buttonName.."ItemRarityColumnText"]:SetText(rarityString);
				-- _G[buttonName.."ItemRarityColumnText"]:SetVertexColor(color.r, color.g, color.b);
				-- _G[buttonName.."ItemRarityColumn"].tooltip = rarityString;
				
				-- Set level
				if ( level > UnitLevel("player") ) then
					_G[buttonName.."ItemUseLevelColumnText"]:SetText(RED_FONT_COLOR_CODE..level..FONT_COLOR_CODE_CLOSE);
				else
					_G[buttonName.."ItemUseLevelColumnText"]:SetText(level);
				end
				_G[buttonName.."ItemUseLevelColumn"].tooltip = level;
				
				-- Set ilvl
				_G[buttonName.."ItemLevelColumnText"]:SetText(item_info.ilvl);
				_G[buttonName.."ItemLevelColumn"].tooltip = item_info.ilvl;
				
				-- Set item category
				_G[buttonName.."ItemTypeColumnText"]:SetText(item_info.itemtype);
				_G[buttonName.."ItemTypeColumn"].tooltip = item_info.itemtype;
				
				-- Set item subcategory
				_G[buttonName.."ItemSubtypeColumnText"]:SetText(item_info.itemsubtype);
				_G[buttonName.."ItemSubtypeColumn"].tooltip = item_info.itemsubtype;
				
				-- Set item texture, count, and usability
				iconTexture = _G[buttonName.."ItemIconTexture"];
				iconTexture:SetTexture(texture);
				if ( not canUse ) then
					iconTexture:SetVertexColor(1.0, 0.1, 0.1);
				else
					iconTexture:SetVertexColor(1.0, 1.0, 1.0);
				end
				itemCount = _G[buttonName.."ItemCount"];
				if ( count > 1 ) then
					itemCount:SetText(count);
					itemCount:Show();
				else
					itemCount:Hide();
				end

				button.itemCount = count;
				button.itemIndex = index;

				-- Set highlight
				if ( ArkInventorySearch_Stockpile.GetSelectedStockpileItem("list") and (offset + i) == ArkInventorySearch_Stockpile.GetSelectedStockpileItem("list") ) then
					button:LockHighlight();
				else
					button:UnlockHighlight();
				end
			end
		end

		-- Update scrollFrame
		-- If more than one page of auctions show the next and prev arrows when the scrollframe is scrolled all the way down
		if ( totalAuctions > NUM_AUCTION_ITEMS_PER_PAGE ) then
			-- BrowsePrevPageButton.isEnabled = (StockpileFrameBrowse.page ~= 0);
			-- BrowseNextPageButton.isEnabled = (StockpileFrameBrowse.page ~= (ceil(totalAuctions/NUM_AUCTION_ITEMS_PER_PAGE) - 1));
			if ( isLastSlotEmpty ) then
				StockpileBrowseSearchCountText:Show();
				local itemsMin = StockpileFrameBrowse.page * NUM_AUCTION_ITEMS_PER_PAGE + 1;
				local itemsMax = itemsMin + numBatchAuctions - 1;
				StockpileBrowseSearchCountText:SetFormattedText(NUMBER_OF_RESULTS_TEMPLATE, itemsMin, itemsMax, totalAuctions);
			else
				StockpileBrowseSearchCountText:Hide();
			end
			
			-- Artifically inflate the number of results so the scrollbar scrolls one extra row
			numBatchAuctions = numBatchAuctions + 1;
		else
			-- BrowsePrevPageButton.isEnabled = false;
			-- BrowseNextPageButton.isEnabled = false;
			StockpileBrowseSearchCountText:Hide();
		end
		FauxScrollFrame_Update(StockpileBrowseScrollFrame, numBatchAuctions, NUM_BROWSE_TO_DISPLAY, AUCTIONS_BUTTON_HEIGHT);
end

function ArkInventorySearch_Stockpile.StockpileBrowseFrame_CheckUnlockHighlight(self, selectedType, offset)
	local selected = ArkInventorySearch_Stockpile.GetSelectedStockpileItem(selectedType);
	if ( not selected or (selected ~= self:GetParent():GetID() + offset) ) then
		self:GetParent():UnlockHighlight();
	end
end

function ArkInventorySearch_Stockpile.StockpileFrameItem_OnEnter(self, type, index)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");

	--local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = GameTooltip:SetAuctionItem(type, index);
	local item_h = ArkInventorySearch_Stockpile.SearchResultsTable[index].h or ""

	ArkInventory.GameTooltipSetHyperlink( self, item_h )

	GameTooltip_ShowCompareItem();

	if ( IsModifiedClick("DRESSUP") ) then
		ShowInspectCursor();
	else
		ResetCursor();
	end
end

-- SortButton functions
function ArkInventorySearch_Stockpile.SortButton_UpdateArrow(button, type, sort)
	local primaryColumn, reversed = ArkInventorySearch_Stockpile.StockpileFrame_GetStockpileSort(type);
	button.Arrow:SetShown(sort == primaryColumn);
	if (sort == primaryColumn) then
		if (reversed) then
			button.Arrow:SetTexCoord(0, 0.5625, 0, 1);
		else
			button.Arrow:SetTexCoord(0, 0.5625, 1, 0);
		end
	end
end
