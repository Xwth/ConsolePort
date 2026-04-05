---------------------------------------------------------------
-- Interface cursor
---------------------------------------------------------------
-- Creates a cursor used to manage the interface with D-pad.
-- Operates recursively on frames and calculates appropriate
-- actions based on node priority and position on screen.
-- Leverages ConsolePortNode for interface scans.

local env, db, name = CPAPI.GetEnv(...);
local pairs, ipairs, format = pairs, ipairs, format;
local IsGamePadFreelookEnabled = IsGamePadFreelookEnabled;
local RunNextFrame = RunNextFrame;
local GenerateClosure = GenerateClosure;
---@class Cursor : Frame, EventHandler
---@field Cur NodeObject|nil Current cursor selection
---@field Old NodeObject|nil Previous cursor selection
---@field customAnchor boolean|nil Whether a custom anchor is active
---@field forceAnchor boolean|nil Whether the anchor is forced
---@field showAfterCombat boolean|nil Whether to re-show cursor after combat ends
---@field isCombatPaused boolean|nil Whether the cursor is paused due to combat
---@field BasicControls table|nil Cached D-pad control bindings
---@field DynamicControls table|nil Cached dynamic button bindings
---@field scrollers table|nil Active scroll override widgets
---@field onEnableCallback function|nil Deferred callback for post-combat enable
---@field hasScannedSinceNotDrawn boolean|nil Whether a rescan was attempted since node became undrawn
local Cursor, Node, Input, Stack, Scroll, Fade, Hooks =
	CPAPI.EventHandler(ConsolePortCursor, {
		'ADDON_ACTION_FORBIDDEN';
	}),
	env.Node,
	ConsolePortInputHandler,
	ConsolePortUIStackHandler,
	ConsolePortUIScrollHandler,
	db.Alpha.Fader, db.Hooks;

db:Register('Cursor', Cursor, true); env.Cursor = Cursor;
Cursor.InCombat = InCombatLockdown;

---------------------------------------------------------------
-- Events
---------------------------------------------------------------
---Handles the ADDON_ACTION_FORBIDDEN event for taint error reporting
---@param addOnName string The addon that triggered the forbidden action
---@param action string The forbidden action name
function Cursor:ADDON_ACTION_FORBIDDEN(addOnName, action)
	if ( addOnName == name ) then
		env.HandleTaintError(action)
	end
end

---------------------------------------------------------------
-- Cursor state
---------------------------------------------------------------
---Toggles the cursor on/off based on current state
function Cursor:OnClick()
	self:SetEnabled(not self:IsShown())
end

---Called when the frame stack changes; enables/disables cursor based on visible frames
---@param hasFrames boolean Whether any frames are visible in the stack
function Cursor:OnStackChanged(hasFrames)
	if db('UIshowOnDemand') then return end
	if not hasFrames then
		return self:Disable()
	end
	if IsGamePadFreelookEnabled() then
		return self:Enable()
	end
	-- Freelook may not be restored yet (e.g. ring just closed); retry next frame.
	RunNextFrame(function()
		if IsGamePadFreelookEnabled() then
			self:Enable()
		end
	end)
end

---Enables or disables the cursor
---@param enable boolean Whether to enable the cursor
function Cursor:SetEnabled(enable)
	return enable and self:Enable() or self:Disable()
end

---Enables the cursor if not in combat and not disabled
function Cursor:Enable()
	local inCombat, disabled = self:InCombat(), not db('UIenableCursor')
	if disabled then return end
	if inCombat or self.isCombatPaused then
		return self:ShowAfterCombat(true)
	end
	if not self:IsShown() then
		self:Show()
		self:SetBasicControls()
		return self:Refresh()
	end
end

---Disables the cursor, deferring hide if in combat
function Cursor:Disable()
	local inCombat = self:InCombat()
	if inCombat or self.isCombatPaused then
		self:ShowAfterCombat(false)
	end
	if self:IsShown() and not inCombat then
		self:Hide()
	end
end

