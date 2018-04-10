NUM_BROWSE_TO_DISPLAY = 8;
NUM_AUCTION_ITEMS_PER_PAGE = 50;
NUM_FILTERS_TO_DISPLAY = 15;
BROWSE_FILTER_HEIGHT = 20;
AUCTIONS_BUTTON_HEIGHT = 37;
CLASS_FILTERS = {};
OPEN_FILTER_LIST = {};

ArkInventorySearch_Stockpile.StockpileSort = { };

-- list sorts
ArkInventorySearch_Stockpile.StockpileSort["list_name"] = {
	-- { column = "duration",	reverse = false	},
	-- { column = "unitprice",		reverse = false },
	-- { column = "quantity",	reverse = true	},
	-- { column = "minbidbuyout",	reverse = false	},
	{ column = "name",		reverse = false	},
	-- { column = "level",		reverse = true	},
	-- { column = "quality",	reverse = false	},
};
ArkInventorySearch_Stockpile.StockpileSort["list_level"] = {
	-- { column = "duration",	reverse = true	},
	-- { column = "unitprice",		reverse = false },
	-- { column = "quantity",	reverse = false	},
	-- { column = "minbidbuyout",	reverse = true	},
	-- { column = "name",		reverse = true	},
	-- { column = "quality",	reverse = true	},
	{ column = "uselevel",		reverse = false	},
	{ column = "name",		reverse = false	},
};
ArkInventorySearch_Stockpile.StockpileSort["list_itemLevel"] = {
	-- { column = "unitprice",		reverse = false },
	-- { column = "quantity",	reverse = true	},
	-- { column = "minbidbuyout",	reverse = false	},
	-- { column = "level",		reverse = true	},
	-- { column = "quality",	reverse = false	},
	-- { column = "duration",	reverse = false	},
	{ column = "ilvl", reverse = false },
	{ column = "name",		reverse = false	},
};
ArkInventorySearch_Stockpile.StockpileSort["list_itemType"] = {
	-- { column = "duration",	reverse = false	},
	-- { column = "unitprice",		reverse = false },
	-- { column = "quantity",	reverse = true	},
	-- { column = "minbidbuyout",	reverse = false	},
	-- { column = "level",		reverse = true	},
	-- { column = "quality",	reverse = false	},
	-- { column = "seller",	reverse = false	},
	{ column = "itemtype",		reverse = false	},
	{ column = "name",		reverse = false	},
};
ArkInventorySearch_Stockpile.StockpileSort["list_itemSubtype"] = {
	-- { column = "duration",	reverse = false	},
	-- { column = "unitprice",		reverse = false },
	-- { column = "quantity",	reverse = true	},
	-- { column = "minbidbuyout",	reverse = false	},
	-- { column = "level",		reverse = true	},
	-- { column = "quality",	reverse = false	},
	-- { column = "seller",	reverse = false	},
	{ column = "itemsubtype",		reverse = false	},
	{ column = "name",		reverse = false	},
};

ArkInventorySearch_Stockpile.StockpileSort["list_quality"] = {
	-- { column = "duration",	reverse = false	},
	-- { column = "unitprice",		reverse = false },
	-- { column = "quantity",	reverse = true	},
	-- { column = "minbidbuyout",	reverse = false	},
	-- { column = "level",		reverse = true	},
	{ column = "q",	reverse = false	},
	{ column = "name",		reverse = false	},
};

ArkInventorySearch_Stockpile.StockpileCategories = {};

local function FindDeepestCategory(categoryIndex, ...)
	local categoryInfo = ArkInventorySearch_Stockpile.StockpileCategories[categoryIndex];
	for i = 1, select("#", ...) do
		local subCategoryIndex = select(i, ...);
		if categoryInfo and categoryInfo.subCategories and categoryInfo.subCategories[subCategoryIndex] then
			categoryInfo = categoryInfo.subCategories[subCategoryIndex];
		else
			break;
		end
	end
	return categoryInfo;
end

