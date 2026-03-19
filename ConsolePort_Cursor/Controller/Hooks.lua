---------------------------------------------------------------
-- Hooks
---------------------------------------------------------------
-- Hooks for the interface cursor to do magic things.
-- Node-type and tooltip-type handlers are registered through
-- public APIs, enabling modular extension without editing
-- this file directly.

local env, db, _, L = CPAPI.GetEnv(...)
---@type Hooks
local Hooks = db:Register('Hooks', {}, true); env.Hooks = Hooks;

local TOOLTIP_ICON_SIZE  = 64;
local UTILITY_RING_INDEX = 1;

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local function WrappedExecute(func, execEnv, ...)
	if not func then return end
	local fenv = getfenv(func)
	setfenv(func, setmetatable(execEnv, {__index = fenv}))
	func(...)
	setfenv(func, fenv)
end

local function ModifierOverride(map)
	return { IsModifiedClick = function(action) return map[action] end }
end

local DRESSUP_ENV    = ModifierOverride({ DRESSUP = true, CHATLINK = false });
local EXPANDITEM_ENV = ModifierOverride({ EXPANDITEM = true });

---------------------------------------------------------------
-- Node state — wiped atomically on leave
---------------------------------------------------------------
local NodeState   = {};
local NodeActions = {}; -- active { key, def } pairs in priority order

---------------------------------------------------------------
-- Action definitions — single source of truth.
-- promptKey defaults to 'Special' when absent.
-- execute receives the active node as its argument.
---------------------------------------------------------------
local Actions = {
	itemLocation = {
		execute    = function()     db.ItemMenu:SetItem(NodeState.itemLocation:GetBagAndSlot()) end,
		promptText = OPTIONS,
	},
	spellID = {
		execute    = function()     db.SpellMenu:SetSpell(NodeState.spellID) end,
		promptText = OPTIONS,
	},
	bagLocation = {
		execute    = function()     PickupBagFromSlot(NodeState.bagLocation) end,
		promptText = L 'Pickup',
	},
	dressupItem = {
		execute    = function()
			WrappedExecute(HandleModifiedItemClick, DRESSUP_ENV, NodeState.dressupItem)
		end,
		promptText = INSPECT,
	},
	inventorySlotID = {
		execute    = function(node)
			WrappedExecute(PaperDollItemSlotButton_OnModifiedClick, EXPANDITEM_ENV, node)
			local isArtifact = GetInventoryItemQuality('player', node:GetID()) == Enum.ItemQuality.Artifact;
			if not GetSocketItemInfo() and not isArtifact then
				WrappedExecute(HandleModifiedItemClick, DRESSUP_ENV, GetInventoryItemLink('player', node:GetID()))
			end
		end,
		promptText = function() return ('%s / %s'):format(INSPECT, ARTIFACTS_PERK_TAB or SOCKET_GEMS) end,
	},
	housingPreviewLink = {
		execute    = function()     HousingFramesUtil.PreviewHousingItem(NodeState.housingPreviewLink) end,
		promptText = INSPECT,
	},
};

