---------------------------------------------------------------
-- CombatGuard — centralized combat state observer
---------------------------------------------------------------
-- Provides a single source of truth for combat state queries
-- and notifies subscribers when combat starts/ends.
-- Owns the leave-combat delay logic previously duplicated in
-- Cursor.lua and Stack.lua.

local env, db = CPAPI.GetEnv(...);
---------------------------------------------------------------
local After = C_Timer.After;
local xpcall, CallErrorHandler = xpcall, CallErrorHandler;
local InCombatLockdown, UnitIsDead = InCombatLockdown, UnitIsDead;
---------------------------------------------------------------

---@class CombatGuard
local CombatGuard = CPAPI.CreateEventHandler({'Frame', '$parentCombatGuard', ConsolePort}, {});

Mixin(CombatGuard, CallbackRegistryMixin);
CallbackRegistryMixin.OnLoad(CombatGuard);
CombatGuard:GenerateCallbackEvents({"OnCombatStart", "OnCombatEnd"});

db:Register('CombatGuard', CombatGuard, true);
env.CombatGuard = CombatGuard;

---------------------------------------------------------------
-- State
---------------------------------------------------------------
local isLocked = false;
local isCombatPaused = false;

---------------------------------------------------------------
-- State queries
---------------------------------------------------------------
---@return boolean
function CombatGuard:IsLocked()
	return isLocked or InCombatLockdown();
end

---@return boolean
function CombatGuard:IsCombatPaused()
	return isCombatPaused;
end

---@return boolean
function CombatGuard:IsDisabled()
	return not db('UIenableCursor');
end

---------------------------------------------------------------
-- Subscriber management (compatibility wrappers)
---------------------------------------------------------------
-- callbacks = { OnCombatStart = fn, OnCombatEnd = fn }
-- If combat is already active, immediately fires OnCombatStart
---@param key any           subscriber identity key
---@param callbacks table   { OnCombatStart?: fun(), OnCombatEnd?: fun() }
function CombatGuard:Subscribe(key, callbacks)
	if not key or not callbacks then return end;

	if callbacks.OnCombatStart then
		self:RegisterCallback("OnCombatStart", callbacks.OnCombatStart, key);
	end
	if callbacks.OnCombatEnd then
		self:RegisterCallback("OnCombatEnd", callbacks.OnCombatEnd, key);
	end

	-- Late subscriber support: if already in combat, notify immediately
	if self:IsLocked() and callbacks.OnCombatStart then
		xpcall(callbacks.OnCombatStart, CallErrorHandler);
	end
end

---@param key any  subscriber identity key to remove
function CombatGuard:Unsubscribe(key)
	self:UnregisterCallback("OnCombatStart", key);
	self:UnregisterCallback("OnCombatEnd", key);
end

---------------------------------------------------------------
-- Events
---------------------------------------------------------------
function CombatGuard:PLAYER_REGEN_DISABLED()
	isLocked = true;
	-- Track if cursor was visible when combat started
	isCombatPaused = db.Cursor and db.Cursor:IsShown() or false;
	self:TriggerEvent("OnCombatStart");
end

function CombatGuard:PLAYER_REGEN_ENABLED()
	-- Delay is doubled if player is dead (matches existing Cursor.lua behavior)
	local delay = db('UIleaveCombatDelay') * (UnitIsDead('player') and 2 or 1);

	After(delay, function()
		if not InCombatLockdown() then
			isLocked = false;
			isCombatPaused = false;
			CombatGuard:TriggerEvent("OnCombatEnd");
		end
	end)
end

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------
function CombatGuard:OnDataLoaded()
	local events = {'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED'};
	if FrameUtil and FrameUtil.RegisterFrameForEvents then
		FrameUtil.RegisterFrameForEvents(self, events);
	else
		self:RegisterEvent('PLAYER_REGEN_DISABLED');
		self:RegisterEvent('PLAYER_REGEN_ENABLED');
	end
	return CPAPI.BurnAfterReading;
end
