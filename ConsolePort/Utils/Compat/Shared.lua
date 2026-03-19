local _, db = ...;
---------------------------------------------------------------
-- Compat/Shared.lua
-- API wrappers available on ALL supported game versions.
-- Add entries here when a global moves into a C_ namespace
-- but the old global still exists on some versions.
---------------------------------------------------------------
local function nopz() return 0  end
local function nopt() return {} end

---@class CPAPI
CPAPI.ContainerIDToInventoryID       = C_Container     and C_Container.ContainerIDToInventoryID          or ContainerIDToInventoryID;
CPAPI.DisableAddOn                   = C_AddOns        and C_AddOns.DisableAddOn                         or DisableAddOn;
CPAPI.EnableAddOn                    = C_AddOns        and C_AddOns.EnableAddOn                          or EnableAddOn;
CPAPI.GetAddOnInfo                   = C_AddOns        and C_AddOns.GetAddOnInfo                         or GetAddOnInfo;
CPAPI.GetContainerItemID             = C_Container     and C_Container.GetContainerItemID                or GetContainerItemID;
CPAPI.GetContainerItemQuestInfo      = C_Container     and C_Container.GetContainerItemQuestInfo         or GetContainerItemQuestInfo;
CPAPI.GetContainerNumFreeSlots       = C_Container     and C_Container.GetContainerNumFreeSlots          or GetContainerNumFreeSlots;
CPAPI.GetContainerNumSlots           = C_Container     and C_Container.GetContainerNumSlots              or GetContainerNumSlots;
CPAPI.GetItemCount                   = C_Item          and C_Item.GetItemCount                           or GetItemCount;
CPAPI.GetItemLink                    = C_Item          and C_Item.GetItemLink                            or nop;
CPAPI.GetItemSpell                   = C_Item          and C_Item.GetItemSpell                           or GetItemSpell;
CPAPI.GetLootMethod                  = C_PartyInfo     and C_PartyInfo.GetLootMethod                     or GetLootMethod;
CPAPI.GetNumQuestWatches             = C_QuestLog      and C_QuestLog.GetNumQuestWatches                 or nopz;
CPAPI.GetNumSpellTabs                = C_SpellBook     and C_SpellBook.GetNumSpellBookSkillLines         or GetNumSpellTabs;
CPAPI.GetQuestLogIndexForQuestID     = C_QuestLog      and C_QuestLog.GetLogIndexForQuestID              or nop;
CPAPI.GetSpellBookItemLink           = C_SpellBook     and C_SpellBook.GetSpellBookItemLink              or GetSpellLink;
CPAPI.GetSpellBookItemName           = C_SpellBook     and C_SpellBook.GetSpellBookItemName              or GetSpellBookItemName;
CPAPI.GetSpellBookItemTexture        = C_SpellBook     and C_SpellBook.GetSpellBookItemTexture           or GetSpellBookItemTexture;
CPAPI.GetSpellBookItemType           = C_SpellBook     and C_SpellBook.GetSpellBookItemType              or GetSpellBookItemInfo;
CPAPI.GetSpellLink                   = C_Spell         and C_Spell.GetSpellLink                          or GetSpellLink;
CPAPI.GetSpellName                   = C_Spell         and C_Spell.GetSpellName                          or GetSpellName;
CPAPI.GetSpellSubtext                = C_Spell         and C_Spell.GetSpellSubtext                       or GetSpellSubtext;
CPAPI.GetSpellTexture                = C_Spell         and C_Spell.GetSpellTexture                       or GetSpellTexture;
CPAPI.HasPetSpells                   = C_SpellBook     and C_SpellBook.HasPetSpells                      or HasPetSpells;
CPAPI.IsAddOnLoaded                  = C_AddOns        and C_AddOns.IsAddOnLoaded                        or IsAddOnLoaded;
CPAPI.IsEquippableItem               = C_Item          and C_Item.IsEquippableItem                       or IsEquippableItem;
CPAPI.IsEquippedItem                 = C_Item          and C_Item.IsEquippedItem                         or IsEquippedItem;
CPAPI.IsPassiveSpell                 = C_Spell         and C_Spell.IsSpellPassive                        or IsPassiveSpell;
CPAPI.IsSpellBookItemPassive         = C_SpellBook     and C_SpellBook.IsSpellBookItemPassive            or IsPassiveSpell;
CPAPI.IsSpellHarmful                 = C_Spell         and C_Spell.IsSpellHarmful                        or IsHarmfulSpell;
CPAPI.IsSpellHelpful                 = C_Spell         and C_Spell.IsSpellHelpful                        or IsHelpfulSpell;
CPAPI.IsUsableItem                   = C_Item          and C_Item.IsUsableItem                           or IsUsableItem;
CPAPI.LeaveParty                     = C_PartyInfo     and C_PartyInfo.LeaveParty                        or LeaveParty;
CPAPI.LoadAddOn                      = C_AddOns        and C_AddOns.LoadAddOn                            or LoadAddOn;
CPAPI.PickupContainerItem            = C_Container     and C_Container.PickupContainerItem               or PickupContainerItem;
CPAPI.PickupItem                     = C_Item          and C_Item.PickupItem                             or PickupItem;
CPAPI.PickupSpell                    = C_Spell         and C_Spell.PickupSpell                           or PickupSpell;
CPAPI.PickupSpellBookItem            = C_SpellBook     and C_SpellBook.PickupSpellBookItem               or PickupSpellBookItem;
CPAPI.RequestLoadQuestByID           = C_QuestLog      and C_QuestLog.RequestLoadQuestByID               or nop;
CPAPI.RunMacroText                   = C_Macro         and C_Macro.RunMacroText                          or RunMacroText;
CPAPI.SocketContainerItem            = C_Container     and C_Container.SocketContainerItem               or SocketContainerItem;
CPAPI.SplitContainerItem             = C_Container     and C_Container.SplitContainerItem                or SplitContainerItem;
CPAPI.UseContainerItem               = C_Container     and C_Container.UseContainerItem                  or UseContainerItem;