---Called when the cursor frame is shown; sets scale and fires event
function Cursor:OnShow()
	self:SetScale(UIParent:GetEffectiveScale())
	db:TriggerEvent('OnCursorShow', self)
end

---Called when the cursor frame is hidden; resets state and fires event
function Cursor:OnHide()
	self.timer = 0
	self.hasScannedSinceNotDrawn = nil
	self:SetAlpha(1)
	self:SetFlashNextNode()
	self:Release()
	self.Blocker:Hide()
	db:TriggerEvent('OnCursorHide', self)
end

---Releases input bindings and clears node cache
function Cursor:Release()
	Node.ClearCache()
	self:OnLeaveNode(self:GetCurrentNode())
	self:SetHighlight()
	Input:Release(self)
end

---Returns whether the cursor is obstructed by combat, settings, or pause state
---@return boolean inCombat
---@return boolean disabled
---@return boolean|nil isCombatPaused
function Cursor:IsObstructed()
	return self:InCombat(), not db('UIenableCursor'), self.isCombatPaused;
end

---Sets whether the cursor should re-show after combat ends
---@param enabled boolean
function Cursor:ShowAfterCombat(enabled)
	self.showAfterCombat = enabled
end

---Scans the UI for navigable nodes using the current frame stack
function Cursor:ScanUI()
	if db('UIaccessUnlimited') then
		Node(unpack(env.UnlimitedFrameStack))
	else
		Node(Stack:GetVisibleCursorFrames())
	end
end

---Rescans the UI and attempts to select a node
---@return Frame|nil node The selected node, or nil
function Cursor:Refresh()
	self:OnLeaveNode(self:GetCurrentNode())
	self:ScanUI()
	return self:AttemptSelectNode()
end

---Sets the current node and prepares an enable callback if in combat
---@param node Frame|nil The frame to set as current
---@param assertNotMouse boolean|nil If true, require gamepad to be active
---@param forceEnable boolean|nil If true, bypass gamepad check
---@return boolean|nil success True if the node was set
function Cursor:SetCurrentNode(node, assertNotMouse, forceEnable)
	if not db('UIenableCursor') then return end
	if db('UIshowOnDemand') and not self:IsShown() then return end

	local isGamepadActive = IsGamePadFreelookEnabled()
	if not isGamepadActive and not forceEnable then return end

	local object = node and Node.ScanLocal(node)[1]
	if object and (not assertNotMouse or isGamepadActive or forceEnable) then
		self:SetOnEnableCallback(function(self, object)
			self:SetBasicControls()
			self:SetFlashNextNode()
			self:SetCurrent(object)
			self:SelectAndPosition(self:GetSelectParams(object, true, true))
			self:Chime()
		end, object)
		return true;
	end
end

---Sets the current node only if the cursor is currently shown
---@param ... any Arguments forwarded to SetCurrentNode
---@return boolean|nil success
function Cursor:SetCurrentNodeIfActive(...)
	if self:IsShown() then
		return self:SetCurrentNode(...)
	end
end

---Stores a callback to execute when the cursor is next enabled (post-combat)
---@param callback fun(self: Cursor, ...: any) The callback to defer
---@param ... any Additional arguments for the callback
function Cursor:SetOnEnableCallback(callback, ...)
	local inCombat, disabled, isCombatPaused = self:IsObstructed()
	if disabled then return end
	if not inCombat and not isCombatPaused then
		return callback(self, ...)
	end
	self.onEnableCallback = GenerateClosure(callback, self, ...)
end

---Per-frame update: rescans UI if current node is not drawn or stack is dirty
---@param elapsed number Time since last frame
function Cursor:OnUpdate(elapsed)
	if self:InCombat() then return end
	if not self:IsCurrentNodeDrawn() then
		if Stack:IsDirty() then
			Stack:ClearDirty()
			self:SetFlashNextNode()
			if not self:Refresh() then
				self:Hide()
			end
		elseif not self.hasScannedSinceNotDrawn then
			self.hasScannedSinceNotDrawn = true
			self:SetFlashNextNode()
			if not self:Refresh() then
				self:Hide()
			end
		end
	else
		self.hasScannedSinceNotDrawn = nil
		self:RefreshAnchor()
	end
