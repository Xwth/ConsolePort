---------------------------------------------------------------
-- NodeObject — formalized node-object wrapper
---------------------------------------------------------------
-- Provides a metatable-based wrapper for the {node, object, super}
-- tables used by the Cursor to track the current selection.
-- Validates node via C_Widget.IsFrameWidget on construction,
-- returning nil for invalid inputs.

local env, db = CPAPI.GetEnv(...);
---------------------------------------------------------------
local IsFrameWidget = C_Widget.IsFrameWidget;
---------------------------------------------------------------

---@class NodeObject
---@field node   Frame       the focusable frame widget
---@field object string      widget type string ('Button', 'EditBox', etc.)
---@field super  Frame|nil   parent scroll container, or nil
local NodeObject = {};
NodeObject.__index = NodeObject;

env.NodeObject = NodeObject;

---------------------------------------------------------------
-- Constructor
---------------------------------------------------------------
function NodeObject.Create(node, object, super)
	if not node or not IsFrameWidget(node) then
		return nil;
	end
	return setmetatable({
		node   = node;
		object = object;
		super  = super;
	}, NodeObject);
end

---------------------------------------------------------------
-- Accessors
---------------------------------------------------------------
function NodeObject:GetNode()
	return self.node;
end

function NodeObject:GetObjectType()
	return self.object;
end

function NodeObject:GetSuper()
	return self.super;
end
