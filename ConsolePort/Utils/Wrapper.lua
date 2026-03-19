local _, db = ...;
---------------------------------------------------------------
-- Wrapper.lua
-- db-dependent API wrappers and internal helpers.
-- Pure API shims (no db dependency) live in Compat/:
--   Compat/Shared.lua  — all versions
--   Compat/Retail.lua  — Retail only
--   Compat/Classic.lua — Classic/Cata only
---------------------------------------------------------------

function CPAPI.Log(...)
	local cc = ChatTypeInfo.SYSTEM;
	DEFAULT_CHAT_FRAME:AddMessage(db.Locale(...), cc.r, cc.g, cc.b, cc.id)
end

---------------------------------------------------------------
-- Character / class helpers (db-dependent)
---------------------------------------------------------------
local function GetClassInfo() return UnitClass('player') end
local function GetClassID()   return select(3, UnitClass('player')) end

function CPAPI.GetClassFile()
	return db('classFileOverride') or select(2, UnitClass('player'))
end

function CPAPI.GetItemLevelColor(...)
	if GetItemLevelColor then
		return GetItemLevelColor(...)
	end
	local r, g, b = CPAPI.GetClassColor()
	return r, g, b;
end

-- Retail version defined in Compat/Retail.lua; this is the Classic fallback.
if not CPAPI.GetAverageItemLevel then
	function CPAPI.GetAverageItemLevel()
		if GetAverageItemLevel then
			return floor(select(2, GetAverageItemLevel()))
		end
		if GetClassicExpansionLevel and MAX_PLAYER_LEVEL_TABLE then
			return MAX_PLAYER_LEVEL_TABLE[GetClassicExpansionLevel()]
		end
		return MAX_PLAYER_LEVEL
	end
end

function CPAPI.GetContainerTotalSlots()
	local totalFree, totalSlots, freeSlots, bagFamily = 0, 0;
	for i = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		freeSlots, bagFamily = CPAPI.GetContainerNumFreeSlots(i)
		if ( bagFamily == 0 ) then
			totalFree  = totalFree  + freeSlots;
			totalSlots = totalSlots + CPAPI.GetContainerNumSlots(i)
		end
	end
	return totalFree, totalSlots;
end

---------------------------------------------------------------
-- Binding wrappers (db-dependent: uses db.Gamepad, db.table)
---------------------------------------------------------------
do
	local FORBIDDEN_TO_CLEAR = {
		TURNORACTION         = true;
		CAMERAORSELECTORMOVE = true;
	};

	local function ReportBindingError(keyChord, bindingID)
		if not keyChord or not keyChord:match('PAD.+') then return end;
		local set = GetCurrentBindingSet();
		CPAPI.Log(table.concat({
				'Failed to set binding %s to %s.';
				'Please report this bug using in-game customer support.';
				'Steps to resolve for now:';
				'1. Backup bindings.';
				'2. Exit the game completely.';
				'3. Remove WTF/Account/%s/bindings-cache.wtf.';
				'4. Restart the game and restore bindings from backup.';
			}, '\n'),
			BLUE_FONT_COLOR:WrapTextInColorCode(tostring(keyChord)),
			BLUE_FONT_COLOR:WrapTextInColorCode(GetBindingName(tostring(bindingID))),
			set == Enum.BindingSet.Character and
				('<AccountName>/%s/%s'):format(GetRealmName(), UnitName('player')) or
			set == Enum.BindingSet.Account and
				'<AccountName>' or '*'
		);
	end

	local function TrySetBinding(keyChord, bindingID, saveAfter, context)
		context = context or (bindingID and CPAPI.GetBindingContextForAction(bindingID))
		if SetBinding(keyChord, bindingID, context) then
			return saveAfter;
		end
		ReportBindingError(keyChord, bindingID);
	end

	function CPAPI.SetBinding(keyChord, bindingID, saveAfter)
		if bindingID and not db('bindingOverlapEnable') then
			CPAPI.ClearBindingsForID(bindingID, false)
		end
		if TrySetBinding(keyChord, bindingID, saveAfter) then
			SaveBindings(GetCurrentBindingSet())
			return true;
		end
		return false;
	end

	function CPAPI.ClearBindingsForID(bindingID, saveAfter)
		if FORBIDDEN_TO_CLEAR[bindingID] then
			return false;
		end
		local context = CPAPI.GetBindingContextForAction(bindingID)
		for _, binding in ipairs(db.Gamepad:GetBindingKey(bindingID, true)) do
			TrySetBinding(binding, nil, false, context)
		end
		if saveAfter then
			SaveBindings(GetCurrentBindingSet())
		end
		return true;
	end

	-- GetBindingContextForAction: Retail has it, Classic doesn't.
	CPAPI.GetBindingContextForAction = C_KeyBindings and C_KeyBindings.GetBindingContextForAction or nop;
end

---------------------------------------------------------------
-- Internal helpers (db-dependent)
---------------------------------------------------------------

function CPAPI.IsButtonValidForBinding(button)
	return db('bindingAllowSticks') or (not button:match('PAD.STICK.+'))
end

function CPAPI.GetKeyChordParts(keyChord)
	return
		--[[buttonID]] (keyChord:match('PAD.+')),
		--[[modifier]] (keyChord:gsub('PAD.+', ''));
end

function CPAPI.IsTutorialComplete(tutorialID)
	return CPAPI.Tutorial:IsFlagSet(tutorialID, db('tutorialState'));
end

function CPAPI.SetTutorialComplete(tutorialID, state)
	return db('Settings/tutorialState', CPAPI.Tutorial:Combine(tutorialID, db('tutorialState'), state));
end

---------------------------------------------------------------
-- Enum wrappers
---------------------------------------------------------------
CPAPI.BOOKTYPE_PET     = not CPAPI.IsRetailVersion and BOOKTYPE_PET   or Enum.SpellBookSpellBank.Pet;
CPAPI.BOOKTYPE_SPELL   = not CPAPI.IsRetailVersion and BOOKTYPE_SPELL or Enum.SpellBookSpellBank.Player;
CPAPI.SKILLTYPE_PET    = not CPAPI.IsRetailVersion and 'PETACTION'    or nil;
CPAPI.SKILLTYPE_SPELL  = not CPAPI.IsRetailVersion and 'SPELL'        or Enum.SpellBookItemType.Spell;
CPAPI.SKILLTYPE_FLYOUT = not CPAPI.IsRetailVersion and 'FLYOUT'       or Enum.SpellBookItemType.Flyout;
