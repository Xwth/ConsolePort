---------------------------------------------------------------
-- Scroll management
---------------------------------------------------------------
-- Handles centered, interpolated and manual scrolling
-- of scroll frames and scroll boxes. The keyword "super" is
-- used to refer to a candidate scroll frame or scroll box that
-- is above the node in the hierarchy by one or more levels.

---@class Scroll : Frame
local Scroll, Node, Clamp, env, db =
	CreateFrame('Frame', '$parentUIScrollHandler', ConsolePort),
	LibStub('ConsolePortNode'),
	Clamp, CPAPI.GetEnv(...);

local xpcall, CallErrorHandler = xpcall, CallErrorHandler;
local rawget = rawget;
local GenerateClosure = GenerateClosure;

---------------------------------------------------------------
-- Auto-scrolling
---------------------------------------------------------------
---Scrolls a scroll frame or scroll box to bring a node into view
---@param node Frame The target node to scroll to
---@param super ScrollFrame|Frame The scroll container (ScrollFrame or ScrollBox)
---@param prev Frame|nil The previously selected node, for direction detection
---@param force boolean|nil If true, always scroll regardless of direction
function Scroll:To(node, super, prev, force)
	local nodeX, nodeY = Node.GetCenter(node)
	local scrollX, scrollY = super:GetCenter()
	if nodeY and scrollY then

		if self:IsValidScrollFrame(super) then
			local prevX, prevY = nodeX, nodeY;
			if prev then
				prevX, prevY = Node.GetCenter(prev)
			end

			local current, range = super:GetVerticalScroll(), super:GetVerticalScrollRange();
			local target = self:GetVerticalScrollTarget(current, scrollY, nodeY, prevY, force, range)
			self:Interpolate(super, current, target, GenerateClosure(super.SetVerticalScroll, super))

		elseif self:IsValidScrollBox(super) then
			local index = self:GetScrollBoxElementDataIndex(super, node)
			if index then
				return super:ScrollToElementDataIndex(index)
			end
		end
	end
end

---Calculates the clamped vertical scroll target position
---@param currVert number Current vertical scroll offset
---@param scrollY number Y center of the scroll container
---@param nodeY number Y center of the target node
---@param prevY number|nil Y center of the previous node
---@param force boolean|nil Force scroll regardless of direction
---@param maxVert number Maximum vertical scroll range
---@return number target Clamped scroll target
function Scroll:GetVerticalScrollTarget(currVert, scrollY, nodeY, prevY, force, maxVert)
	return Clamp(self:GetScrollTarget(currVert, scrollY, nodeY, prevY, force), 0, maxVert)
end

---Calculates the raw scroll target offset
---@param curr number Current scroll offset
---@param scrollPos number Center position of the scroll container
---@param nodePos number Center position of the target node
---@param prevPos number|nil Center position of the previous node
---@param force boolean|nil Force scroll regardless of direction
---@return number target Scroll target offset
function Scroll:GetScrollTarget(curr, scrollPos, nodePos, prevPos, force)
	local new = curr + (scrollPos - nodePos)
	if force or not tonumber(prevPos) or (new > curr) ~= (nodePos > prevPos) then
		return new;
	end
	return curr;
end

---Returns whether the given frame is a valid (non-hybrid) ScrollFrame
---@param super Frame The frame to check
---@return boolean
function Scroll:IsValidScrollFrame(super)
	-- HACK: make sure this isn't a hybrid scroll frame
	return super:IsObjectType('ScrollFrame') and
		super:GetScript('OnLoad') ~= HybridScrollFrame_OnLoad;
end

---Returns whether the given frame is a valid ScrollBox (has ScrollToElementDataIndex)
---@param super Frame The frame to check
---@return boolean|function|nil
function Scroll:IsValidScrollBox(super)
	return rawget(super, 'ScrollToElementDataIndex')
end

---Walks up the node hierarchy to find the immediate child of the scroll target
---@param super Frame The scroll box container
---@param node Frame The target node
---@return Frame|nil child The immediate child of the scroll target, or nil
function Scroll:GetImmediateScrollTargetNode(super, node)
	local scrollTarget = super:GetScrollTarget()
	while ( node and node:GetParent() ~= scrollTarget ) do
		node = node:GetParent()
	end
	return node;
end

---Returns the element data index for a node inside a ScrollBox
---@param super Frame The scroll box container
---@param node Frame The target node
---@return number|nil index The element data index, or nil
function Scroll:GetScrollBoxElementDataIndex(super, node)
	node = self:GetImmediateScrollTargetNode(super, node)
	if not node then return end;
	local getter = rawget(node, 'GetElementDataIndex')
	if not getter then return end;
	local ok, index = xpcall(getter, CallErrorHandler, node)
	return ok and index;
