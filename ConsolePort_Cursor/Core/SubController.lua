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
---@return nil
function SubControllerMixin:InitLifecycle()
	Mixin(self, CallbackRegistrantMixin)
	self:AddDynamicEventMethod(env.CombatGuard, "OnCombatStart", self.OnCombatStart)
	self:AddDynamicEventMethod(env.CombatGuard, "OnCombatEnd", self.OnCombatEnd)
	db:RegisterCallback('OnBindingCatcherShown', self.OnBindingCatcherShown, self)
	CPAPI.Start(self, true)
end

---------------------------------------------------------------
-- Combat callbacks
---------------------------------------------------------------
---@return nil
function SubControllerMixin:OnCombatStart()
	self:Hide()
end

---@return nil
function SubControllerMixin:OnCombatEnd()
	self:Show()
end

---------------------------------------------------------------
-- Binding catcher callback
---------------------------------------------------------------
---@param isCatcherShown boolean  true if the binding catcher is visible
---@return nil
function SubControllerMixin:OnBindingCatcherShown(isCatcherShown)
	self:SetShown(not isCatcherShown)
end

---------------------------------------------------------------
-- Register into environment
---------------------------------------------------------------
env.SubControllerMixin = SubControllerMixin;
