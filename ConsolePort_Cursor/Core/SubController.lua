---------------------------------------------------------------
-- SubControllerMixin — common sub-controller lifecycle
---------------------------------------------------------------
-- Shared lifecycle wiring for Nudge and Shoulder controllers.
-- Handles CPAPI.Start, combat show/hide via CombatGuard, and
-- binding-catcher visibility toggling.

local env, db = CPAPI.GetEnv(...);

---@class SubControllerMixin
local SubControllerMixin = {};

---------------------------------------------------------------
-- Lifecycle initialization
---------------------------------------------------------------
function SubControllerMixin:InitLifecycle()
	env.CombatGuard:Subscribe(self, {
		OnCombatStart = function() self:OnCombatStart() end,
		OnCombatEnd   = function() self:OnCombatEnd() end,
	})
	db:RegisterCallback('OnBindingCatcherShown', self.OnBindingCatcherShown, self)
	CPAPI.Start(self, true)
end

---------------------------------------------------------------
-- Combat callbacks
---------------------------------------------------------------
function SubControllerMixin:OnCombatStart()
	self:Hide()
end

function SubControllerMixin:OnCombatEnd()
	self:Show()
end

---------------------------------------------------------------
-- Binding catcher callback
---------------------------------------------------------------
function SubControllerMixin:OnBindingCatcherShown(isCatcherShown)
	self:SetShown(not isCatcherShown)
end

---------------------------------------------------------------
-- Register into environment
---------------------------------------------------------------
env.SubControllerMixin = SubControllerMixin;
