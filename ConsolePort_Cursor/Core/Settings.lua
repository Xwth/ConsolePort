---------------------------------------------------------------
-- Settings — cached settings accessor
---------------------------------------------------------------
-- Provides a centralized, lazily-cached accessor for cursor
-- button bindings and configuration values. Cache entries are
-- invalidated via db callbacks when settings change.

local env, db = CPAPI.GetEnv(...);
local pairs = pairs;
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
	CommandModifier          = 'Settings/UImodifierCommands';
	NudgeModifier            = 'Settings/UImodifierNudge';
	RepeatDelay              = 'Settings/UIholdRepeatDelay';
	RepeatDelayFirst         = 'Settings/UIholdRepeatDelayFirst';
	RepeatDisabled           = 'Settings/UIholdRepeatDisable';
	LeaveCombatDelay         = 'Settings/UIleaveCombatDelay';
	ShoulderMenuEnable       = 'Settings/UIshoulderMenuEnable';
	ShoulderMenuSilent       = 'Settings/UIshoulderMenuSilent';
	ShoulderMenuSwapDirection = 'Settings/UIshoulderMenuSwapDirection';
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
---@param action string  button action name ('LeftClick', 'RightClick', 'Special', 'Cancel')
---@return any|nil       bound button value, or nil if action is unknown
function Settings:GetButton(action)
	local dbKey = ButtonKeys[action];
	if not dbKey then return nil end;
	return Get(action, dbKey);
end

---------------------------------------------------------------
-- Scalar accessors
---------------------------------------------------------------
---@return string  modifier key name for command mode
function Settings:GetCommandModifier()
	return Get('CommandModifier', ScalarKeys.CommandModifier);
end

---@return string  modifier key name for nudge mode
function Settings:GetNudgeModifier()
	return Get('NudgeModifier', ScalarKeys.NudgeModifier);
end

---@return number  hold-repeat delay in seconds
function Settings:GetRepeatDelay()
	return Get('RepeatDelay', ScalarKeys.RepeatDelay);
end

---@return number  initial hold-repeat delay in seconds
function Settings:GetRepeatDelayFirst()
	return Get('RepeatDelayFirst', ScalarKeys.RepeatDelayFirst);
end

---@return boolean  true if hold-repeat is disabled
function Settings:IsRepeatDisabled()
	return Get('RepeatDisabled', ScalarKeys.RepeatDisabled);
end

---@return number  delay in seconds before leaving combat mode
function Settings:GetLeaveCombatDelay()
	return Get('LeaveCombatDelay', ScalarKeys.LeaveCombatDelay);
end

---@return boolean  true if shoulder menu navigation is enabled
function Settings:IsShoulderMenuEnabled()
	return Get('ShoulderMenuEnable', ScalarKeys.ShoulderMenuEnable);
end

---@return boolean  true if silent cycling mode is active
function Settings:IsShoulderMenuSilent()
	return Get('ShoulderMenuSilent', ScalarKeys.ShoulderMenuSilent);
end

---@return boolean  true if shoulder button direction is swapped
function Settings:IsShoulderMenuSwapDirection()
	return Get('ShoulderMenuSwapDirection', ScalarKeys.ShoulderMenuSwapDirection);
end

---------------------------------------------------------------
-- Cache invalidation via db callbacks
---------------------------------------------------------------
for _, keyTable in ipairs({ ButtonKeys, ScalarKeys }) do
	for cacheKey, dbKey in pairs(keyTable) do
		db:RegisterSafeCallback(dbKey, function()
			cache[cacheKey] = nil;
		end)
	end
end