-- Activate a pending action: store value, queue for routing, show prompt.
local function SetPending(key, tooltip, value)
	local def = Actions[key];
	NodeState[key] = value;
	NodeActions[#NodeActions + 1] = { key = key, def = def };
	local text = type(def.promptText) == 'function' and def.promptText() or def.promptText;
	Hooks:AddPrompt(tooltip, def.promptKey or 'Special', text)
end

-- Generate public SetPending* methods from Actions keys.
-- SetPendingInspectItem has an extra guard so it stays explicit.
for key in pairs(Actions) do
	Hooks['SetPending' .. key:sub(1,1):upper() .. key:sub(2)] = function(self, tooltip, value)
		SetPending(key, tooltip, value)
	end
end

function Hooks:SetPendingInspectItem(tooltip, item)
	if not tonumber(item) then return end
	SetPending('inventorySlotID', tooltip, item)
end

function Hooks:OnNodeLeave()
	if NodeState.pendingAction then
		ConsolePort:ClearPendingRingAction()
	end
	wipe(NodeState);
	wipe(NodeActions);
end

---------------------------------------------------------------
-- Click routing
---------------------------------------------------------------
function Hooks:ProcessInterfaceCursorEvent(button, down, node)
	if down ~= false then return end

	if self:IsCancelClick(button) then
		local handler = self:GetCancelClickHandler(node)
		if handler then handler(node, button, down) return true end
		return
	end

	local handler = self:GetSpecialClickHandler(node)
	if handler then handler(node, button, down) return true end

	if node and node:IsObjectType('EditBox') then
		if node:HasFocus() then node:ClearFocus() else node:SetFocus() end
		return
	end

	for _, entry in ipairs(NodeActions) do
		if NodeState[entry.key] then
			return entry.def.execute(node) ~= false or true
		end
	end

	if ConsolePort:HasPendingRingAction() then
		return ConsolePort:PostPendingRingAction()
	end
end

function Hooks:ProcessInterfaceClickEvent(script, node)
	if script == 'OnMouseUp' then
		if GetCursorInfo() then
			local isActionButton = node:IsProtected() and node:GetAttribute('type') == 'action'
			local actionID = isActionButton and
				(node.CalculateAction and node:CalculateAction() or node:GetAttribute('action'))
			if actionID then PlaceAction(actionID) return true end
		elseif self:IsModifiedClick() then
			if node.UpdateTooltip == ContainerFrameItemButton_OnUpdate then
				WrappedExecute(ContainerFrameItemButton_OnModifiedClick, {
					IsModifiedClick = function(action)
						return db.Gamepad:GetModifierHeld(GetModifiedClick(action))
					end;
				}, node, 'LeftButton')
				return true;
			end
		end
	end
end

function Hooks:IsModifiedClick()
	return next(db.Gamepad:GetModifiersHeld()) ~= nil;
end

function Hooks:IsCancelClick(button)
	return button == env.Settings:GetButton('Cancel');
end

function Hooks:GetSpecialClickHandler(node)
	return node and (node.OnSpecialClick or env.NodeAttr.GetSpecialClick(node));
end

function Hooks:GetCancelClickHandler(node)
	return node and (node.OnCancelClick or env.NodeAttr.GetCancelClick(node));
end

---------------------------------------------------------------
-- Node identification
---------------------------------------------------------------
do
	local IsWidget, GetID, GetParent, GetScript =
		C_Widget.IsFrameWidget, UIParent.GetID, UIParent.GetParent, UIParent.GetScript;

	local TryIdentifyContainerSlot = function(node)
		return env.TryIdentifyContainerSlot(node)
	end

	local TryIdentifyContainerBag = function(node)
		return GetScript(node, 'OnEnter') == ContainerFramePortraitButton_OnEnter and GetID(node) ~= 0;
	end

	local TryIdentifyMerchantItem = function(node)
		return node.UpdateTooltip == MerchantItemButton_OnEnter
			or node.UpdateTooltip == MerchantBuyBackButton_OnEnter;
	end

	function Hooks:GetItemLocationFromNode(node)
		return IsWidget(node) and TryIdentifyContainerSlot(node) and
			env.CreateItemLocationFromNode(node) or nil;
	end

	function Hooks:GetBagLocationFromNode(node)
		return IsWidget(node) and TryIdentifyContainerBag(node) and
			CPAPI.ContainerIDToInventoryID(node:GetID());
	end

	function Hooks:GetMerchantLinkFromNode(node)
		return IsWidget(node) and TryIdentifyMerchantItem(node) and node.link or nil;
	end
end

---------------------------------------------------------------
-- Prompts
---------------------------------------------------------------
function Hooks:IsPromptProcessingValid(node)
	return not InCombatLockdown()
		and db.Cursor:IsCurrentNode(node)
		and not env.NodeAttr.HasDisableHooks(node)
end

function Hooks:GetPrompt(action, text)
	local device = db('Gamepad/Active')
	local button = env.Settings:GetButton(action)
	return device and button and device:GetTooltipButtonPrompt(button, L(text), TOOLTIP_ICON_SIZE)
end

function Hooks:AddPrompt(tooltip, action, text)
	if not tooltip then return end
	local prompt = self:GetPrompt(action, text)
	if prompt then tooltip:AddLine(prompt) tooltip:Show() end
end

-- Used externally by Scripts.lua
function Hooks:GetSpecialActionPrompt(text)
	return self:GetPrompt('Special', text)
end

function Hooks:SetUseItemPrompt(tooltip, text)
	self:AddPrompt(tooltip, 'RightClick', text)
end

function Hooks:SetSellItemPrompt(tooltip, itemLocation)
	local bagID, slotID = itemLocation:GetBagAndSlot()
	if bagID and slotID and CPAPI.GetContainerItemInfo(bagID, slotID).hasNoValue == false then
		self:AddPrompt(tooltip, 'RightClick', L 'Sell')
	end
end

function Hooks:SetPendingActionToUtilityRing(tooltip, owner, action)
	if owner.ignoreUtilityRing then return end
	NodeState.pendingAction = action;
	local text;
	if ConsolePort:SetPendingRingAction(UTILITY_RING_INDEX, action) then
		text = 'Add to Utility Ring'
	else
		local _, existingIndex = ConsolePort:IsUniqueRingAction(UTILITY_RING_INDEX, action)
		if existingIndex then
			ConsolePort:SetPendingRingRemove(UTILITY_RING_INDEX, action)
			text = 'Remove from Utility Ring'
		end
	end
	if text then self:AddPrompt(tooltip, 'Special', text) end
end

---------------------------------------------------------------
-- Node-type handler registry
---------------------------------------------------------------
-- Handlers are iterated in ascending priority order during
-- OnTooltipSetItem processing. Each handler has:
--   key:         string identifier
--   identify:    function(owner, link, itemID) -> value|nil
--   handle:      function(tooltip, owner, link, itemID, value)
--   priority:    number (lower = earlier, default 100)
--   fallthrough: bool (continue after match, default false)
---------------------------------------------------------------
local NodeTypeHandlers = {};

local function SortHandlers()
	table.sort(NodeTypeHandlers, function(a, b) return a.priority < b.priority end)
end

function Hooks:RegisterNodeTypeHandler(key, identifyFunc, handleFunc, options)
	options = options or {};
	local entry = {
		key         = key,
		identify    = identifyFunc,
		handle      = handleFunc,
		priority    = type(options.priority) == 'number' and options.priority or 100,
		fallthrough = options.fallthrough or false,
	};
	NodeTypeHandlers[#NodeTypeHandlers + 1] = entry;
	SortHandlers();
end

---------------------------------------------------------------
-- Tooltip-type hook registry
---------------------------------------------------------------
-- Allows registering handlers for tooltip data types
-- (Spell, Mount, Toy, etc.) via a public API.
---------------------------------------------------------------
function Hooks:RegisterTooltipTypeHook(dataType, handler, options)
	options = options or {};
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[dataType], handler)
	end
	if not CPAPI.IsRetailVersion and options.script then
		GameTooltip:HookScript(options.script, handler)
	end
end

---------------------------------------------------------------
-- Tooltip hooks
---------------------------------------------------------------
do
	local function IsSpellKnown(spellID)
		if IsSpellKnownOrOverridesKnown(spellID) or IsPlayerSpell(spellID) then return true end
		local mountID = CPAPI.GetMountFromSpell(spellID)
		return mountID and select(11, CPAPI.GetMountInfoByID(mountID)) or false;
	end

	-- Common guard for all tooltip handlers.
	local function IsValidTooltipOwner(self, checkSpecialClick)
		local owner = self:GetOwner()
		if not Hooks:IsPromptProcessingValid(owner) then return end
		if checkSpecialClick and Hooks:GetSpecialClickHandler(owner) then return end
		return owner
	end

	---------------------------------------------------------------
	-- Register built-in node-type handlers
	---------------------------------------------------------------

	-- itemLocation: priority 10
	Hooks:RegisterNodeTypeHandler('itemLocation',
		function(owner)
			return Hooks:GetItemLocationFromNode(owner)
		end,
		function(tooltip, owner, link, itemID, itemLocation)
			if CPAPI.IsMerchantAvailable then
				Hooks:SetSellItemPrompt(tooltip, itemLocation)
			elseif itemID and CPAPI.IsEquippableItem(itemID) then
				Hooks:SetUseItemPrompt(tooltip, EQUIPSET_EQUIP or USE)
			elseif itemID and CPAPI.IsUsableItem(itemID) then
				Hooks:SetUseItemPrompt(tooltip, USE)
			end
			Hooks:SetPendingItemLocation(tooltip, itemLocation)
		end,
		{ priority = 10 }
	)

	-- bagLocation: priority 20
	Hooks:RegisterNodeTypeHandler('bagLocation',
		function(owner)
			return Hooks:GetBagLocationFromNode(owner)
		end,
		function(tooltip, owner, link, itemID, bagLocation)
			Hooks:SetPendingBagLocation(tooltip, bagLocation)
		end,
		{ priority = 20 }
	)

	-- merchantLink: priority 30, fallthrough
	Hooks:RegisterNodeTypeHandler('merchantLink',
		function(owner)
			return Hooks:GetMerchantLinkFromNode(owner)
		end,
		function(tooltip, owner, link, itemID, merchantLink)
			if HousingFramesUtil and C_HousingCatalog and merchantLink then
				if C_HousingCatalog.GetCatalogEntryInfoByItem(merchantLink, true) then
					Hooks:SetPendingHousingPreviewLink(tooltip, merchantLink)
				end
			end
		end,
		{ priority = 30, fallthrough = true }
	)

	-- housingPreview: priority 40, fallthrough
	Hooks:RegisterNodeTypeHandler('housingPreview',
		function(owner, link, itemID)
			return (itemID and link) or nil
		end,
		function(tooltip, owner, link, itemID, housingLink)
			if HousingFramesUtil and C_HousingCatalog and housingLink then
				if C_HousingCatalog.GetCatalogEntryInfoByItem(housingLink, true) then
					Hooks:SetPendingHousingPreviewLink(tooltip, housingLink)
				end
			end
		end,
		{ priority = 40, fallthrough = true }
	)

	---------------------------------------------------------------
	-- OnTooltipSetItem — iterates registered handlers
	---------------------------------------------------------------
	local function OnTooltipSetItem(self)
		local owner = IsValidTooltipOwner(self, true)
		if not owner then return end

		local _, link, itemID = self:GetItem()

		for _, handler in ipairs(NodeTypeHandlers) do
			local ok, value = pcall(handler.identify, owner, link, itemID)
			if ok and value then
				local hOk, hErr = pcall(handler.handle, self, owner, link, itemID, value)
				if not hOk then
					-- Handler error; continue to next handler
				end
				if not handler.fallthrough then return end
			end
		end

		if not link then return end

		local numOwned     = CPAPI.GetItemCount(link)
		local isEquipped   = CPAPI.IsEquippedItem(link)
		local isEquippable = CPAPI.IsEquippableItem(link)
		local isDressable  = CPAPI.IsDressableItemByID(link)
		local isMount      = itemID and CPAPI.GetMountFromItem(itemID)

		if CPAPI.GetItemSpell(link) and numOwned > 0 then
			Hooks:SetPendingActionToUtilityRing(self, owner, { type = 'item', item = link, link = link });
		elseif isEquippable and isEquipped then
			Hooks:SetPendingInspectItem(self, owner:GetID())
		elseif (isEquippable and not isEquipped) or isDressable or isMount then
			Hooks:SetPendingDressupItem(self, link);
		end
	end

	local function OnTooltipSetSpell(self)
		local owner = IsValidTooltipOwner(self, true)
		if not owner then return end

		local _, spellID = self:GetSpell()
		if spellID and not CPAPI.IsPassiveSpell(spellID) and IsSpellKnown(spellID) then
			Hooks:SetPendingSpellID(self, spellID)
		end
	end

	local function OnTooltipSetMount(self, info)
		local owner = IsValidTooltipOwner(self)
		if not owner then return end
		local mountInfo = { CPAPI.GetMountInfoByID(info.id) }
		if mountInfo[11] and mountInfo[2] and IsSpellKnown(mountInfo[2]) then
			Hooks:SetPendingSpellID(self, mountInfo[2])
		end
	end

	local function OnTooltipSetToy(self, info)
		local owner = IsValidTooltipOwner(self)
		if not owner then return end
		local itemID = type(info) == 'table' and info.id;
		if itemID and CPAPI.PlayerHasToy(itemID) then
			local itemInfo = CPAPI.GetItemInfo(itemID)
			Hooks:SetPendingActionToUtilityRing(self, owner, {
				type = 'item', item = itemInfo.itemLink, link = itemInfo.itemLink });
		end
	end

	local function OnTooltipSetItemLine(self, line)
		if self:IsForbidden() then return end
		local owner = self:GetOwner()
		if Hooks:IsPromptProcessingValid(owner) and Hooks:GetBagLocationFromNode(owner) then
			if (line.leftText or ''):match('^<') then
				line.leftText = Hooks:GetPrompt('RightClick', line.leftText) or line.leftText;
			end
		end
	end

	---------------------------------------------------------------
	-- Register built-in tooltip-type hooks
	---------------------------------------------------------------
	Hooks:RegisterTooltipTypeHook('Item',  OnTooltipSetItem,  { script = 'OnTooltipSetItem'  })
	Hooks:RegisterTooltipTypeHook('Spell', OnTooltipSetSpell, { script = 'OnTooltipSetSpell' })
	Hooks:RegisterTooltipTypeHook('Mount', OnTooltipSetMount)
	Hooks:RegisterTooltipTypeHook('Toy',   OnTooltipSetToy)

	-- Item line pre-call (Retail only)
	if TooltipDataProcessor and TooltipDataProcessor.AddLinePreCall then
		TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataType.Item, OnTooltipSetItemLine)
	end

	---------------------------------------------------------------
	-- Tooltip anchor and cleanup hooks
	---------------------------------------------------------------
	GameTooltip:HookScript('OnShow', function(self)
		local owner = self:GetOwner()
		if Hooks:IsPromptProcessingValid(owner) and self:GetAnchorType() == 'ANCHOR_CURSOR' then
			self:SetAnchorType('ANCHOR_TOPLEFT')
			self:Show()
		end
	end)

	GameTooltip:HookScript('OnHide', function()
		Hooks:OnNodeLeave()
	end)
end
