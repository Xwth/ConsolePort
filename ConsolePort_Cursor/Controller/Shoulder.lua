---------------------------------------------------------------
-- Shoulder controller
---------------------------------------------------------------
-- Cycles the cursor between visible UI panels using shoulder
-- buttons (or a configured modifier + shoulder combination).
-- Uses the SubController lifecycle pattern shared with Nudge.

local env, db = CPAPI.GetEnv(...);
local Shoulder, Node, Stack =
	CPAPI.CreateEventHandler({'Frame', '$parentShoulderHandler', env.Cursor}, {}),
	env.Node,
	ConsolePortUIStackHandler;

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------
function Shoulder:OnDataLoaded()
	Mixin(self, env.SubControllerMixin)
	self:InitLifecycle()
	self:OnVariablesChanged()
	return CPAPI.BurnAfterReading;
end

function Shoulder:OnVariablesChanged()
	self.specialButton = env.Settings:GetButton('Special')
end

db:RegisterSafeCallback('Settings/UICursorSpecial', Shoulder.OnVariablesChanged, Shoulder)

---------------------------------------------------------------
-- Panel cycling
---------------------------------------------------------------
function Shoulder:CyclePanel(delta)
	local cursor = env.Cursor;
	if not cursor:IsShown() then return end;

	-- Build an ordered list of visible panels by screen position (left to right).
	local panels = {};
	for frame in Stack:IterateVisibleCursorFrames() do
		panels[#panels + 1] = frame;
	end
	if #panels < 2 then return end;

	table.sort(panels, function(a, b)
		local ax = a:GetLeft() or 0;
		local bx = b:GetLeft() or 0;
		return ax < bx;
	end)

	-- Find which panel currently owns the cursor node.
	local currentNode = cursor:GetCurrentNode()
	local currentIndex;
	if currentNode then
		for i, panel in ipairs(panels) do
			if currentNode == panel or currentNode:IsDescendantOf(panel) then
				currentIndex = i;
				break;
			end
		end
	end

	-- Cycle with wrapping.
	currentIndex = currentIndex or 1;
	local targetIndex = ((currentIndex - 1 + delta) % #panels) + 1;
	local targetPanel = panels[targetIndex];

	if targetPanel then
		cursor:SetCurrentNode(targetPanel)
	end
end

---------------------------------------------------------------
-- Input handling
---------------------------------------------------------------
function Shoulder:OnShow()
	self:RegisterEvent('MODIFIER_STATE_CHANGED')
end

function Shoulder:OnHide()
	self:UnregisterAllEvents()
	self:EnableGamePadButton(false)
end

function Shoulder:OnGamePadButtonDown(button)
	if button == 'PADLSHOULDER' then
		self:CyclePanel(-1)
		self:SetPropagateKeyboardInput(false)
	elseif button == 'PADRSHOULDER' then
		self:CyclePanel(1)
		self:SetPropagateKeyboardInput(false)
	else
		self:SetPropagateKeyboardInput(true)
	end
end

function Shoulder:MODIFIER_STATE_CHANGED()
	local modifier = env.Settings:GetCommandModifier()
	local isModifierDown =
		(modifier == 'SHIFT' and IsShiftKeyDown()) or
		(modifier == 'CTRL'  and IsControlKeyDown()) or
		(modifier == 'ALT'   and IsAltKeyDown());
	self:EnableGamePadButton(isModifierDown)
end
