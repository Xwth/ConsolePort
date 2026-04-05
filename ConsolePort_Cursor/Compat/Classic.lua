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

---------------------------------------------------------------
-- Classic menu strategy for shoulder menu navigation
---------------------------------------------------------------
local ClassicMenuStrategy = {};

function ClassicMenuStrategy:FindDropdown(node)
	local current = node;
	while current do
		if current.hasDropDown then
			return current;
		end
		local name = current.GetName and current:GetName();
		if name and name:find('DropDown') then
			return current;
		end
		current = current.GetParent and current:GetParent() or nil;
	end
end

function ClassicMenuStrategy:OpenMenu(dropdown)
	ToggleDropDownMenu(1, nil, dropdown);
end

function ClassicMenuStrategy:CollectSelectableItems(dropdown)
	local list = _G['DropDownList1'];
	if not list then return {} end;
	local items = {};
	for i = 1, (UIDROPDOWNMENU_MAXBUTTONS or 256) do
		local button = _G['DropDownList1Button' .. i];
		if not button then break end;
		if not button.isTitle and not button.isSeparator
			and button:IsShown() and button:IsEnabled() then
			items[#items + 1] = button;
		end
	end
	return items;
end

function ClassicMenuStrategy:HighlightItem(button)
	local hl = button:GetHighlightTexture() or _G[button:GetName() .. 'Highlight'];
	if hl then hl:Show() end;
end

function ClassicMenuStrategy:UnhighlightItem(button)
	local hl = button:GetHighlightTexture() or _G[button:GetName() .. 'Highlight'];
	if hl then hl:Hide() end;
end

function ClassicMenuStrategy:PickItem(button)
	button:Click();
end

function ClassicMenuStrategy:CloseMenu()
	CloseDropDownMenus();
end

function ClassicMenuStrategy:IsMenuVisible()
	local list = _G['DropDownList1'];
	return list and list:IsShown() or false;
end

function ClassicMenuStrategy:SilentCycle(dropdown, delta)
	ToggleDropDownMenu(1, nil, dropdown);
	local items = self:CollectSelectableItems(dropdown);
	if #items == 0 then
		CloseDropDownMenus();
		return;
	end
	-- Find currently checked item.
	local cur = 0;
	for i, button in ipairs(items) do
		local checked = button.GetChecked and button:GetChecked()
			or (button.checked and button.checked());
		if checked then cur = i; break end;
	end
	-- Advance with wrapping.
	cur = cur == 0
		and (delta > 0 and 1 or #items)
		or  (((cur - 1 + delta) % #items) + 1);
	items[cur]:Click();
	CloseDropDownMenus();
end

env.MenuStrategy = ClassicMenuStrategy;