end

---------------------------------------------------------------
-- Navigation and input
---------------------------------------------------------------
do
	local InputProxy = function(key, self, isDown)
		Cursor:Input(key, self, isDown)
	end

	-- D-pad controls are static; built once and reused via RepeatTimer.
	function Cursor:GetBasicControls()
		if not self.BasicControls then
			self.BasicControls = env.RepeatTimer.CreateDpadSet(InputProxy)
		end
		-- Prune any stale dynamic keys not in the D-pad set
		local DpadKeys = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true };
		for key in pairs(self.BasicControls) do
			if not DpadKeys[key] then
				self.BasicControls[key] = nil;
			end
		end
		self.DynamicControls = {
			env.Settings:GetButton('Special');
			env.Settings:GetButton('Cancel');
		};
		for _, key in ipairs(self.DynamicControls) do
			if not self.BasicControls[key] then
				self.BasicControls[key] = {GenerateClosure(InputProxy, key)}
			end
		end
		return self.BasicControls;
	end

	local SetDirectUIControl = function(self, button, settings)
		Input:SetCommand(button, self, true, 'LeftButton', 'UIControl', unpack(settings));
	end

	function Cursor:IsDynamicControl(key)
		return self.DynamicControls and tContains(self.DynamicControls, key)
	end

	function Cursor:SetBasicControls()
		Input:Release(self)
		for button, settings in pairs(self:GetBasicControls()) do
			SetDirectUIControl(self, button, settings);
		end
	end

	function Cursor:SetBasicControl(button)
		local settings = self:GetBasicControls()[button];
		if settings then
			SetDirectUIControl(self, button, settings);
		end
	end

	do local function ResetControls(self) self.BasicControls, self.DynamicControls = nil; end
		db:RegisterCallbacks(ResetControls, Cursor,
			'Settings/UICursorSpecial',
			'Settings/UICursorCancel',
			'Settings/UICursorLeftClick',
			'Settings/UICursorRightClick'
		);
	end

	local EmuClick = function(self, down)
		local node, emubtn, script = self.node, self.emubtn;
		if node then
			script =
				((down == true)  and 'OnMouseDown') or
				((down == false) and 'OnMouseUp');
			if script then
				env.ExecuteScript(node, script, emubtn, true)
			end
		end
	end

	local EmuClickInit = function(self, node, emubtn)
		self.node   = node;
		self.emubtn = emubtn;
	end

	local EmuClickClear = function(self)
		self.node   = nil;
		self.emubtn = nil;
	end

	function Cursor:GetEmuClick(node, button)
		return button, 'UIOnMouse', EmuClick, EmuClickInit, EmuClickClear, node, button;
	end
end

function Cursor:ReverseScanUI(node, key, target, changed)
	if node then
		local parent = node:GetParent()
		Node.ScanLocal(parent)
		target, changed = Node.NavigateToBestCandidateV3(self.Cur, key)
		if changed then
			return target, changed;
		end
		return self:ReverseScanUI(parent, key)
	end
	return self.Cur, false;
end

function Cursor:ReverseScanStack(node, key, target, changed)
	if node then
		local parent = node:GetParent()
		Node.ScanLocal(parent)
		target, changed = Node.NavigateToBestCandidateV2(self.Cur, key)
		if changed then
			return target, changed;
		end
		return self:FlatScanStack(key)
	end
	return self.Cur, false;
end

function Cursor:FlatScanStack(key)
	self:ScanUI()
	return Node.NavigateToBestCandidateV3(self.Cur, key)
end

---Navigates the cursor in the given direction
---@param key string The D-pad direction key
---@return NodeObject|nil target The resulting node object
---@return boolean|nil changed Whether the selection changed
function Cursor:Navigate(key)
	local target, changed;
	if db('UIaccessUnlimited') then
		target, changed = self:SetCurrent(self:ReverseScanUI(self:GetCurrentNode(), key))
	elseif db('UIalgoOptimize') then
		target, changed = self:SetCurrent(self:ReverseScanStack(self:GetCurrentNode(), key))
	else
		target, changed = self:SetCurrent(self:FlatScanStack(key))
	end
	if not changed then
		target, changed = self:SetCurrent(Node.NavigateToClosestCandidate(target, key))
	end
	return target, changed;
