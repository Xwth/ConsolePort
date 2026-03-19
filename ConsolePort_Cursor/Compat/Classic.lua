local env, db, _, L = CPAPI.GetEnv(...); _ = CPAPI.OnAddonLoaded;
if CPAPI.IsRetailVersion then return end;
---------------------------------------------------------------
-- Compat/Classic.lua
-- Classic-only cursor compatibility code.
---------------------------------------------------------------

-- Node identification: Classic container slot detection (duck-typing)
env.TryIdentifyContainerSlot = function(node)
	return not not node.JunkIcon and not not node.SplitStack;
end

-- Node identification: Classic item location constructor
env.CreateItemLocationFromNode = function(node)
	local GetID, GetParent = UIParent.GetID, UIParent.GetParent;
	return ItemLocation:CreateFromBagAndSlot(GetID(GetParent(node)), GetID(node))
end
