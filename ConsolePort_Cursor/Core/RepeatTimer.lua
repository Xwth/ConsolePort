---------------------------------------------------------------
-- RepeatTimer — shared hold-repeat timer utility
---------------------------------------------------------------
-- Provides a reusable repeat-timer pattern for D-pad navigation
-- and scroll proxy buttons. Encapsulates the hold-repeat logic
-- that was previously duplicated in Cursor.lua and Scroll.lua.

local env = CPAPI.GetEnv(...);
---------------------------------------------------------------

---@class RepeatTimer
local RepeatTimer = {};
env.RepeatTimer = RepeatTimer;

---------------------------------------------------------------
-- RepeatTimer.Create(onTick)
-- Returns a timer object for hold-repeat behavior.
---------------------------------------------------------------
function RepeatTimer.Create(onTick)
	local timer = {
		elapsed   = 0;
		ticker    = 0;
		isRunning = false;
		onTick    = onTick;
	};

	function timer:Start(firstDelay, repeatDelay)
		self.elapsed   = -firstDelay;
		self.ticker    = repeatDelay;
		self.isRunning = true;
	end

	function timer:Stop()
		self.elapsed   = 0;
		self.isRunning = false;
	end

	function timer:OnUpdate(elapsed)
		if not self.isRunning then return end;
		self.elapsed = self.elapsed + elapsed;
		if self.elapsed >= self.ticker then
			self.elapsed = 0;
			if self.onTick then
				self.onTick();
			end
		end
	end

	return timer;
end

---------------------------------------------------------------
-- RepeatTimer.IsRepeatDisabled()
-- Delegates to env.Settings:IsRepeatDisabled()
---------------------------------------------------------------
function RepeatTimer.IsRepeatDisabled()
	return env.Settings:IsRepeatDisabled();
end

---------------------------------------------------------------
-- RepeatTimer.CreateDpadSet(inputProxy)
-- Returns a table of D-pad control entries matching the format:
--   { PADDUP, PADDDOWN, PADDLEFT, PADDRIGHT }
-- Each entry = { callback, initFn, clearFn, repeaterFn }
--
-- The init/clear/repeater functions operate on WoW widget frames
-- (self is a frame with SetAttribute, SetScript, Show, Hide).
-- They use env.Settings for delay values instead of raw db() calls.
---------------------------------------------------------------
function RepeatTimer.CreateDpadSet(inputProxy)
	-- The repeater function accumulates elapsed time on the frame
	-- and fires the UIControl action when the threshold is crossed.
	local DpadRepeater = function(self, elapsed)
		self.timer = self.timer + elapsed;
		if self.timer >= self:GetAttribute('ticker') and self.state then
			local func = self:GetAttribute(CPAPI.ActionTypeRelease);
			if func == 'UIControl' then
				self[func](self, self.state, self:GetAttribute('id'));
			end
			self.timer = 0;
		end
	end

	-- The init function sets up the frame for hold-repeat behavior.
	-- Reads delay values from env.Settings instead of raw db() calls.
	local DpadInit = function(self, dpadRepeater)
		if not RepeatTimer.IsRepeatDisabled() then
			self:SetAttribute('timer', -env.Settings:GetRepeatDelayFirst());
			self:SetAttribute('ticker', env.Settings:GetRepeatDelay());
			self:SetScript('OnUpdate', dpadRepeater);
			self:Show();
		end
	end

	-- The clear function stops the hold-repeat behavior.
	local DpadClear = function(self)
		self:SetScript('OnUpdate', nil);
		self:Hide();
	end

	-- Build the control entries for each D-pad direction.
	-- Each entry is { callback, initFn, clearFn, repeaterFn }
	return {
		PADDUP    = { GenerateClosure(inputProxy, 'PADDUP'),    DpadInit, DpadClear, DpadRepeater };
		PADDDOWN  = { GenerateClosure(inputProxy, 'PADDDOWN'),  DpadInit, DpadClear, DpadRepeater };
		PADDLEFT  = { GenerateClosure(inputProxy, 'PADDLEFT'),  DpadInit, DpadClear, DpadRepeater };
		PADDRIGHT = { GenerateClosure(inputProxy, 'PADDRIGHT'), DpadInit, DpadClear, DpadRepeater };
	};
end
