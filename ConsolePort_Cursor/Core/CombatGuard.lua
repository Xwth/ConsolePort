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
local CombatGuard = CPAPI.CreateEventHandler({'Frame', '$parentCombatGuard', ConsolePort}, {
	'PLAYER_REGEN_DISABLED';
	'PLAYER_REGEN_ENABLED';
});

db:Register('CombatGuard', CombatGuard, true);
env.CombatGuard = CombatGuard;

---------------------------------------------------------------
-- State
---------------------------------------------------------------
local isLocked = false;
local isCombatPaused = false;
local subscribers = {};

---------------------------------------------------------------
-- State queries
---------------------------------------------------------------
function CombatGuard:IsLocked()
	return isLocked or InCombatLockdown();
end

function CombatGuard:IsCombatPaused()
	return isCombatPaused;
end

function CombatGuard:IsDisabled()
	return not db('UIenableCursor');
end

---------------------------------------------------------------
-- Subscriber management (observer pattern)
---------------------------------------------------------------
-- callbacks = { OnCombatStart = fn, OnCombatEnd = fn }
-- If combat is already active, immediately fires OnCombatStart
function CombatGuard:Subscribe(key, callbacks)
	if not key or not callbacks then return end;
	subscribers[key] = callbacks;

	-- Late subscriber support: if already in combat, notify immediately
	if self:IsLocked() and callbacks.OnCombatStart then
		xpcall(callbacks.OnCombatStart, CallErrorHandler);
	end
end

function CombatGuard:Unsubscribe(key)
	if key then
		subscribers[key] = nil;
	end
end

---------------------------------------------------------------
-- Internal: notify all subscribers
---------------------------------------------------------------
local function NotifySubscribers(callbackName)
	for key, callbacks in pairs(subscribers) do
		local fn = callbacks[callbackName];
		if fn then
			xpcall(fn, CallErrorHandler);
		end
	end
end

---------------------------------------------------------------
-- Events
---------------------------------------------------------------
function CombatGuard:PLAYER_REGEN_DISABLED()
	isLocked = true;
	-- Track if cursor was visible when combat started
	isCombatPaused = db.Cursor and db.Cursor:IsShown() or false;
	NotifySubscribers('OnCombatStart');
end

function CombatGuard:PLAYER_REGEN_ENABLED()
	-- Delay is doubled if player is dead (matches existing Cursor.lua behavior)
	local delay = db('UIleaveCombatDelay') * (UnitIsDead('player') and 2 or 1);

	After(delay, function()
		if not InCombatLockdown() then
			isLocked = false;
			isCombatPaused = false;
			NotifySubscribers('OnCombatEnd');
		end
	end)
end

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------
function CombatGuard:OnDataLoaded()
	return CPAPI.BurnAfterReading;
end
