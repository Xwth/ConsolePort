---------------------------------------------------------------
-- Menu navigator
---------------------------------------------------------------
-- Navigates dropdown menus using shoulder buttons when the
-- cursor is on a dropdown element. Uses the SubController
-- lifecycle pattern and reads env.MenuStrategy set by Compat.

local env, db = CPAPI.GetEnv(...);
local MenuNavigator =
	CPAPI.CreateEventHandler({'Frame', '$parentMenuNavigator', env.Cursor}, {});
local MenuStrategy; -- set in OnDataLoaded from env.MenuStrategy

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local function ShoulderDelta(button)
	local swap = env.Settings:IsShoulderMenuSwapDirection();
	if button == 'PADRSHOULDER' then return swap and -1 or  1 end;
	if button == 'PADLSHOULDER' then return swap and  1 or -1 end;
end

---------------------------------------------------------------
-- Button-up dispatch table
---------------------------------------------------------------
local MENU_ACTIONS = {
	PADDDOWN  = { execute = function(self) self:CycleFocus( 1) end, propagate = false };
	PADDUP    = { execute = function(self) self:CycleFocus(-1) end, propagate = false };
	PADDLEFT  = { propagate = true  };
	PADDRIGHT = { propagate = true  };
};

---------------------------------------------------------------
-- Initialization
---------------------------------------------------------------
function MenuNavigator:OnDataLoaded()
	self.menuNav = {
		state      = 'idle',
		focusIndex = 0,
		session    = {
			dropdown        = nil,
			selectableItems = {},
			returnNode      = nil,
		},
	};
	Mixin(self, env.SubControllerMixin)
	self:InitLifecycle()
	MenuStrategy = env.MenuStrategy;
	MENU_ACTIONS['PADDLEFT'].execute  = self.CloseMenuNavigation;
	MENU_ACTIONS['PADDRIGHT'].execute = self.CloseMenuNavigation;
	self:OnVariablesChanged()
	return CPAPI.BurnAfterReading;
end

---------------------------------------------------------------
-- Settings callbacks
---------------------------------------------------------------
function MenuNavigator:RebuildMenuActions()
	local s = env.Settings;
	for k, v in pairs(MENU_ACTIONS) do
		if v.dynamic then MENU_ACTIONS[k] = nil end;
	end
	local lc = s:GetButton('LeftClick');
	if lc then MENU_ACTIONS[lc] = {
		execute = self.SelectFocusedItem, propagate = false, dynamic = true,
	} end;
	local cc = s:GetButton('Cancel');
	if cc then MENU_ACTIONS[cc] = {
		execute = self.CloseMenuNavigation, propagate = false, dynamic = true,
	} end;
end

function MenuNavigator:OnVariablesChanged()
	self:RebuildMenuActions()
	if self.menuNav and self.menuNav.state ~= 'idle'
		and not env.Settings:IsShoulderMenuEnabled() then
		self:CloseMenuNavigation();
	end
end

db:RegisterSafeCallback('Settings/UIshoulderMenuEnable', MenuNavigator.OnVariablesChanged, MenuNavigator)
db:RegisterSafeCallback('Settings/UICursorLeftClick', MenuNavigator.OnVariablesChanged, MenuNavigator)
db:RegisterSafeCallback('Settings/UICursorCancel', MenuNavigator.OnVariablesChanged, MenuNavigator)

---------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------
function MenuNavigator:OnShow()
	CallbackRegistrantMixin.OnShow(self)
	self:RegisterEvent('MODIFIER_STATE_CHANGED')
end

function MenuNavigator:OnHide()
	if self.menuNav and self.menuNav.state ~= 'idle' then
		self:CloseMenuNavigation();
	end
	CallbackRegistrantMixin.OnHide(self)
	self:UnregisterAllEvents()
	self:EnableGamePadButton(false)
end

---------------------------------------------------------------
-- Input
---------------------------------------------------------------
function MenuNavigator:OnGamePadButtonDown(button)
	local delta = ShoulderDelta(button);
	if not delta then
		return self:SetPropagateKeyboardInput(true);
	end

	-- Menu already open: cycle or bail if closed externally.
	if self.menuNav.state == 'menuOpen' then
		if not MenuStrategy:IsMenuVisible() then
			self:CloseMenuNavigation();
			return self:SetPropagateKeyboardInput(true);
		end
		self:CycleFocus(delta);
		return self:SetPropagateKeyboardInput(false);
	end

	-- Idle: check for dropdown under cursor.
	local dropdown = self:GetMenuShowingElement();
	if dropdown then
		if env.Settings:IsShoulderMenuSilent() then
			self:SilentCycle(dropdown, delta);
		else
			self:OpenMenuNavigation(dropdown);
		end
		return self:SetPropagateKeyboardInput(false);
	end

	-- Not ours — let PanelCycler handle it.
	self:SetPropagateKeyboardInput(true);
