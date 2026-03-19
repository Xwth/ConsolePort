---------------------------------------------------------------
-- NodeAttribute — typed getter/setter helpers
---------------------------------------------------------------
-- Provides concise accessor functions for node attributes,
-- eliminating verbose node:GetAttribute(env.Attributes.X)
-- patterns throughout the codebase. Setters wrap calls in
-- db:RunSafe for taint safety.

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
-- Getters
---------------------------------------------------------------
function NodeAttr.IsIgnored(node)
	return node:GetAttribute(Attr.IgnoreNode);
end

function NodeAttr.IsSingleton(node)
	return node:GetAttribute(Attr.Singleton);
end

function NodeAttr.IsPassThrough(node)
	return node:GetAttribute(Attr.PassThrough);
end

function NodeAttr.IsIgnoreDrag(node)
	return node:GetAttribute(Attr.IgnoreDrag);
end

function NodeAttr.IsIgnoreMime(node)
	return node:GetAttribute(Attr.IgnoreMime);
end

function NodeAttr.IsIgnoreScroll(node)
	return node:GetAttribute(Attr.IgnoreScroll);
end

function NodeAttr.GetPriority(node)
	return node:GetAttribute(Attr.Priority);
end

function NodeAttr.GetSpecialClick(node)
	return node:GetAttribute(Attr.SpecialClick);
end

function NodeAttr.GetCancelClick(node)
	return node:GetAttribute(Attr.CancelClick);
end

function NodeAttr.HasDisableHooks(node)
	return node:GetAttribute(Attr.DisableHooks);
end

---------------------------------------------------------------
-- Setters (taint-safe via db:RunSafe)
---------------------------------------------------------------
function NodeAttr.SetIgnored(node, val)
	db:RunSafe(node.SetAttribute, node, Attr.IgnoreNode, val);
end

function NodeAttr.SetPassThrough(node, val)
	db:RunSafe(node.SetAttribute, node, Attr.PassThrough, val);
end

function NodeAttr.SetIgnoreScroll(node, val)
	db:RunSafe(node.SetAttribute, node, Attr.IgnoreScroll, val);
end

function NodeAttr.SetIgnoreNode(node, val)
	db:RunSafe(node.SetAttribute, node, Attr.IgnoreNode, val);
end

function NodeAttr.SetPriority(node, val)
	db:RunSafe(node.SetAttribute, node, Attr.Priority, val);
end

function NodeAttr.SetSpecialClick(node, fn)
	db:RunSafe(node.SetAttribute, node, Attr.SpecialClick, fn);
end

function NodeAttr.SetCancelClick(node, fn)
	db:RunSafe(node.SetAttribute, node, Attr.CancelClick, fn);
end
