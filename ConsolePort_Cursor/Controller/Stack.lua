---------------------------------------------------------------
-- Stack functionality for UI cursor
---------------------------------------------------------------
-- Keeps a stack of frames to control with the D-pad when they
-- are visible on screen. See Cursor.lua.
--
-- ConsolePortNode limitations/quirks/stuff/Not a fan:
--
-- 1. No frame-level filtering: Node() scans every frame it
--    receives. It cannot decide "skip this entire frame."
--    `ScrubCache` only removes individual nodes behind RECTS,
--    not whole frames. filter frames before passing to Node(),
--    which is what `filterByZOrder()` does could fix that.
--
-- 2. `ScrubCache` only checks center points: a node is removed
--    only if its center falls inside a higher-level RECT.
--    Nodes at the edge of an occluded frame can survive even
--    when visually hidden. It Would require `ScrubCache` to
--    check full node bounds, not just center.
--
-- 3. `RECTS` only populated by mouse-enabled frames: if the
--    occluding frame is not, it won't produce a RECT entry,
--    so `ScrubCache` can't use it for occlusion.
--    CacheRect would need to also cache non-mouse-enabled
--    frames that are visually opaque, though not sure if thats ideal.
--
-- 4. No same-level occlusion: CanLevelsIntersect requires
--    strict level1 < level2, so two frames at the same
--    absolute level never occlude each other in `ScrubCache`.
--    `CanLevelsIntersect` would need <= and a tiebreaker
--    (e.g. frame area or show order).
--
-- 5. `RECTS` ordering is insert-time dependent: GetRectLevelIndex
--    inserts by descending level, but same-level rects have no
--    guaranteed order. Would need to stable sort by area or pointer.
--
-- 6. `BOUNDS` stale after resolution changes mid-scan: `BOUNDS`
--    updates via `UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED`, but
--    if a scan is already in progress when the event fires,
--    `BOUNDS.z` (UIParent effective scale) used by GetCenterScaled
--    and `GetHitRectScaled` may be outdated for that pass.
--    Woudl require to re-read `BOUNDS` at the start of each scan or defer
--    scans until the next frame after a resize event.
--
-- 7. No hit rect inset clamping, `GetHitRectScaled` subtracts
--    insets from width/height without clamping, so frames with
--    insets larger than their dimensions produce negative sizes.
--    Probably clamp (w-r) and (h-t) to a minimum of 0 to fix it.
--
-- 8. Scan recursion depth is unbounded: `Scan()` recurses via
--    `GetChildren()` through the entire frame hierarchy. Deeply
--    nested UI trees (e.g. large addon frames) can approach
--    Lua's stack limit.
--    Scan() from recursion to an iterative stack to avoid hitting
--    limit on deeply nested frames.
--
-- 9. CACHE/RECTS are global singletons: `ScanLocal()` calls
--    `ClearCache()` which wipes the global CACHE/RECTS, so any
--    concurrent or nested scan (e.g. `ScanLocal` inside a
--    navigation callback) destroys the previous scan results.
--
-- 10. `GetPriorityCandidate` breaks on first priority node, if
--     multiple nodes have `nodepriority`, only the first one
--     encountered wins regardless of its priority value or
--     distance. Maybe compare priority values numerically and
--     use distance as a tiebreaker in equal priorities.
--
-- 11. `NavigateToArbitraryCandidate` skips clipping check on
--     old. `IsCandidate` calls `IsDrawn` without the super node,
--     so scroll-clipping checks are skipped. A node scrolled
--     out of view inside a ScrollFrame still can be selected.
--     Fix would be to pass the cached super to IsDrawn, or re-derive it.

local env, db, _ = CPAPI.GetEnv(...)
---------------------------------------------------------------
local After = C_Timer.After;
local pairs, next, unravel = pairs, next, db.table.unravel;

