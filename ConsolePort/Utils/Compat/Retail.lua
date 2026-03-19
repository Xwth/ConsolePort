local _, db = ...;
if not CPAPI.IsRetailVersion then return end;
---------------------------------------------------------------
-- Compat/Retail.lua
-- API wrappers that only exist on Retail (Mainline).
-- This file is a no-op on Classic/Cata.
---------------------------------------------------------------

---@class CPAPI
CPAPI.GetActiveZoneAbilities         = C_ZoneAbility   and C_ZoneAbility.GetActiveAbilities              or function() return {} end;
CPAPI.GetBonusBarIndexForSlot        = C_ActionBar     and C_ActionBar.GetBonusBarIndexForSlot           or nop;
CPAPI.GetCollectedDragonridingMounts = C_MountJournal  and C_MountJournal.GetCollectedDragonridingMounts or function() return {} end;
CPAPI.GetFactionParagonInfo          = C_Reputation    and C_Reputation.GetFactionParagonInfo            or nop;
CPAPI.GetFriendshipReputation        = C_GossipInfo    and C_GossipInfo.GetFriendshipReputation          or nop;
CPAPI.GetFriendshipReputationRanks   = C_GossipInfo    and C_GossipInfo.GetFriendshipReputationRanks     or nop;
CPAPI.GetItemNumSockets              = C_Item          and C_Item.GetItemNumSockets                      or function() return 0 end;
CPAPI.GetItemQuality                 = C_Item          and C_Item.GetItemQuality                         or nop;
CPAPI.GetMajorFactionData            = C_MajorFactions and C_MajorFactions.GetMajorFactionData           or nop;
CPAPI.GetMountFromItem               = C_MountJournal  and C_MountJournal.GetMountFromItem               or nop;
CPAPI.GetMountFromSpell              = C_MountJournal  and C_MountJournal.GetMountFromSpell              or nop;
CPAPI.GetMountInfoByID               = C_MountJournal  and C_MountJournal.GetMountInfoByID               or nop;
CPAPI.GetRenownLevels                = C_MajorFactions and C_MajorFactions.GetRenownLevels               or nop;
CPAPI.IsAccountWideReputation        = C_Reputation    and C_Reputation.IsAccountWideReputation          or nop;
CPAPI.IsDressableItemByID            = C_Item          and C_Item.IsDressableItemByID                    or nop;
CPAPI.IsFactionParagon               = C_Reputation    and C_Reputation.IsFactionParagonForCurrentPlayer or nop;
CPAPI.IsMajorFaction                 = C_Reputation    and C_Reputation.IsMajorFaction                   or nop;

-- Retail-specific binding context
function CPAPI.GetBindingAction(keyChord, checkOverride, context)
	return GetBindingAction(keyChord, checkOverride, context)
end

-- Retail-specific character metadata (spec-based)
function CPAPI.GetCharacterMetadata()
	if GetSpecializationInfo and GetSpecialization then
		return GetSpecializationInfo(GetSpecialization())
	end
end

function CPAPI.GetSpecialization()
	local currentSpecialization = GetSpecialization()
	if currentSpecialization then
		return GetSpecializationInfo(currentSpecialization)
	end
end

function CPAPI.GetSpecTextureByID(ID)
	if GetSpecializationInfoByID then
		return select(4, GetSpecializationInfoByID(ID))
	end
end

CPAPI.GetSpecializationInfoByID = GetSpecializationInfoByID or nop;
