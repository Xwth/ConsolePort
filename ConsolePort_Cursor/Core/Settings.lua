---------------------------------------------------------------
-- Settings — cached settings accessor
---------------------------------------------------------------
-- Provides a centralized, lazily-cached accessor for cursor
-- button bindings and configuration values. Cache entries are
-- invalidated via db callbacks when settings change.

local env, db = CPAPI.GetEnv(...);
---------------------------------------------------------------

---@class CursorSettings
local Settings = {};
env.Settings = Settings;

---------------------------------------------------------------
-- Button action → db key mapping
---------------------------------------------------------------
local ButtonKeys = {
	LeftClick  = 'Settings/UICursorLeftClick';
	RightClick = 'Settings/UICursorRightClick';
	Special    = 'Settings/UICursorSpecial';
	Cancel     = 'Settings/UICursorCancel';
};

---------------------------------------------------------------
-- Scalar setting → db key mapping
---------------------------------------------------------------
local ScalarKeys = {
	CommandModifier  = 'Settings/UImodifierCommands';
	NudgeModifier    = 'Settings/UImodifierNudge';
	RepeatDelay      = 'Settings/UIholdRepeatDelay';
	RepeatDelayFirst = 'Settings/UIholdRepeatDelayFirst';
	RepeatDisabled   = 'Settings/UIholdRepeatDisable';
	LeaveCombatDelay = 'Settings/UIleaveCombatDelay';
};

---------------------------------------------------------------
-- Lazy cache
---------------------------------------------------------------
local cache = {};

local function Get(cacheKey, dbKey)
	if cache[cacheKey] == nil then
		cache[cacheKey] = db(dbKey);
	end
	return cache[cacheKey];
end

---------------------------------------------------------------
-- Button accessor
---------------------------------------------------------------
function Settings:GetButton(action)
	local dbKey = ButtonKeys[action];
	if not dbKey then return nil end;
	return Get(action, dbKey);
end

---------------------------------------------------------------
-- Scalar accessors
---------------------------------------------------------------
function Settings:GetCommandModifier()
	return Get('CommandModifier', ScalarKeys.CommandModifier);
end

function Settings:GetNudgeModifier()
	return Get('NudgeModifier', ScalarKeys.NudgeModifier);
end

function Settings:GetRepeatDelay()
	return Get('RepeatDelay', ScalarKeys.RepeatDelay);
end

function Settings:GetRepeatDelayFirst()
	return Get('RepeatDelayFirst', ScalarKeys.RepeatDelayFirst);
end

function Settings:IsRepeatDisabled()
	return Get('RepeatDisabled', ScalarKeys.RepeatDisabled);
end

function Settings:GetLeaveCombatDelay()
	return Get('LeaveCombatDelay', ScalarKeys.LeaveCombatDelay);
end

---------------------------------------------------------------
-- Cache invalidation via db callbacks
---------------------------------------------------------------
for cacheKey, dbKey in pairs(ButtonKeys) do
	db:RegisterSafeCallback(dbKey, function()
		cache[cacheKey] = nil;
	end)
end

for cacheKey, dbKey in pairs(ScalarKeys) do
	db:RegisterSafeCallback(dbKey, function()
		cache[cacheKey] = nil;
	end)
end