function ArkInventorySearch_Stockpile.GetDetailColumnString(categoryIndex, subCategoryIndex)
	local categoryInfo = FindDeepestCategory(categoryIndex, subCategoryIndex);
	return categoryInfo and categoryInfo:GetDetailColumnString() or REQ_LEVEL_ABBR;
end

function ArkInventorySearch_Stockpile.DoesCategoryHaveFlag(flag, categoryIndex, subCategoryIndex, subSubCategoryIndex)
	local categoryInfo = FindDeepestCategory(categoryIndex, subCategoryIndex, subSubCategoryIndex);
	if categoryInfo then
		return categoryInfo:HasFlag(flag);
	end
	return false;
end

function ArkInventorySearch_Stockpile.CreateCategory(name)
	local category = CreateFromMixins(ArkInventorySearch_Stockpile.AuctionCategoryMixin);
	category.name = name;
	ArkInventorySearch_Stockpile.StockpileCategories[#ArkInventorySearch_Stockpile.StockpileCategories + 1] = category;
	return category;
end

ArkInventorySearch_Stockpile.AuctionCategoryMixin = {};

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:SetDetailColumnString(detailColumnString)
	self.detailColumnString = detailColumnString;
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:GetDetailColumnString()
	if self.detailColumnString then
		return self.detailColumnString;
	end
	if self.parent then
		return self.parent:GetDetailColumnString();
	end
	return REQ_LEVEL_ABBR;
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:CreateSubCategory(classID, subClassID, inventoryType)
	local name = "";
	if inventoryType then
		name = GetItemInventorySlotInfo(inventoryType);
	elseif classID and subClassID then
		name = GetItemSubClassInfo(classID, subClassID);
	elseif classID then
		name = GetItemClassInfo(classID);
	end
	
	-- work around to add mounts category
	if not name and classID == LE_ITEM_CLASS_MISCELLANEOUS and subClassID ==  LE_ITEM_MISCELLANEOUS_MOUNT + 10 then
		name = ACCOUNT_LEVEL_MOUNT
	elseif not name and classID == LE_ITEM_CLASS_MISCELLANEOUS and subClassID ==  LE_ITEM_MISCELLANEOUS_MOUNT then
		name = BAGSLOTTEXT
	end
	
	return self:CreateNamedSubCategory(name);
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:CreateNamedSubCategory(name)
	self.subCategories = self.subCategories or {};

	local subCategory = CreateFromMixins(ArkInventorySearch_Stockpile.AuctionCategoryMixin);
	self.subCategories[#self.subCategories + 1] = subCategory;

	assert(name and #name > 0);
	subCategory.name = name;
	subCategory.parent = self;
	subCategory.sortIndex = #self.subCategories;
	return subCategory;
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:CreateNamedSubCategoryAndFilter(name, classID, subClassID, inventoryType)
	local category = self:CreateNamedSubCategory(name);
	category:AddFilter(classID, subClassID, inventoryType);

	return category;
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:CreateSubCategoryAndFilter(classID, subClassID, inventoryType)
	local category = self:CreateSubCategory(classID, subClassID, inventoryType);
	category:AddFilter(classID, subClassID, inventoryType);

	return category;
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:AddBulkInventoryTypeCategories(classID, subClassID, inventoryTypes)
	for i, inventoryType in ipairs(inventoryTypes) do
		self:CreateSubCategoryAndFilter(classID, subClassID, inventoryType);
	end
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:AddFilter(classID, subClassID, inventoryType)
	self.filters = self.filters or {};
	self.filters[#self.filters + 1] = { classID = classID, subClassID = subClassID, inventoryType = inventoryType, };

	if self.parent then
		self.parent:AddFilter(classID, subClassID, inventoryType);
	end
end

do
	local function GenerateSubClassesHelper(self, classID, ...)
		for i = 1, select("#", ...) do
			local subClassID = select(i, ...);
			self:CreateSubCategoryAndFilter(classID, subClassID);
		end
	end

	function ArkInventorySearch_Stockpile.AuctionCategoryMixin:GenerateSubCategoriesAndFiltersFromSubClass(classID)
		GenerateSubClassesHelper(self, classID, GetAuctionItemSubClasses(classID));
	end
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:FindSubCategoryByName(name)
	if self.subCategories then
		for i, subCategory in ipairs(self.subCategories) do
			if subCategory.name == name then
				return subCategory;
			end
		end
	end
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:SortSubCategories()
	if self.subCategories then
		table.sort(self.subCategories, function(left, right)
			return left.sortIndex < right.sortIndex;
		end)
	end
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:SetSortIndex(sortIndex)
	self.sortIndex = sortIndex
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:SetFlag(flag)
	self.flags = self.flags or {};
	self.flags[flag] = true;
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:ClearFlag(flag)
	if self.flags then
		self.flags[flag] = nil;
	end
end

function ArkInventorySearch_Stockpile.AuctionCategoryMixin:HasFlag(flag)
	return not not (self.flags and self.flags[flag]);
end

do -- Weapons
	local weaponsCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_WEAPONS);

	local oneHandedCategory = weaponsCategory:CreateNamedSubCategory(AUCTION_SUBCATEGORY_ONE_HANDED);
	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_AXE1H);
	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_MACE1H);
	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_SWORD1H);

	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_WARGLAIVE);
	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_DAGGER);
	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_UNARMED);
	oneHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_WAND);

	local twoHandedCategory = weaponsCategory:CreateNamedSubCategory(AUCTION_SUBCATEGORY_TWO_HANDED);
	twoHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_AXE2H);
	twoHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_MACE2H);
	twoHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_SWORD2H);

	twoHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_POLEARM);
	twoHandedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_STAFF);

	local rangedCategory = weaponsCategory:CreateNamedSubCategory(AUCTION_SUBCATEGORY_RANGED);
	rangedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_BOWS);
	rangedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_CROSSBOW);
	rangedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_GUNS);
	rangedCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_THROWN);
	
	local miscCategory = weaponsCategory:CreateNamedSubCategory(AUCTION_SUBCATEGORY_MISCELLANEOUS);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_FISHINGPOLE);

	local otherCategory = miscCategory:CreateNamedSubCategory(AUCTION_SUBCATEGORY_OTHER);
	otherCategory:AddFilter(LE_ITEM_CLASS_WEAPON, LE_ITEM_WEAPON_GENERIC);
