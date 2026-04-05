local env, db, _, L = CPAPI.GetEnv(...); _ = CPAPI.OnAddonLoaded;
if not CPAPI.IsRetailVersion then return end;
local RunNextFrame = RunNextFrame;
---------------------------------------------------------------
-- Compat/Retail.lua
-- Retail-only cursor compatibility code.
---------------------------------------------------------------

-- Node identification: Retail container slot detection
env.TryIdentifyContainerSlot = function(node)
	return node.GetSlotAndBagID == ContainerFrameItemButtonMixin.GetSlotAndBagID;
end

-- Node identification: Retail item location constructor
env.CreateItemLocationFromNode = function(node)
	return ItemLocation:CreateFromBagAndSlot(node:GetBagID(), node:GetID())
end

---------------------------------------------------------------
-- Retail-only script replacements (moved from Scripts.lua)
-- Uses _() for deferred loading and env.RegisterScriptReplacement
-- for taint-safe script substitution.
---------------------------------------------------------------

-----------------------------------------------------------
-- Blizzard_Collections: ToySpellButton_OnEnter
-----------------------------------------------------------
_('Blizzard_Collections', function()
	env.RegisterScriptReplacement('OnEnter', ToySpellButton_OnEnter, function(self)
		-- Strip fanfare/UpdateTooltip from toy spell buttons,
		-- since the taint prevents UseToy from working.
		if self.itemID then
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetToyByItemID(self.itemID)
			GameTooltip:Show()
		end
	end)
end)


-----------------------------------------------------------
-- Blizzard_HousingTemplates: BaseHousingActionButtonMixin
-----------------------------------------------------------
_('Blizzard_HousingTemplates', function()
	env.RegisterScriptReplacement('OnEnter', BaseHousingActionButtonMixin.OnEnter, function(self)
		self.IsMouseMotionFocus = CPAPI.Static(true);
		return BaseHousingActionButtonMixin.OnEnter(self)
	end)
	env.RegisterScriptReplacement('OnLeave', BaseHousingActionButtonMixin.OnLeave, function(self)
		CPAPI.Purge(self, 'IsMouseMotionFocus')
		return BaseHousingActionButtonMixin.OnLeave(self)
	end)
end)


-----------------------------------------------------------
-- Blizzard_DelvesCompanionConfiguration: CompanionConfigSlotTemplateMixin
-----------------------------------------------------------
_('Blizzard_DelvesCompanionConfiguration', function()
	-- CheckToggleAllowed() calls ClosestUnitPosition() which returns secret values.
	-- Skip the check on hover; and skip the check in OnMouseDown.
	env.RegisterScriptReplacement('OnEnter', CompanionConfigSlotTemplateMixin.OnEnter, function(self)
		if self:HasSelectionAndInfo() then
			local selection = self.selectionNodeOptions[self.selectionNodeInfo.activeEntry.entryID];
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT', -5, -30)
			local spellID = selection.overriddenSpellID or selection.spellID;
			if spellID then
				GameTooltip:SetSpellByID(spellID, false)
			elseif selection.name and selection.description then
				GameTooltip_SetTitle(GameTooltip, selection.name)
				GameTooltip_AddNormalLine(GameTooltip, selection.description)
			end
			GameTooltip:Show()
		end
		self.HighlightTexture:Show()
		self.BorderHighlight:Show()
	end)
	env.RegisterScriptReplacement('OnMouseDown', CompanionConfigSlotTemplateMixin.OnMouseDown, function(self)
		if not self:IsEnabled() then
			return;
		end
		if not self.toggleNotAllowed then
			if self.OptionsList:IsShown() then
				self.OptionsList:Hide();

				if self.NewLabel:IsShown() then
					self.NewLabel:Hide();
					self.NewGlowHighlight:Hide();
				end
			else
				self.OptionsList:Show();
				self:SetSeenCurios();
			end
		end
	end)
end)