end

---Attempts to select the best candidate node after a scan
---@return Frame|nil node The selected node, or nil
function Cursor:AttemptSelectNode()
	local newObj = Node.NavigateToArbitraryCandidate(self.Cur, self.Old, self:GetCenter())
	local target, changed = self:SetCurrent(newObj)
	if target then
		if changed then
			self:SetFlashNextNode()
		end
		return self:SelectAndPosition(self:GetSelectParams(target, true))
	end
end

---Handles D-pad and dynamic button input
---@param key string The button identifier
---@param caller any The input caller
---@param isDown boolean|nil Whether the button is pressed
---@return Frame|nil node The selected node after navigation
function Cursor:Input(key, caller, isDown)
	local target, changed
	if isDown and key then
		if not self:AttemptDragStart() then
			target, changed = self:Navigate(key)
		end
	elseif self:IsDynamicControl(key) then
		return Hooks:ProcessInterfaceCursorEvent(key, isDown, self:GetCurrentNode())
	end
	if ( target ) then
		return self:SelectAndPosition(self:GetSelectParams(target, isDown))
	end
end

---------------------------------------------------------------
-- Current node queries
---------------------------------------------------------------
---Sets the current NodeObject, returning the new object and whether it changed
---@param newObj NodeObject|nil The new cursor selection
---@return NodeObject|nil current The current (or new) object
---@return boolean changed Whether the selection changed
function Cursor:SetCurrent(newObj)
	local oldObj = self:GetCurrent()
	if ( oldObj and newObj == oldObj ) then
		return oldObj, false;
	end
	self.Old = oldObj;
	self.Cur = newObj;
	return newObj, true;
end

---Returns the current NodeObject
---@return NodeObject|nil
function Cursor:GetCurrent()
	return self.Cur;
end

---Returns the current node widget, or nil
---@return Frame|nil
function Cursor:GetCurrentNode()
	local obj = self:GetCurrent()
	return obj and obj.node;
end

---Returns whether the given node is the current cursor node
---@param node Frame|nil The node to check
---@param uniqueTriggered boolean|nil If true, also require the node is not mouse-overed
---@return boolean
function Cursor:IsCurrentNode(node, uniqueTriggered)
	return self:IsShown() and (node and node == self:GetCurrentNode())
		and (not uniqueTriggered or not node:IsMouseOver())
end

---Returns the object type string of the current selection
---@return string|nil
function Cursor:GetCurrentObjectType()
	local obj = self:GetCurrent()
	return obj and obj.object;
end

---Returns whether the current node is visible and drawn on screen
---@return boolean|nil
function Cursor:IsCurrentNodeDrawn()
	local node = self:GetCurrentNode()
	return node and ( node:IsVisible() and Node.IsDrawn(node) )
end

---Returns whether auto-scrolling is valid for the given super frame
---@param super Frame|nil The scroll container
---@param force boolean|nil If true, skip same-super check
---@return boolean|nil
function Cursor:IsValidForAutoScroll(super, force)
	if not super then return end
	local old = self:GetOld()
	local oldSuper = old and old.super;
	return (force or super == oldSuper)
		and not env.NodeAttr.IsIgnoreScroll(super)
		and not IsShiftKeyDown()
		and not IsControlKeyDown()
end

---Unpacks a NodeObject into select parameters
---@param obj NodeObject The node object to unpack
---@param triggerOnEnter boolean|nil Whether to trigger OnEnter
---@param automatic boolean|nil Whether this is an automatic selection
---@return Frame node
---@return string object
---@return Frame|nil super
---@return boolean|nil triggerOnEnter
---@return boolean|nil automatic
function Cursor:GetSelectParams(obj, triggerOnEnter, automatic)
	return obj.node, obj.object, obj.super, triggerOnEnter, automatic;
end