-- Globals that may not exist on all versions
CPAPI.ClearCursor                    = ClearCursor        or nop;
CPAPI.GetOverrideBarSkin             = GetOverrideBarSkin or nop;
CPAPI.IsInLFDBattlefield             = IsInLFDBattlefield or nop;
CPAPI.IsInLFGDungeon                 = IsInLFGDungeon     or nop;
CPAPI.IsPartyLFG                     = IsPartyLFG         or nop;
CPAPI.IsSpellOverlayed               = IsSpellOverlayed   or nop;
CPAPI.IsXPUserDisabled               = IsXPUserDisabled   or nop;
CPAPI.PlayerHasToy                   = PlayerHasToy       or nop;
CPAPI.Scrub                          = scrubsecretvalues  or function(...) return ... end;

---------------------------------------------------------------
-- Complex wrappers: normalize return shapes across versions
---------------------------------------------------------------

---@return ContainerItemInfo
function CPAPI.GetContainerItemInfo(...)
	if C_Container and C_Container.GetContainerItemInfo then
		return C_Container.GetContainerItemInfo(...) or {};
	end
	if GetContainerItemInfo then
		local icon, itemCount, locked, quality, readable, lootable, itemLink,
			isFiltered, noValue, itemID, isBound = GetContainerItemInfo(...)
		return {
			hasLoot    = lootable;
			hasNoValue = noValue;
			hyperlink  = itemLink;
			iconFileID = icon;
			isBound    = isBound;
			isFiltered = isFiltered;
			isLocked   = locked;
			isReadable = readable;
			itemID     = itemID;
			quality    = quality;
			stackCount = itemCount;
		};
	end
	return {};
end

