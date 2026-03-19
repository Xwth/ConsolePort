---------------------------------------------------------------
-- Stack functionality for UI cursor
---------------------------------------------------------------
-- Keeps a stack of frames to control with the D-pad when they
-- are visible on screen. See Cursor.lua.

local env, db, _ = CPAPI.GetEnv(...)
---------------------------------------------------------------
local After = C_Timer.After;
local pairs, next, unravel = pairs, next, db.table.unravel;
local isEnabled, isObstructed;
---------------------------------------------------------------
local Stack = db:Register('Stack', CPAPI.CreateEventHandler({'Frame', '$parentUIStackHandler', ConsolePort}, {
}, {
	Registry = {};
}), true);
local GetPoint, IsAnchoringRestricted, IsVisible = Stack.GetPoint, Stack.IsAnchoringRestricted, Stack.IsVisible;

---------------------------------------------------------------
local function GetFrameWidget(frame)
	if C_Widget.IsFrameWidget(frame) then
		return frame;
	elseif type(frame) == 'string' and C_Widget.IsFrameWidget(_G[frame]) then
		return _G[frame];
	end
end

---------------------------------------------------------------
-- Externals
---------------------------------------------------------------
function Stack:LockCore(...)        env.CombatGuard:IsLocked()  end
function Stack:IsCoreLocked()       return env.CombatGuard:IsLocked() end
function Stack:IsCursorObstructed() return isObstructed end

---------------------------------------------------------------
-- Visibility tracking
---------------------------------------------------------------
do local frames, visible, buffer, hooks, forbidden, obstructors = {}, {}, {}, {}, {}, {};

	local function updateVisible(self)
		visible[self] = (
			not IsAnchoringRestricted(self)
			and GetPoint(self)
			and IsVisible(self)
		) or nil;
	end

	local function updateOnBuffer(self)
		buffer[self] = true;
		After(0, function()
			updateVisible(self)
			buffer[self] = nil;
			if not next(buffer) then
				Stack:UpdateFrames()
			end
		end)
	end

	local function showHook(self)
		if isEnabled and frames[self] then
			updateOnBuffer(self)
		end
	end

	local function hideHook(self, force)
		if isEnabled and frames[self] and (force or visible[self]) then
			updateOnBuffer(self)
		end
	end

	local function addHook(widget, script, hook)
		local mt = getmetatable(widget)
		local ix = mt and mt.__index;
		local fn = type(ix) == 'table' and ix[script];
		if ( type(fn) == 'function' and not hooks[fn] ) then
			hooksecurefunc(ix, script, hook)
			hooks[fn] = true;
		elseif ( widget.HookScript ) then
			widget:HookScript(('On%s'):format(script), hook)
		end
	end

	hooks[CPAPI.Index(UIParent).Show] = true
	hooks[CPAPI.Index(UIParent).Hide] = true

	function Stack:AddFrame(frame)
		local widget = GetFrameWidget(frame)
		if widget then
			if not forbidden[widget] then
				if not frames[widget] then
					addHook(widget, 'Show', showHook)
					addHook(widget, 'Hide', hideHook)
				end
				frames[widget] = true;
				env.NodeAttr.SetPassThrough(widget, true)
				updateOnBuffer(widget)
			end
			return true;
		else
			self:AddFrameWatcher(frame)
		end
	end

	function Stack:Flush(frame)
		if not frames[frame] then return end;
		local wasVisible = visible[frame];
		updateVisible(frame)
		if wasVisible ~= visible[frame] then
			self:UpdateFrames()
		end
	end

	function Stack:LoadAddonFrames(name)
		local addonFrames = db('Stack/Registry/'..name)
		if (type(addonFrames) == 'table') then
			for frame, enabled in pairs(addonFrames) do
				if enabled then
					self:AddFrame(frame)
				end
			end
		end
	end

	function Stack:RemoveFrame(frame)
		local widget = GetFrameWidget(frame)
		if widget then
			visible[widget] = nil;
			frames[widget]  = nil;
			env.NodeAttr.SetPassThrough(widget, nil)
		end
	end

	function Stack:ForbidFrame(frame)
		local widget = GetFrameWidget(frame)
		if frames[widget] then
			forbidden[widget] = true;
			self:RemoveFrame(widget)
		end
	end

	function Stack:UnforbidFrame(frame)
		if forbidden[frame] then
			self:AddFrame(frame)
			forbidden[frame] = nil
		end
	end

	function Stack:SetCursorObstructor(idx, state)
		if not idx then return end
		obstructors[idx] = state or nil;
		isObstructed = not not next(obstructors);
		if isObstructed then
			db.Cursor:OnStackChanged(false)
		else
			self:UpdateFrames()
		end
	end

	function Stack:ToggleCore()
		isEnabled = db('UIenableCursor');
		if not isEnabled then
			db.Cursor:OnStackChanged(false)
		end
	end

	function Stack:UpdateFrames()
		if env.CombatGuard:IsLocked() or isObstructed then return end
		self:UpdateFrameTracker()
		RunNextFrame(function()
			if not env.CombatGuard:IsLocked() then
				db.Cursor:OnStackChanged(not not next(visible))
			end
		end)
	end

	function Stack:IterateVisibleCursorFrames()
		return pairs(visible)
	end

	function Stack:GetVisibleCursorFrames()
		return unravel(visible)
	end

	function Stack:IsFrameVisibleToCursor(frame, ...)
		if frame then
			return visible[frame] or false, self:IsFrameVisibleToCursor(...)
		end
	end