end

function MenuNavigator:OnGamePadButtonUp(button)
	if self.menuNav.state ~= 'menuOpen' then
		return self:SetPropagateKeyboardInput(true);
	end
	if not MenuStrategy:IsMenuVisible() then
		self:CloseMenuNavigation();
		return self:SetPropagateKeyboardInput(true);
	end
	local action = MENU_ACTIONS[button];
	if action then
		action.execute(self);
		return self:SetPropagateKeyboardInput(action.propagate);
	end
	self:SetPropagateKeyboardInput(true);
end

---------------------------------------------------------------
-- Modifier state
---------------------------------------------------------------
function MenuNavigator:MODIFIER_STATE_CHANGED()
	local modifier = env.Settings:GetCommandModifier();
	local predicate = env.ModifierPredicates[modifier];
	self:EnableGamePadButton(predicate and predicate());
end


---------------------------------------------------------------
-- Menu navigation methods (moved from Shoulder.lua)
---------------------------------------------------------------
function MenuNavigator:GetMenuShowingElement()
	if not env.Settings:IsShoulderMenuEnabled() then return end;
	local node = env.Cursor:GetCurrentNode();
	if not node then return end;
	local dropdown = MenuStrategy:FindDropdown(node);
	if dropdown and dropdown.GetMenuDescription
		and not dropdown.menuGenerator
		and not dropdown:GetMenuDescription() then
		return;
	end
	return dropdown;
end

function MenuNavigator:OpenMenuNavigation(dropdown)
	if InCombatLockdown() then return end;
	if self.menuNav.state ~= 'idle' then return end;

	local nav     = self.menuNav;
	local session = nav.session;
	session.returnNode      = env.Cursor:GetCurrentNode();
	session.dropdown        = dropdown;
	MenuStrategy:OpenMenu(dropdown);
	session.selectableItems = MenuStrategy:CollectSelectableItems(dropdown);
	nav.focusIndex          = #session.selectableItems > 0 and 1 or 0;
	nav.state               = 'menuOpen';
	if nav.focusIndex > 0 then
		self:HighlightFocusedItem();
	end
end

function MenuNavigator:CloseMenuNavigation()
	MenuStrategy:CloseMenu();
	local nav     = self.menuNav;
	local session = nav.session;
	if session.returnNode then
		env.Cursor:SetCurrentNode(session.returnNode);
	end
	nav.state               = 'idle';
	nav.focusIndex          = 0;
	session.dropdown        = nil;
	session.returnNode      = nil;
	wipe(session.selectableItems);
end

--- Re-collect items after a pick that kept the menu open, clamp focus.
function MenuNavigator:RefreshMenuItems()
	local nav     = self.menuNav;
	local session = nav.session;
	session.selectableItems = MenuStrategy:CollectSelectableItems(session.dropdown);
	local count = #session.selectableItems;
	if count == 0 then
		nav.focusIndex = 0;
	elseif nav.focusIndex > count then
		nav.focusIndex = count;
	end
	if nav.focusIndex > 0 then
		self:HighlightFocusedItem();
	end
end

function MenuNavigator:CycleFocus(delta)
	local nav     = self.menuNav;
	local session = nav.session;
	local n = #session.selectableItems;
	if n == 0 or nav.focusIndex == 0 then return end;
	if nav.focusIndex > n then nav.focusIndex = n end;

	local old = session.selectableItems[nav.focusIndex];
	if old then MenuStrategy:UnhighlightItem(old) end;
	nav.focusIndex = ((nav.focusIndex - 1 + delta) % n) + 1;
	self:HighlightFocusedItem();
end

function MenuNavigator:HighlightFocusedItem()
	local nav     = self.menuNav;
	local session = nav.session;
	local item = session.selectableItems[nav.focusIndex];
	if item then MenuStrategy:HighlightItem(item) end;
end

function MenuNavigator:SelectFocusedItem()
	if InCombatLockdown() then return end;
	local nav     = self.menuNav;
	local session = nav.session;
	if nav.focusIndex == 0 then return end;
	if nav.focusIndex > #session.selectableItems then
		nav.focusIndex = #session.selectableItems;
	end
	local item = session.selectableItems[nav.focusIndex];
	if not item then return end;

	local responded, response = MenuStrategy:PickItem(item);
	-- Retail: explicit response enum.
	if responded then
		if response == MenuResponse.Close or response == MenuResponse.CloseAll then
			return self:CloseMenuNavigation();
		end
		return self:RefreshMenuItems();
	end
	-- Classic: infer from dropdown list visibility.
	if not MenuStrategy:IsMenuVisible() then
		return self:CloseMenuNavigation();
	end
	self:RefreshMenuItems();
end

function MenuNavigator:SilentCycle(dropdown, delta)
	if InCombatLockdown() then return end;
	MenuStrategy:SilentCycle(dropdown, delta);
end