---@return ItemInfo
function CPAPI.GetItemInfo(...)
	local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
		itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType,
		expacID, setID, isCraftingReagent = (GetItemInfo or C_Item.GetItemInfo)(...)
	return {
		itemName          = itemName;
		itemLink          = itemLink;
		itemQuality       = itemQuality;
		itemLevel         = itemLevel;
		itemMinLevel      = itemMinLevel;
		itemType          = itemType;
		itemSubType       = itemSubType;
		itemStackCount    = itemStackCount;
		itemEquipLoc      = itemEquipLoc;
		itemTexture       = itemTexture;
		sellPrice         = sellPrice;
		classID           = classID;
		subclassID        = subclassID;
		bindType          = bindType;
		expacID           = expacID;
		setID             = setID;
		isCraftingReagent = isCraftingReagent;
	};
end

---@return ItemInfoInstant
function CPAPI.GetItemInfoInstant(...)
	local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant;
	if GetItemInfoInstant then
		local itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID = GetItemInfoInstant(...)
		return {
			itemID       = itemID;
			itemType     = itemType;
			itemSubType  = itemSubType;
			itemEquipLoc = itemEquipLoc;
			icon         = icon;
			classID      = classID;
			subclassID   = subclassID;
		};
	end
	return {};
end

---@return SpellInfo
function CPAPI.GetSpellInfo(...)
	if GetSpellInfo then
		local name, rank, icon, castTime, minRange, maxRange, spellID, originalIcon = GetSpellInfo(...)
		return {
			name           = name;
			rank           = rank;
			iconID         = icon;
			castTime       = castTime;
			minRange       = minRange;
			maxRange       = maxRange;
			spellID        = spellID;
			originalIconID = originalIcon;
		};
	end
	return C_Spell.GetSpellInfo(...) or {};
end

---@return SpellBookSkillLineInfo
function CPAPI.GetSpellTabInfo(...)
	if GetSpellTabInfo then
		local name, texture, offset, numSlots, isGuild, offSpecID, shouldHide, specID = GetSpellTabInfo(...)
		return {
			name              = name;
			iconID            = texture;
			itemIndexOffset   = offset;
			numSpellBookItems = numSlots;
			isGuild           = isGuild;
			offSpecID         = offSpecID;
			shouldHide        = shouldHide;
			specID            = specID;
		};
	end
	return C_SpellBook.GetSpellBookSkillLineInfo(...) or {};
end

---@return SpellBookItemInfo
function CPAPI.GetSpellBookItemInfo(...)
	if GetSpellBookItemInfo then
		local itemType, id = GetSpellBookItemInfo(...)
		local iconID     = GetSpellBookItemTexture(...)
		local name       = GetSpellBookItemName(...)
		local isPassive  = IsPassiveSpell(...)
		local spellID    = select(7, GetSpellInfo(...))
		return {
			itemType = itemType;
			actionID = spellID or id;
			spellID  = spellID;
			name     = name;
			iconID   = iconID;
			isPassive = isPassive;
		};
	end
	return C_SpellBook.GetSpellBookItemInfo(...) or {};
end

---@return LootSlotInfo
function CPAPI.GetLootSlotInfo(...)
	local lootIcon, lootName, lootQuantity, currencyID, lootQuality,
		locked, isQuestItem, questID, isActive = GetLootSlotInfo(...)
	return {
		lootIcon     = lootIcon;
		lootName     = lootName;
		lootQuantity = lootQuantity;
		currencyID   = currencyID;
		lootQuality  = lootQuality;
		locked       = locked;
		isQuestItem  = isQuestItem;
		questID      = questID;
		isActive     = isActive;
		lootLink     = GetLootSlotLink(...);
	};
end