end


---------------------------------------------------------------
-- Registry persistence
---------------------------------------------------------------
db:Save('Stack/Registry', 'ConsolePortUIStack')

function Stack:GetRegistrySet(name)
	self.Registry[name] = self.Registry[name] or {};
	return self.Registry[name];
end

-- Registers a frame name into a set.
-- If the entry doesn't exist, defaults to (state ?? true).
-- If state is provided, always overwrites.
function Stack:TryRegisterFrame(set, name, state)
	if not name then return end
	local stack = self:GetRegistrySet(set)
	if stack[name] == nil then
		stack[name] = (state == nil) or state;
	elseif state ~= nil then
		stack[name] = state;
	end
	return stack[name];
end

-- Marks a frame as disabled (false) or removes it (wipe=true).
-- Returns true if the entry existed.
function Stack:TryUnregisterFrame(set, name, wipe)
	if not name then return end
	local stack = self:GetRegistrySet(set)
	if stack[name] == nil then return end
	stack[name] = wipe and nil or false;
	return true;
end

function Stack:OnDataLoaded()
	db:Load('Stack/Registry', 'ConsolePortUIStack')

	for i, frame in ipairs(env.StandaloneFrameStack) do
		self:TryRegisterFrame(_, frame)
	end

	self:ToggleCore()

	for addon in pairs(self.Registry) do
		if CPAPI.IsAddOnLoaded(addon) then
			self:LoadAddonFrames(addon)
		end
	end

	self:RegisterEvent('ADDON_LOADED')
	self.ADDON_LOADED = function(self, name)
		self:LoadAddonFrames(name)
		self:UpdateFrames()
	end;

	db:RegisterSafeCallback('Settings/UIenableCursor', self.ToggleCore, self)
	db:RegisterSafeCallback('Settings/UIshowOnDemand', self.ToggleCore, self)

	env.CombatGuard:Subscribe('Stack', {
		OnCombatStart = function()
			db.Cursor:OnStackChanged(false)
			-- isLocked is now managed by CombatGuard
		end,
		OnCombatEnd = function()
			Stack:UpdateFrames()
		end,
	})

	return CPAPI.BurnAfterReading;
end

---------------------------------------------------------------
-- Frame watching
---------------------------------------------------------------
do  local specialFrames, poolFrames, watchers = {}, {}, {};

	local function TryAddSpecialFrame(self, frame)
		if specialFrames[frame] then return end;
		if self:TryRegisterFrame(_, frame) then
			if self:AddFrame(frame) then
				specialFrames[frame] = true;
			end
		elseif GetFrameWidget(frame) then
			specialFrames[frame] = true;
		end
	end

	local function CheckSpecialFrames(self)
		for manager, isAssociative in pairs(env.FrameManagers) do
			if isAssociative then
				for frame in pairs(manager) do
					TryAddSpecialFrame(self, frame)
				end
			else
				for _, frame in ipairs(manager) do
					TryAddSpecialFrame(self, frame)
				end
			end
		end
	end

	local function CatchNewFrame(frame)
		local widget = GetFrameWidget(frame)
		if widget and not Stack:IsFrameVisibleToCursor(widget) then
			if Stack:TryRegisterFrame(_, widget:GetName()) then
				Stack:AddFrame(widget)
			end
		end
	end

	local function CatchPoolFrame(frame)
		if not Stack:IsFrameVisibleToCursor(frame) then
			if not poolFrames[frame] then
				Stack:AddFrame(frame)
				poolFrames[frame] = true;
				return true;
			end
		end
	end

	for name, method in pairs(env.FramePipelines) do
		if type(method) == 'string' then
			local object = _G[name];
			if object then
				hooksecurefunc(object, method, CatchPoolFrame)
			end
		elseif type(method) == 'boolean' then
			hooksecurefunc(name, CatchNewFrame)
		end
	end

	if (_G.Menu and _G.Menu.GetManager) then
		local menu = _G.Menu;
		local mgr  = menu.GetManager();
		local function CatchOpenMenu()
			local openMenu = mgr:GetOpenMenu()
			if CatchPoolFrame(openMenu) then
				for _, tag in ipairs(menu.GetOpenMenuTags()) do
					menu.ModifyMenu(tag, function(_, description)
						description:AddMenuAcquiredCallback(CatchPoolFrame)
					end)
				end
			elseif openMenu then
				Stack:Flush(openMenu)
			end
		end
		hooksecurefunc(mgr, 'OpenMenu',        CatchOpenMenu)
		hooksecurefunc(mgr, 'OpenContextMenu', CatchOpenMenu)
	end

	function Stack:UpdateFrameTracker()
		if self.OnDataLoaded then return end;
		CheckSpecialFrames(self)
		for frame in pairs(watchers) do
			if self:AddFrame(frame) then
				watchers[frame] = nil;
			end
		end
	end

	function Stack:AddFrameWatcher(frame)
		watchers[frame] = true;
	end
end