end

do -- Armor
	local ArmorInventoryTypes = {
		LE_INVENTORY_TYPE_HEAD_TYPE,
		LE_INVENTORY_TYPE_SHOULDER_TYPE,
		LE_INVENTORY_TYPE_CHEST_TYPE,
		LE_INVENTORY_TYPE_WAIST_TYPE,
		LE_INVENTORY_TYPE_LEGS_TYPE,
		LE_INVENTORY_TYPE_FEET_TYPE,
		LE_INVENTORY_TYPE_WRIST_TYPE,
		LE_INVENTORY_TYPE_HAND_TYPE,
	};

	local armorCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_ARMOR);

	local plateCategory = armorCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_PLATE);
	plateCategory:AddBulkInventoryTypeCategories(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_PLATE, ArmorInventoryTypes);

	local plateChestCategory = plateCategory:FindSubCategoryByName(GetItemInventorySlotInfo(LE_INVENTORY_TYPE_CHEST_TYPE));
	plateChestCategory:AddFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_PLATE, LE_INVENTORY_TYPE_ROBE_TYPE);

	local mailCategory = armorCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_MAIL);
	mailCategory:AddBulkInventoryTypeCategories(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_MAIL, ArmorInventoryTypes);
	
	local mailChestCategory = mailCategory:FindSubCategoryByName(GetItemInventorySlotInfo(LE_INVENTORY_TYPE_CHEST_TYPE));
	mailChestCategory:AddFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_MAIL, LE_INVENTORY_TYPE_ROBE_TYPE);

	local leatherCategory = armorCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_LEATHER);
	leatherCategory:AddBulkInventoryTypeCategories(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_LEATHER, ArmorInventoryTypes);

	local leatherChestCategory = leatherCategory:FindSubCategoryByName(GetItemInventorySlotInfo(LE_INVENTORY_TYPE_CHEST_TYPE));
	leatherChestCategory:AddFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_LEATHER, LE_INVENTORY_TYPE_ROBE_TYPE);

	local clothCategory = armorCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_CLOTH);
	clothCategory:AddBulkInventoryTypeCategories(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_CLOTH, ArmorInventoryTypes);

	local clothChestCategory = clothCategory:FindSubCategoryByName(GetItemInventorySlotInfo(LE_INVENTORY_TYPE_CHEST_TYPE));
	clothChestCategory:AddFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_CLOTH, LE_INVENTORY_TYPE_ROBE_TYPE);

	local miscCategory = armorCategory:CreateSubCategory(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC, LE_INVENTORY_TYPE_NECK_TYPE);

	miscCategory:CreateNamedSubCategoryAndFilter(AUCTION_SUBCATEGORY_CLOAK, LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_CLOTH, LE_INVENTORY_TYPE_CLOAK_TYPE);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC, LE_INVENTORY_TYPE_FINGER_TYPE);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC, LE_INVENTORY_TYPE_TRINKET_TYPE);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC, LE_INVENTORY_TYPE_HOLDABLE_TYPE);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_SHIELD);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC, LE_INVENTORY_TYPE_BODY_TYPE);
	miscCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_GENERIC, LE_INVENTORY_TYPE_HEAD_TYPE);

	local cosmeticCategory = armorCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_ARMOR, LE_ITEM_ARMOR_COSMETIC);