---@return QuestInfo
function CPAPI.GetQuestInfo(...)
	if C_QuestLog and C_QuestLog.GetInfo then
		return C_QuestLog.GetInfo(...) or {};
	end
	if GetQuestLogTitle then
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
			frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI,
			isTask, isBounty, isStory, isHidden, isScaling = GetQuestLogTitle(...)
		return {
			title          = title;
			level          = level;
			suggestedGroup = suggestedGroup;
			isHeader       = isHeader;
			isCollapsed    = isCollapsed;
			isComplete     = isComplete;
			frequency      = frequency;
			questID        = questID;
			startEvent     = startEvent;
			displayQuestID = displayQuestID;
			isOnMap        = isOnMap;
			hasLocalPOI    = hasLocalPOI;
			isTask         = isTask;
			isBounty       = isBounty;
			isStory        = isStory;
			isHidden       = isHidden;
			isScaling      = isScaling;
		};
	end
	return {};
end

---@return FactionData|nil
function CPAPI.GetWatchedFactionData(...)
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		return C_Reputation.GetWatchedFactionData(...)
	end
	if GetWatchedFactionInfo then
		local name, standingID, min, max, value, factionID = GetWatchedFactionInfo(...)
		return {
			name                   = name;
			reaction               = standingID;
			currentReactionThreshold = min;
			nextReactionThreshold  = max;
			currentStanding        = value;
			factionID              = factionID;
		};
	end
end

---@return MacroInfo|nil
function CPAPI.GetMacroInfo(macroID)
	local name, icon, body = GetMacroInfo(macroID)
	if name then
		return { name = name; icon = icon; body = body };
	end
end

function CPAPI.GetAllMacroInfo()
	local info = {};
	for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
		info[i] = CPAPI.GetMacroInfo(i);
	end
	return info;
end

function CPAPI.CanPlayerDisenchantItem(itemID)
	local spellID = CPAPI.GetSpellInfo('Disenchant').spellID;
	if spellID and IsPlayerSpell(spellID) then
		local info = CPAPI.GetItemInfo(itemID)
		local class, quality = info.classID, info.itemQuality;
		if class and quality then
			return
				(class == Enum.ItemClass.Weapon or class == Enum.ItemClass.Armor)
				and quality >= (Enum.ItemQuality.Good or Enum.ItemQuality.Uncommon)
				and quality <= (Enum.ItemQuality.Epic);
		end
	end
	return false;
end

---------------------------------------------------------------
-- Lua stdlib polyfills
---------------------------------------------------------------

CPAPI.CreateColorFromHexString = CreateColorFromHexString or function(hexColor)
	if #hexColor == 8 then
		local function ExtractColorValueFromHex(str, index)
			return tonumber(str:sub(index, index + 1), 16) / 255;
		end
		local a, r, g, b =
			ExtractColorValueFromHex(hexColor, 1),
			ExtractColorValueFromHex(hexColor, 3),
			ExtractColorValueFromHex(hexColor, 5),
			ExtractColorValueFromHex(hexColor, 7);
		return CreateColor(r, g, b, a);
	end
end

CPAPI.CreateKeyChord = CreateKeyChordStringUsingMetaKeyState or (function()
	local function CreateKeyChordStringFromTable(keys, preventSort)
		if not preventSort then
			table.sort(keys, KeyComparator)
		end
		return table.concat(keys, '-')
	end
	return function(key)
		local chord = {};
		if IsAltKeyDown()     then tinsert(chord, 'ALT')   end
		if IsControlKeyDown() then tinsert(chord, 'CTRL')  end
		if IsShiftKeyDown()   then tinsert(chord, 'SHIFT') end
		if IsMetaKeyDown()    then tinsert(chord, 'META')  end
		if not IsMetaKey(key) then tinsert(chord, key)     end
		return CreateKeyChordStringFromTable(chord, true)
	end
end)()

CPAPI.MinEditDistance = CalculateStringEditDistance or function(str1, str2)
	local len1, len2, min, byte = #str1, #str2, math.min, string.byte;
	local matrix = {}
	for i = 0, len1 do matrix[i] = { [0] = i } end
	for j = 0, len2 do matrix[0][j] = j         end
	for i = 1, len1 do
		for j = 1, len2 do
			local cost = (byte(str1, i) == byte(str2, j)) and 0 or 1;
			matrix[i][j] = min(
				matrix[i-1][j] + 1,
				matrix[i][j-1] + 1,
				matrix[i-1][j-1] + cost
			);
		end
	end
	return matrix[len1][len2];