-----------------------------------------------------------
-- Blizzard_PlayerSpells: Talent frame customization
-----------------------------------------------------------
_('Blizzard_PlayerSpells', function()
	-- Talent frame customization:
	-- Remove action bar highlights from talent buttons, since they taint the action bar controller.
	-- Also, add a special click handler to split talent buttons, so that they can be selected by clicking on them,
	-- instead of on mouseover. Finally, hook the spell menu to remove focus from the talent frame so that
	-- pickups and bar placements from the talent frame can go smoothly.

	local selectionChoiceFrame = PlayerSpellsFrame.TalentsFrame.SelectionChoiceFrame;
	local currentBaseButton;

	local function HideChoiceFrame() selectionChoiceFrame:Hide() end

	env.RegisterScriptReplacement('OnEnter', ClassTalentButtonSpendMixin.OnEnter, function(self)
		HideChoiceFrame()
		TalentButtonSpendMixin.OnEnter(self)
	end)
	env.RegisterScriptReplacement('OnEnter', ClassTalentButtonSelectMixin.OnEnter, function(self)
		HideChoiceFrame()
		TalentButtonSelectMixin.OnEnter(self)
	end)
	env.RegisterScriptReplacement('OnEnter', ClassTalentSelectionChoiceMixin.OnEnter, TalentDisplayMixin.OnEnter)
	env.RegisterScriptReplacement('OnEnter', ClassTalentButtonSplitSelectMixin.OnEnter, function(self)
		env.NodeAttr.SetSpecialClick(self, function(self, button, down)
			TalentButtonSplitSelectMixin.OnEnter(self)
			RunNextFrame(function()
				env.Cursor:SetCurrentNode(selectionChoiceFrame.selectionFrameArray[1])
			end)
		end)

		HideChoiceFrame()
		currentBaseButton = self;

		local prompt = env.Hooks:GetSpecialActionPrompt(INSPECT_TALENTS_BUTTON)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		local spellID = self:GetSpellID()
		if spellID then
			GameTooltip:SetSpellByID(spellID)
			GameTooltip:AddLine(prompt)
		else
			GameTooltip:SetText(prompt)
		end
		GameTooltip:Show()
	end)

	selectionChoiceFrame:HookScript('OnHide', function(self)
		if currentBaseButton then
			RunNextFrame(function()
				env.Cursor:SetCurrentNode(currentBaseButton)
				currentBaseButton = nil;
			end)
		end
	end)

	-- Remove clearing of action bar highlights from talent buttons, since they taint the action bar controller.
	-- When leaving a split choice talent popup, hide the popup if the cursor is not over a nested selection button.
	env.RegisterScriptReplacement('OnLeave', ClassTalentButtonSpendMixin.OnLeave, function(self)
		HideChoiceFrame()
		TalentDisplayMixin.OnLeave(self)
	end)
	env.RegisterScriptReplacement('OnLeave', ClassTalentButtonSelectMixin.OnLeave, function(self)
		HideChoiceFrame()
		TalentButtonSelectMixin.OnLeave(self)
	end)

	env.RegisterScriptReplacement('OnLeave', ClassTalentButtonSplitSelectMixin.OnLeave, ClassTalentButtonSplitSelectMixin.OnLeave)
	env.RegisterScriptReplacement('OnLeave', ClassTalentSelectionChoiceMixin.OnLeave, function(self)
		TalentDisplayMixin.OnLeave(self)
		RunNextFrame(function()
			if ConsolePortSpellMenu:IsShown() then return end;

			local currentNode = env.Cursor:GetCurrentNode()
			if currentNode and currentNode:GetParent() ~= selectionChoiceFrame then
				selectionChoiceFrame:Hide()
			end
		end)
	end)

	ConsolePortSpellMenu:HookScript('OnShow', function()
		if PlayerSpellsFrame:IsShown() then
			PlayerSpellsFrame:SetAlpha(0.25)
			env.NodeAttr.SetIgnored(PlayerSpellsFrame, true)
		end
	end)
	ConsolePortSpellMenu:HookScript('OnHide', function()
		if env.NodeAttr.IsIgnored(PlayerSpellsFrame) then
			PlayerSpellsFrame:SetAlpha(1)
			env.NodeAttr.SetIgnored(PlayerSpellsFrame, nil)
		end
	end)
end)