end

---------------------------------------------------------------
-- Interpolated scrolling
---------------------------------------------------------------
---Starts an interpolated scroll animation from current to target
---@param super Frame The scroll container (used as pool key)
---@param current number Current scroll position
---@param target number Target scroll position
---@param setter fun(value: number) Function to apply the interpolated value
function Scroll:Interpolate(super, current, target, setter)
	local active, interpolators = self:GetPools()
	if active[super] and interpolators:IsActive(active[super]) then
		interpolators:Release(active[super])
	end
	local interpolator = self.Interpolators:Acquire()
	interpolator:Interpolate(current, target, .11, setter, function()
		if interpolators:Release(interpolator) then
			active[super] = nil;
		end
	end)
	active[super] = interpolator;
end

---Returns or creates the active interpolator tracking table and object pool
---@return table<Frame, Interpolator> active Active interpolators keyed by scroll container
---@return ObjectPool interpolators The interpolator object pool
function Scroll:GetPools()
	if not self.Active then
		self.Active = {};
		self.Interpolators = CreateObjectPool(
			GenerateClosure(CreateInterpolator, InterpolatorUtil.InterpolateEaseOut),
			function(_, interpolator) interpolator:Cancel() end
		);
	end
	return self.Active, self.Interpolators;
end


---------------------------------------------------------------
-- Scroll controller
---------------------------------------------------------------
local ScrollControllerPrimitive = ScrollControllerMixin;

---@class ScrollProxyMixin : Button
---@field Delta number Scroll direction delta value
---@field repeatTimer RepeatTimer Timer for held-button repeat scrolling
local ScrollProxyMixin = {};

---Executes a scroll step on the active scroll controller
function ScrollProxyMixin:Execute()
	local parent = self:GetParent();
	local super = parent.ActiveController;
	if super then
		env.ExecuteScript(super, 'OnMouseWheel', self.Delta)
	end
end

---Handles click events: starts repeat scrolling on press, stops on release
---@param _ any Unused
---@param down boolean Whether the button is pressed
function ScrollProxyMixin:OnClick(_, down)
	if down then
		self:Execute()
		self.repeatTimer:Start(env.Settings:GetRepeatDelayFirst(), env.Settings:GetRepeatDelay())
		self:SetScript('OnUpdate', self.OnUpdate)
	else
		self.repeatTimer:Stop()
		self:SetScript('OnUpdate', nil)
	end
end

---Updates the repeat timer each frame while held
---@param elapsed number Time since last frame
function ScrollProxyMixin:OnUpdate(elapsed)
	self.repeatTimer:OnUpdate(elapsed)
end

for direction, ProxyButton in pairs({
	Up   = Mixin(CreateFrame('Button', '$parentProxyUp', Scroll),   ScrollProxyMixin, { Delta = ScrollControllerPrimitive.Directions.Increase });
	Down = Mixin(CreateFrame('Button', '$parentProxyDown', Scroll), ScrollProxyMixin, { Delta = ScrollControllerPrimitive.Directions.Decrease });
}) do Scroll[direction] = ProxyButton;
	ProxyButton.repeatTimer = env.RepeatTimer.Create(function() ProxyButton:Execute() end)
	ProxyButton:SetScript('OnClick', ProxyButton.OnClick)
	ProxyButton:RegisterForClicks('AnyUp', 'AnyDown')
end

---Returns proxy scroll buttons if the node or its parent is a valid scroll controller
---@param node Frame The currently focused node
---@param super Frame|nil The scroll container above the node
---@return Button|nil scrollUp The up scroll proxy button
---@return Button|nil scrollDown The down scroll proxy button
function Scroll:GetScrollButtonsForController(node, super)
	if self:IsValidScrollController(super) then
		self.ActiveController = super;
		return self.Up, self.Down;
	end
	-- We're at most two levels deep (thumb or up/down buttons),
	-- so we want to find the first scroll controller in the hierarchy.
	local depth, parent = 2, node:GetParent();
	while parent and depth > 0 do
		if self:IsValidScrollController(parent) then
			self.ActiveController = parent;
			return self.Up, self.Down;
		end
		depth, parent = depth - 1, parent:GetParent();
	end
	self.ActiveController = nil;
end

---Returns whether the given frame uses ScrollControllerMixin's OnMouseWheel handler
---@param super Frame|nil The frame to check
---@return boolean
function Scroll:IsValidScrollController(super)
	return super and super:GetScript('OnMouseWheel') == ScrollControllerPrimitive.OnMouseWheel;
end