end

do -- Containers
	local containersCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_CONTAINERS);
	containersCategory:SetDetailColumnString(SLOT_ABBR);
	containersCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_CONTAINER);
end

do -- Gems
	local gemsCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_GEMS);
	gemsCategory:SetDetailColumnString(ITEM_LEVEL_ABBR);
	gemsCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_GEM);
end

do -- Item Enhancement
	local itemEnhancementCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_ITEM_ENHANCEMENT);
	itemEnhancementCategory:SetDetailColumnString(ITEM_LEVEL_ABBR);
	itemEnhancementCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_ITEM_ENHANCEMENT);
end

do -- Consumables
	local consumablesCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_CONSUMABLES);
	consumablesCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_CONSUMABLE);
end

do -- Glyphs
	local glyphsCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_GLYPHS);
	glyphsCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_GLYPH);
end

do -- Trade Goods
	local tradeGoodsCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_TRADE_GOODS);
	tradeGoodsCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_TRADEGOODS);
end

do -- Recipes
	local recipesCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_RECIPES);
	recipesCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_RECIPE);

	local bookCategory = recipesCategory:FindSubCategoryByName(GetItemSubClassInfo(LE_ITEM_CLASS_RECIPE, LE_ITEM_RECIPE_BOOK));
	if bookCategory then
		bookCategory:SetDetailColumnString(SKILL_ABBR);
		bookCategory:SetSortIndex(100);
	end

	recipesCategory:SortSubCategories();
end

do -- Battle Pets
	local battlePetsCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_BATTLE_PETS);
	battlePetsCategory:GenerateSubCategoriesAndFiltersFromSubClass(LE_ITEM_CLASS_BATTLEPET);
	battlePetsCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_COMPANION_PET);
end

do -- Mounts
	local mountsCategory = ArkInventorySearch_Stockpile.CreateCategory(MOUNTS);
	mountsCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_MOUNT);
	mountsCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_MOUNT + 10);
end

do -- Quest Items
	local questItemsCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_QUEST_ITEMS);
	questItemsCategory:AddFilter(LE_ITEM_CLASS_QUESTITEM);
end

do -- Miscellaneous
	local miscellaneousCategory = ArkInventorySearch_Stockpile.CreateCategory(AUCTION_CATEGORY_MISCELLANEOUS);
	miscellaneousCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_JUNK);
	miscellaneousCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_REAGENT);
	miscellaneousCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_HOLIDAY);
	miscellaneousCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_OTHER);
	miscellaneousCategory:CreateSubCategoryAndFilter(LE_ITEM_CLASS_MISCELLANEOUS, LE_ITEM_MISCELLANEOUS_MOUNT);
end