---@type boolean|nil Whether the cursor system is enabled via settings
local isEnabled;
---@type boolean|nil Whether the cursor is blocked by an obstructor
local isObstructed;
---------------------------------------------------------------
---------------------------------------------------------------
-- Z-order filtering helpers
-- Prevents the cursor from navigating to nodes on frames that
-- are visually behind other frames (e.g. frames behind the map).
-- Mirrors ConsolePortNode's LEVELS table for consistent comparison.
---------------------------------------------------------------
---@type table<string, number> Maps WoW frame strata names to numeric offsets for z-order comparison
local STRATA_LEVELS = {
	BACKGROUND = 0, LOW = 10000, MEDIUM = 20000, HIGH = 30000,
	DIALOG = 40000, FULLSCREEN = 50000, FULLSCREEN_DIALOG = 60000, TOOLTIP = 70000,
};

---Returns a single comparable number for z-order: strata offset + frame level
---@param frame Frame
---@return number absLevel
local function getAbsLevel(frame)
	return (STRATA_LEVELS[frame:GetFrameStrata()] or 0) + frame:GetFrameLevel()
end

---Normalize frame bounds to screen-space so frames at different scales
---can be compared (e.g. a addon's frame vs a full-size map panel)
---@param frame Frame
---@return number|nil left
---@return number|nil bottom
---@return number|nil right
---@return number|nil top
local function getNormalizedRect(frame)
	local x, y, w, h = frame:GetRect()
	if not x then return end
	local s = frame:GetEffectiveScale()
	return x * s, y * s, (x + w) * s, (y + h) * s
end

---Returns true if the inner rect is fully contained within the outer rect
---@param iL number Inner left
---@param iB number Inner bottom
---@param iR number Inner right
---@param iT number Inner top
---@param oL number Outer left
---@param oB number Outer bottom
---@param oR number Outer right
---@param oT number Outer top
---@return boolean
local function isFullyOccluded(iL, iB, iR, iT, oL, oB, oR, oT)
	return oL <= iL and oB <= iB and oR >= iR and oT >= iT
end

---------------------------------------------------------------
---@class Stack : Frame, EventHandler
---@field Registry table<string, table<string, boolean>>
local Stack = db:Register('Stack', CPAPI.CreateEventHandler({'Frame', '$parentUIStackHandler', ConsolePort}, {
}, {
	Registry = {};
}), true);
local GetPoint, IsAnchoringRestricted, IsVisible = Stack.GetPoint, Stack.IsAnchoringRestricted, Stack.IsVisible;

---------------------------------------------------------------
---Resolves a frame reference (widget or global name) to a Frame widget
---@param frame Frame|string
---@return Frame|nil widget
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
---@param ... any
function Stack:LockCore(...)        env.CombatGuard:IsLocked()  end
---@return boolean
function Stack:IsCoreLocked()       return env.CombatGuard:IsLocked() end
---@return boolean|nil
function Stack:IsCursorObstructed() return isObstructed end

---------------------------------------------------------------
-- Visibility tracking
---------------------------------------------------------------
do local frames, visible, buffer, hooks, forbidden, obstructors = {}, {}, {}, {}, {}, {};
	-- dirty flag: set true whenever the visible set changes (frame shown/hidden/removed).
	-- Cursor:OnUpdate checks this to know when a full UI rescan is needed.
	local dirty = true;

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
				dirty = true;
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

	---Registers a frame into the cursor stack, hooks Show/Hide, marks as pass-through
	---@param frame Frame|string Frame widget or global name
	---@return boolean|nil success True if the frame was added
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

	---Forces a visibility re-check on a tracked frame and triggers update if changed
	---@param frame Frame
	function Stack:Flush(frame)
		if not frames[frame] then return end;
		local wasVisible = visible[frame];
		updateVisible(frame)
		if wasVisible ~= visible[frame] then
			dirty = true;
			self:UpdateFrames()
		end
	end

	---Loads and registers frames from the saved registry for a given addon
	---@param name string Addon name
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

	---Removes a frame from the cursor stack and clears its pass-through attribute
	---@param frame Frame|string
	function Stack:RemoveFrame(frame)
		local widget = GetFrameWidget(frame)
		if widget then
			if visible[widget] then
				dirty = true;
			end
			visible[widget] = nil;
			frames[widget]  = nil;
			env.NodeAttr.SetPassThrough(widget, nil)
		end
	end

	---Permanently forbids a frame from being added to the stack
	---@param frame Frame|string
	function Stack:ForbidFrame(frame)
		local widget = GetFrameWidget(frame)
		if frames[widget] then
			forbidden[widget] = true;
			self:RemoveFrame(widget)
		end
	end

	---Removes the forbidden status from a frame and re-adds it to the stack
	---@param frame Frame
	function Stack:UnforbidFrame(frame)
		if forbidden[frame] then
			self:AddFrame(frame)
			forbidden[frame] = nil
		end
	end

	---Sets or clears a named obstructor that blocks cursor operation
	---@param idx any Obstructor identifier
	---@param state boolean|nil True to obstruct, nil/false to clear
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

	---Reads the UIenableCursor setting and disables cursor if off
	function Stack:ToggleCore()
		isEnabled = db('UIenableCursor');
		if not isEnabled then
			db.Cursor:OnStackChanged(false)
		end
	end

	---Triggers frame tracker update and notifies cursor of stack changes next frame
	function Stack:UpdateFrames()
		if env.CombatGuard:IsLocked() or isObstructed then return end
		self:UpdateFrameTracker()
		RunNextFrame(function()
			if not env.CombatGuard:IsLocked() then
				db.Cursor:OnStackChanged(not not next(visible))
			end
		end)
	end

	---@alias FilterEntry {frame: Frame, level: number, l: number, b: number, r: number, t: number, area: number}

	---@type FilterEntry[]
	local filterResult = {}
	-- Removes frames that are visually behind other frames before
	-- passing them to the Node scanner. This is a pre-filter that
	-- complements Node's per-node ScrubCache (which handles partial
	-- overlap within scanned frames). Without this, opening e.g.
	-- the map over the an addon's bank would still scan all bank item nodes.
	local function filterByZOrder()
		wipe(filterResult)
		local count = 0
		for frame in pairs(visible) do
			local l, b, r, t = getNormalizedRect(frame)
			if l then
				count = count + 1
				filterResult[count] = {
					frame = frame,
					level = getAbsLevel(frame),
					l = l, b = b, r = r, t = t,
					area = (r - l) * (t - b),
				}
			end
		end
		if count <= 1 then return end
		-- Sort descending: higher z-order first, then larger area first.
		-- Area tiebreaker handles same-strata/same-level cases where a
		-- large panel (map) should occlude smaller frames (bag slots).
		table.sort(filterResult, function(a, b)
			if a.level ~= b.level then return a.level > b.level end
			if a.area ~= b.area then return a.area > b.area end
			return tostring(a.frame) > tostring(b.frame)
		end)
		-- Walk backwards: for each frame, check if any earlier (higher
		-- priority) frame covers it. Remove if fully occluded or if the
		-- frame's center point falls inside a higher-priority frame.
		for i = count, 1, -1 do
			local fi = filterResult[i]
			local cx = (fi.l + fi.r) * 0.5 -- center X of the candidate frame
			local cy = (fi.b + fi.t) * 0.5 -- center Y of the candidate frame
			for j = 1, i - 1 do -- iterate over all higher-priority frames
				local fj = filterResult[j] -- grab the higher-priority frame entry
				if isFullyOccluded(fi.l, fi.b, fi.r, fi.t, fj.l, fj.b, fj.r, fj.t) -- check if completely covered
				or (cx >= fj.l and cx <= fj.r and cy >= fj.b and cy <= fj.t) then -- or center point is inside the higher frame
					tremove(filterResult, i) -- remove the occluded frame from results
					count = count - 1
					break -- no need to check further, already occluded
				end
			end
		end
	end

	---Iterates over all visible cursor frames (unfiltered)
	---@return fun(t: table<Frame, true>, k: Frame|nil): Frame|nil, true|nil
	---@return table<Frame, true>
	function Stack:IterateVisibleCursorFrames()
		return pairs(visible)
	end

	---Returns visible cursor frames filtered by z-order occlusion
	---@return Frame ... Varargs of non-occluded visible frames
	function Stack:GetVisibleCursorFrames()
		filterByZOrder()
		if #filterResult > 0 then
			local frames = {}
			for i = 1, #filterResult do
				frames[i] = filterResult[i].frame
			end
			return unpack(frames)
		end
		-- Safety net: if filtering produced nothing, fall back to all visible
		return unravel(visible)
	end

	---Returns true if the visible set has changed since last ClearDirty
	---@return boolean
	function Stack:IsDirty()
		return dirty;
	end

	---Resets the dirty flag after a scan has consumed it
	function Stack:ClearDirty()
		dirty = false;
	end

	---Checks if one or more frames are currently visible to the cursor
	---@param frame Frame|nil
	---@param ... Frame
	---@return boolean ...
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

