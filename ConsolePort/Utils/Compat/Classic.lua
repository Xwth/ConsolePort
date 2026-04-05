local _, db = ...;
if CPAPI.IsRetailVersion then return end;
---------------------------------------------------------------
-- Compat/Classic.lua
-- API wrappers and fallbacks for Classic / Cata versions.
-- This file is a no-op on Retail.
---------------------------------------------------------------

---@class CPAPI

-- Mounts: not available on Classic Era, stub out safely
CPAPI.GetMountFromItem  = C_MountJournal and C_MountJournal.GetMountFromItem  or nop;
CPAPI.GetMountFromSpell = C_MountJournal and C_MountJournal.GetMountFromSpell or nop;
CPAPI.GetMountInfoByID  = C_MountJournal and C_MountJournal.GetMountInfoByID  or nop;

-- Dressable items: not available on Classic Era
CPAPI.IsDressableItemByID = C_Item and C_Item.IsDressableItemByID or nop;

-- Item sockets: not available on Classic Era
CPAPI.GetItemNumSockets = C_Item and C_Item.GetItemNumSockets or function() return 0 end;
CPAPI.GetItemQuality    = C_Item and C_Item.GetItemQuality    or nop;

-- Reputation: Classic uses old globals
CPAPI.GetFactionParagonInfo        = nop;
CPAPI.GetFriendshipReputation      = GetFriendshipReputation  or function() return {} end;
CPAPI.GetFriendshipReputationRanks = nop;
CPAPI.IsAccountWideReputation      = nop;
CPAPI.IsFactionParagon             = nop;
CPAPI.IsMajorFaction               = nop;
CPAPI.GetMajorFactionData          = nop;
CPAPI.GetRenownLevels              = nop;

-- Zone abilities: not available on Classic
CPAPI.GetActiveZoneAbilities         = function() return {} end;
CPAPI.GetCollectedDragonridingMounts = function() return {} end;
CPAPI.GetBonusBarIndexForSlot        = nop;

-- Binding context: Classic has no context parameter
function CPAPI.GetBindingAction(keyChord, checkOverride)
	return GetBindingAction(keyChord, checkOverride)
end

-- Character metadata: Classic uses class ID instead of spec ID
function CPAPI.GetCharacterMetadata()
	return select(3, UnitClass('player')), UnitClass('player')
end

function CPAPI.GetSpecialization()
	return select(3, UnitClass('player'))
end

function CPAPI.GetSpecTextureByID(ID)
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local classInfo = C_CreatureInfo.GetClassInfo(ID)
		if classInfo then
			return ([[Interface\ICONS\ClassIcon_%s.blp]]):format(classInfo.classFile)
		end
	end
end

CPAPI.GetSpecializationInfoByID = nop;

-- Average item level: Classic has no GetAverageItemLevel
function CPAPI.GetAverageItemLevel()
	if GetClassicExpansionLevel and MAX_PLAYER_LEVEL_TABLE then
		return MAX_PLAYER_LEVEL_TABLE[GetClassicExpansionLevel()]
	end
	return MAX_PLAYER_LEVEL
end