---------------------------------------------------------------
-- Blizzard_MapCanvas / Blizzard_SharedMapDataProviders:
-- MapCanvasPinMixin taint-safety
---------------------------------------------------------------
_('Blizzard_MapCanvas', function()
	_('Blizzard_SharedMapDataProviders', function()
		-- Map pins OnEnter/OnLeave scripts propagate to basically everywhere on the map,
		-- resulting in widespread taint. Because it's too ardous to figure out which taint
		-- is caused by which pin type, we just apply a safe mixin to all pins that
		-- overrides the problematic methods, so that they are not allowed to execute in
		-- combat. This is a bad solution, but it works for now.
		--
		-- Wouldn't it be nice if we could execute OnEnter/OnLeave securely out of combat?

		local SafePinMixin = {};
		function SafePinMixin:SetPassThroughButtons(...)
			db:RunSafe(GenerateClosure(CPAPI.Index(self).SetPassThroughButtons, self), ...)
		end

		function SafePinMixin:SetPropagateMouseClicks(...)
			db:RunSafe(GenerateClosure(CPAPI.Index(self).SetPropagateMouseClicks, self), ...)
		end

		local function FixPinTaint(pin)
			Mixin(pin, SafePinMixin);
		end

		local cachedPins, worldMapTainted = {}, false;
		local function FixCachedPinTaint()
			worldMapTainted = true;
			for pin in pairs(cachedPins) do
				FixPinTaint(pin);
			end
			wipe(cachedPins);
		end

		local function PinTemplateDefaultHandler(map, pinTemplate)
			for pin in map:EnumeratePinsByTemplate(pinTemplate) do
				if worldMapTainted then
					FixPinTaint(pin);
				elseif not cachedPins[pin] then
					cachedPins[pin] = true;
					env.RegisterScriptReplacement('OnEnter', pin.OnMouseEnter, function(self)
						FixCachedPinTaint()
						return self:OnMouseEnter()
					end)
					env.RegisterScriptReplacement('OnLeave', pin.OnMouseLeave, function(self)
						FixCachedPinTaint()
						return self:OnMouseLeave()
					end)
				end
			end
		end

		local PinTemplateHandlers = CPAPI.Proxy({
			DungeonEntrancePinTemplate = function(map, pinTemplate)
				-- Invoking EncounterJournal_OpenJournal used to taint the UI
				-- panel manager, but this does not seem to be the case anymore.
				-- Leaving this here in case the issue resurfaces.
				PinTemplateDefaultHandler(map, pinTemplate)
			end;
		}, CPAPI.Static(PinTemplateDefaultHandler));

		hooksecurefunc(WorldMapFrame, 'AcquirePin', function(map, pinTemplate)
			PinTemplateHandlers[pinTemplate](map, pinTemplate)
		end)
	end)
end)

---------------------------------------------------------------
-- Retail menu strategy for shoulder menu navigation
---------------------------------------------------------------
local RetailMenuStrategy = {};

function RetailMenuStrategy:FindDropdown(node)
	local current = node;
	while current do
		if current.IsObjectType and current:IsObjectType('DropdownButton') then
			return current;
		end
		if current.menuGenerator then
			return current;
		end
		current = current.GetParent and current:GetParent() or nil;
	end
end

function RetailMenuStrategy:OpenMenu(dropdown)
	if not dropdown:GetMenuDescription() then
		dropdown:GenerateMenu();
	end
	dropdown:OpenMenu();
end

function RetailMenuStrategy:CollectSelectableItems(dropdown)
	local rootDesc = dropdown:GetMenuDescription();
	if not rootDesc then return {} end;
	local items = {};
	MenuUtil.TraverseMenu(rootDesc, function(desc)
		if desc:IsEnabled() and desc:CanSelect() then
			items[#items + 1] = desc;
		end
	end);
	return items;
end

function RetailMenuStrategy:HighlightItem(desc)
	local frame = desc.frame;
	if not frame then return end;
	local onEnter = frame:GetScript('OnEnter');
	if onEnter then onEnter(frame) end;
end

function RetailMenuStrategy:UnhighlightItem(desc)
	local frame = desc.frame;
	if not frame then return end;
	local onLeave = frame:GetScript('OnLeave');
	if onLeave then onLeave(frame) end;
end

function RetailMenuStrategy:PickItem(desc)
	return securecallfunction(desc.Pick, desc, MenuInputContext.MouseButton);
end

function RetailMenuStrategy:CloseMenu()
	Menu.GetManager():CloseMenus();
end

function RetailMenuStrategy:IsMenuVisible()
	local mgr = Menu.GetManager();
	return mgr and mgr:GetOpenMenu() ~= nil;
end

function RetailMenuStrategy:SilentCycle(dropdown, delta)
	if delta > 0 then
		dropdown:Increment();
	else
		dropdown:Decrement();
	end
end

env.MenuStrategy = RetailMenuStrategy;
