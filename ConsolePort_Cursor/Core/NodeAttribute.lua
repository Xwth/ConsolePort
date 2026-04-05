---------------------------------------------------------------
-- NodeAttribute — typed getter/setter helpers
---------------------------------------------------------------
-- Provides concise accessor functions for node attributes,
-- eliminating verbose node:GetAttribute(env.Attributes.X)
-- patterns throughout the codebase. Setters wrap calls in
-- db:RunSafe for combat-lockdown safety.
-- Note: db:RunSafe is a combat-lockdown deferral from RelaTable that queues
--        calls for after PLAYER_REGEN_ENABLED if InCombatLockdown() is true.

local env, db = CPAPI.GetEnv(...);
---------------------------------------------------------------

---@class NodeAttr
local NodeAttr = {};
env.NodeAttr = NodeAttr;

---------------------------------------------------------------
-- Attribute key shortcuts
---------------------------------------------------------------
local Attr = env.Attributes;

---------------------------------------------------------------
-- Getters (generated from definition table)
---------------------------------------------------------------
local Getters = {
	IsIgnored       = Attr.IgnoreNode;
	IsSingleton     = Attr.Singleton;
	IsPassThrough   = Attr.PassThrough;
	IsIgnoreDrag    = Attr.IgnoreDrag;
	IsIgnoreMime    = Attr.IgnoreMime;
	IsIgnoreScroll  = Attr.IgnoreScroll;
	GetPriority     = Attr.Priority;
	GetSpecialClick = Attr.SpecialClick;
	GetCancelClick  = Attr.CancelClick;
	HasDisableHooks = Attr.DisableHooks;
};

for name, attrKey in pairs(Getters) do
	NodeAttr[name] = function(node)
		return node:GetAttribute(attrKey);
	end
end

---------------------------------------------------------------
-- Setters (generated from definition table, combat-lockdown-safe via db:RunSafe)
---------------------------------------------------------------
local Setters = {
	SetIgnored      = Attr.IgnoreNode;
	SetPassThrough  = Attr.PassThrough;
	SetIgnoreScroll = Attr.IgnoreScroll;
	SetIgnoreNode   = Attr.IgnoreNode;
	SetPriority     = Attr.Priority;
	SetSpecialClick = Attr.SpecialClick;
	SetCancelClick  = Attr.CancelClick;
};

for name, attrKey in pairs(Setters) do
	NodeAttr[name] = function(node, val)
		db:RunSafe(node.SetAttribute, node, attrKey, val);
	end
end