end

CPAPI.OpenStackSplitFrame = OpenStackSplitFrame or function(...)
	return StackSplitFrame:OpenStackSplitFrame(...)
end

CPAPI.GetScaledCursorPositionForFrame = GetScaledCursorPositionForFrame or function(frame)
	local uiScale = frame:GetEffectiveScale();
	local x, y = GetCursorPosition();
	return x / uiScale, y / uiScale;
end

CPAPI.CreateSimpleTextureMarkup = CreateSimpleTextureMarkup or function(file, width, height)
	return ('|T%s:%d:%d|t'):format(file, height or width, width)
end

CPAPI.HideAndClearAnchors = FramePool_HideAndClearAnchors or function(framePool, frame)
	frame:Hide()
	frame:ClearAllPoints()
end

CPAPI.HideAndClearAnchorsWithReset = FramePool_HideAndClearAnchorsWithReset or function(framePool, frame)
	frame:Hide()
	frame:ClearAllPoints()
	frame:Reset()
end

CPAPI.IteratePlayerInventory = CPAPI.IsRetailVersion and ItemUtil.IteratePlayerInventory or function(callback)
	local MAX_CONTAINER_ITEMS = MAX_CONTAINER_ITEMS or 36;
	local NUM_BAG_FRAMES      = NUM_BAG_FRAMES      or 4;
	for bag = 0, NUM_BAG_FRAMES do
		for slot = 1, MAX_CONTAINER_ITEMS do
			local bagItem = ItemLocation:CreateFromBagAndSlot(bag, slot);
			if C_Item.DoesItemExist(bagItem) then
				callback(bagItem);
			end
		end
	end
end

CPAPI.PutActionInSlot = C_ActionBar and C_ActionBar.PutActionInSlot or PlaceAction;

---------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------

function CPAPI.SetGradient(...)
	return LibStub('Carpenter'):SetGradient(...)
end

function CPAPI.SetModelLight(self, enabled, lightValues)
	if (pcall(self.SetLight, self, enabled, lightValues)) then return end
	local dirX, dirY, dirZ = lightValues.point:GetXYZ()
	local ambR, ambG, ambB = lightValues.ambientColor:GetRGB()
	local difR, difG, difB = lightValues.diffuseColor:GetRGB()
	return (pcall(self.SetLight, self, enabled,
		lightValues.omnidirectional,
		dirX, dirY, dirZ,
		lightValues.diffuseIntensity,
		difR, difG, difB,
		lightValues.ambientIntensity,
		ambR, ambG, ambB
	))
end

function CPAPI.AutoCastStart(self, autoCastAllowed, ...)
	if (self.Shine or self.AutoCastShine) and AutoCastShine_AutoCastStart then
		return AutoCastShine_AutoCastStart(self.Shine or self.AutoCastShine, ...)
	end
	if self.AutoCastOverlay and self.AutoCastOverlay.ShowAutoCastEnabled then
		self.AutoCastOverlay:SetShown(autoCastAllowed)
		return self.AutoCastOverlay:ShowAutoCastEnabled(true)
	end
end

function CPAPI.AutoCastStop(self, autoCastAllowed)
	if (self.Shine or self.AutoCastShine) and AutoCastShine_AutoCastStop then
		return AutoCastShine_AutoCastStop(self.Shine or self.AutoCastShine)
	end
	if self.AutoCastOverlay and self.AutoCastOverlay.ShowAutoCastEnabled then
		self.AutoCastOverlay:SetShown(autoCastAllowed)
		return self.AutoCastOverlay:ShowAutoCastEnabled(false)
	end
end