---Returns the previous NodeObject
---@return NodeObject|nil
function Cursor:GetOld()
	return self.Old;
end

---Returns the previous node widget, or nil
---@return Frame|nil
function Cursor:GetOldNode()
	local obj = self:GetOld()
	return obj and obj.node;
end

---------------------------------------------------------------
-- Script handling
---------------------------------------------------------------
---Replaces a script handler with a taint-safe alternative
---@param scriptType string The script type (e.g. 'OnEnter', 'OnLeave')
---@param original function The original script handler
---@param replacement function The replacement handler
---@return any result
function Cursor:ReplaceScript(scriptType, original, replacement)
	return env.ReplaceScript(scriptType, original, replacement)
end

do	local function IsDisabledButton(node)
		return node:IsObjectType('Button') and not (node:IsEnabled() or node:GetMotionScriptsWhileDisabled())
	end

	function Cursor:OnLeaveNode(node)
		if node and not IsDisabledButton(node) then
			Hooks:OnNodeLeave()
			env.ExecuteScript(node, 'OnLeave')
		end
	end

	function Cursor:OnEnterNode(node)
		if node and not IsDisabledButton(node) then
			env.ExecuteScript(node, 'OnEnter')
		end
	end
end

---------------------------------------------------------------
-- Node management
---------------------------------------------------------------
---Returns whether a node is clickable (has OnClick and is not an EditBox)
---@param node Frame The node to check
---@param object string The node's object type
---@return boolean
function Cursor:IsClickableNode(node, object)
	if not (env.IsClickableType[object] and object ~= 'EditBox') then
		return false;
	end
	if node:GetScript('OnClick') then
		return true;
	end
	return not node:GetScript('OnMouseDown') and not node:GetScript('OnMouseUp')
end

---Returns a dropdown replacement macro for the node's value, if applicable
---@param node Frame The node to check
---@return string|nil macro
function Cursor:GetMacroReplacement(node)
	return env.DropdownReplacementMacro[node.value];
end

---------------------------------------------------------------
-- Node selection
---------------------------------------------------------------
---Selects a node, triggers enter/leave scripts, auto-scrolls, and sets up input bindings
---@param node Frame The node to select
---@param object string The node's object type
---@param super Frame|nil The scroll container above the node
---@param newMove boolean|nil Whether this is a new navigation move
---@param automatic boolean|nil Whether this is an automatic selection
---@return Frame node The selected node
function Cursor:SelectAndPosition(node, object, super, newMove, automatic)
	if newMove then
		self:OnLeaveNode(self:GetOldNode())
		self:SetPosition(node)
	end
	self:Select(node, object, super, newMove, automatic)
	return node
end

---Performs node selection logic: enter script, auto-scroll, and input binding setup
---@param node Frame The node to select
---@param object string The node's object type
---@param super Frame|nil The scroll container
---@param triggerOnEnter boolean|nil Whether to fire OnEnter
---@param automatic boolean|nil Whether this is an automatic selection
function Cursor:Select(node, object, super, triggerOnEnter, automatic)
	self:OnEnterNode(triggerOnEnter and node)

	if self:IsValidForAutoScroll(super, automatic) then
		Scroll:To(node, super, self:GetOldNode(), automatic)
	end

	self:SetScrollButtonsForNode(node, super)
	self:SetCancelButtonForNode(node)
	self:SetClickButtonsForNode(node,
		self:GetMacroReplacement(node),
		self:IsClickableNode(node, object)
	);
end

---Sets up scroll override buttons for the current node's scroll container
---@param node Frame The current node
---@param super Frame|nil The scroll container
---@return Button|nil scrollUp
---@return Button|nil scrollDown
function Cursor:SetScrollButtonsForNode(node, super)
	local scrollUp, scrollDown = Scroll:GetScrollButtonsForController(node, super)
	if not scrollUp or not scrollDown then
		scrollUp, scrollDown = Node.GetScrollButtons(node)
	end
	self:ToggleScrollIndicator(scrollUp and scrollDown)
	if scrollUp and scrollDown then
		local modifier = env.Settings:GetCommandModifier()
		self.scrollers = {
			Input:SetGlobal(format('%s-%s', modifier, 'PADDUP'),   self, scrollUp:GetName(),   true),
			Input:SetGlobal(format('%s-%s', modifier, 'PADDDOWN'), self, scrollDown:GetName(), true)
		};
		return scrollUp, scrollDown
	end
	if self.scrollers then
		for _, widget in ipairs(self.scrollers) do
			widget:ClearOverride(self)
		end
		self.scrollers = nil;
	end