---Returns or creates the registry set for a given addon/category name
---@param name string
---@return table<string, boolean>
function Stack:GetRegistrySet(name)
	self.Registry[name] = self.Registry[name] or {};
	return self.Registry[name];
end

---Registers a frame name into a set.
---If the entry doesn't exist, defaults to (state ?? true).
---If state is provided, always overwrites.
---@param set string Registry set name
---@param name string|nil Frame name
---@param state boolean|nil Enabled state
---@return boolean|nil enabled
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

---Marks a frame as disabled (false) or removes it (wipe=true).
---Returns true if the entry existed.
---@param set string Registry set name
---@param name string|nil Frame name
---@param wipe boolean|nil If true, remove entirely; if false, mark disabled
---@return boolean|nil existed
function Stack:TryUnregisterFrame(set, name, wipe)
	if not name then return end
	local stack = self:GetRegistrySet(set)
	if stack[name] == nil then return end
	stack[name] = wipe and nil or false;
	return true;
end

---Initializes the stack on data load: loads registry, registers standalone frames,
---hooks addon loading, subscribes to combat guard events.
---@return function BurnAfterReading Signals this should only run once
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
-- Discovers new frames that should be in the cursor stack.
-- Three sources feed into this:
--   1. FrameManagers: (UIPanelWindows, UISpecialFrames, UIMenus)
--        periodically scanned via CheckSpecialFrames
--   2. FramePipelines: (ShowUIPanel, StaticPopupSpecial_Show, etc.)
--        hooked so new frames are caught as they appear
--   3. Watchers: frames referenced by name that don't exist yet,
--        retried each UpdateFrameTracker until the widget is created
--   There might be a smarter approach to squeeze a bit of perf.
---------------------------------------------------------------
do  local specialFrames, poolFrames, watchers = {}, {}, {};

	-- Try to register and add a frame from a FrameManager.
	-- specialFrames tracks what we've already seen to avoid re-processing.
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

	-- Iterate all FrameManagers and pick up any frames we haven't seen.
	-- Managers can be associative tables (keys are frame names) or
	-- indexed arrays (values are frame names).
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

	-- Hook callback for FramePipelines with boolean values (global functions).
	-- Catches frames as they pass through.
	local function CatchNewFrame(frame)
		local widget = GetFrameWidget(frame)
		if widget and not Stack:IsFrameVisibleToCursor(widget) then
			if Stack:TryRegisterFrame(_, widget:GetName()) then
				Stack:AddFrame(widget)
			end
		end
	end

	-- Hook callback for FramePipelines with string values (object methods).
	-- Also used for menu frames. poolFrames prevents re-adding the same
	-- pooled frame multiple times.
	local function CatchPoolFrame(frame)
		if not Stack:IsFrameVisibleToCursor(frame) then
			if not poolFrames[frame] then
				Stack:AddFrame(frame)
				poolFrames[frame] = true;
				return true;
			end
		end
	end

	-- Hook all FramePipelines at load time so new frames are caught
	-- as they appear through.
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

	-- Hook the modern Menu system (if available) to catch context menus
	-- and their dynamically acquired sub-frames.
	-- TODO: This needs updating to catch and focus?
	--         Not quite sure how to go about it
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

	---Called by UpdateFrames to pick up new frames from managers
	---and retry any watchers (frames that didn't exist yet when
	---first referenced by name).
	function Stack:UpdateFrameTracker()
		if self.OnDataLoaded then return end;
		CheckSpecialFrames(self)
		for frame in pairs(watchers) do
			if self:AddFrame(frame) then
				watchers[frame] = nil;
			end
		end
	end

	---Queue a frame name for later retry if the widget doesn't exist yet.
	---@param frame string Frame name to watch for
	function Stack:AddFrameWatcher(frame)
		watchers[frame] = true;
	end
end