end

---Sets up click button bindings for the current node
---@param node Frame The current node
---@param macroReplacement string|nil A macro template for dropdown replacement
---@param isClickable boolean Whether the node is directly clickable
function Cursor:SetClickButtonsForNode(node, macroReplacement, isClickable)
	for click, button in pairs({
		LeftButton  = env.Settings:GetButton('LeftClick');
		RightButton = env.Settings:GetButton('RightClick');
	}) do for modifier in db:For('Gamepad/Index/Modifier/Active') do
			if macroReplacement then
				local unit = UIDROPDOWNMENU_INIT_MENU.unit
				Input:SetMacro(modifier .. button, self, macroReplacement:format(unit or ''), true)
			elseif isClickable then
				Input:SetButton(modifier .. button, self, node, true, click)
			else
				Input:SetCommand(modifier .. button, self, true, self:GetEmuClick(node, click))
			end
		end
	end
end

---Attempts to start a drag operation on the current node
---@return boolean|nil started True if drag was initiated
function Cursor:AttemptDragStart()
	local node = self:GetCurrentNode()
	local script = node and not env.NodeAttr.IsIgnoreDrag(node)
		and node:GetScript('OnDragStart');
	if script then
		local widget = Input:GetActiveWidget(env.Settings:GetButton('LeftClick'), self)
		local click = widget and widget:HasClickButton()
		if widget and widget.state and click then
			widget:ClearClickButton()
			widget:EmulateFrontend(click, 'NORMAL', 'OnMouseUp')
			script(node, 'LeftButton')
			return true;
		end
	end
end

do local function GetCloseButton(node)
		if rawget(node, 'CloseButton') then
			return node.CloseButton;
		end
		local nodeName = node:GetName();
		if nodeName then
			return _G[nodeName..'CloseButton'];
		end
	end

	local function FindCloseButton(node)
		if not node then return end;
		return GetCloseButton(node) or FindCloseButton(node:GetParent())
	end

	function Cursor:SetCancelButtonForNode(node)
		local cancelButton = env.Settings:GetButton('Cancel')
		if not cancelButton then return end

		if Hooks:GetCancelClickHandler(node) then
			return self:SetBasicControl(cancelButton)
		end

		local closeButton = FindCloseButton(node)
		if C_Widget.IsFrameWidget(closeButton) then RunNextFrame(function()
			if self:InCombat() or not self:IsShown() then return end;
			Input:SetButton(cancelButton, self, closeButton, true, 'LeftButton')
		end) end;
	end
end

---------------------------------------------------------------
-- CombatGuard subscription
---------------------------------------------------------------
CPAPI.Start(Cursor)

env.CombatGuard:Subscribe('Cursor', {
	OnCombatStart = function()
		Cursor.isCombatPaused = true;
		if Cursor:IsShown() then
			Fade.Out(Cursor, 0.2, Cursor:GetAlpha(), 0)
			Cursor:ShowAfterCombat(true)
			Cursor:SetFlashNextNode()
			Cursor:Release()
		end
	end,
	OnCombatEnd = function()
		if Cursor:IsShown() and not Cursor.showAfterCombat then
			Cursor:Hide()
		end
		Cursor.isCombatPaused = nil;
		if Cursor.showAfterCombat then
			Fade.In(Cursor, 0.2, Cursor:GetAlpha(), 1)
			if not Cursor:InCombat() and Cursor:IsShown() then
				Cursor:SetBasicControls()
				Cursor:Refresh()
			end
			Cursor.showAfterCombat = nil;
		end
	end,
})
