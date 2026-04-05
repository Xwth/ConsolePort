---------------------------------------------------------------
-- Scripts
---------------------------------------------------------------
-- Replace problematic scripts or add custom functionality.
-- Original functions become taint-bearing when called insecurely
-- because they modify properties of protected objects, either
-- directly or indirectly by execution path.

local env, db, _, L = CPAPI.GetEnv(...); _ = CPAPI.OnAddonLoaded;
local pcall = pcall;
local Scripts = CPAPI.Proxy({}, function(self, key) return rawget(rawset(self, key, {}), key) end);

local function ExecuteFrameScript(frame, scriptName, ...)
	local pre, main, post =
		frame:GetScript(scriptName, LE_SCRIPT_BINDING_TYPE_INTRINSIC_PRECALL),
		frame:GetScript(scriptName, LE_SCRIPT_BINDING_TYPE_EXTRINSIC),
		frame:GetScript(scriptName, LE_SCRIPT_BINDING_TYPE_INTRINSIC_POSTCALL);
	if pre  then pcall(pre, frame, ...) end;
	if main then pcall(main, frame, ...) end;
	if post then pcall(post, frame, ...) end;
end

function env.ExecuteScript(node, scriptType, ...)
	local script, ok, err = Scripts[scriptType][node:GetScript(scriptType) or node];
	if script then
		ok, err = pcall(script, node, ...)
	else
		ok, err = pcall(ExecuteFrameScript, node, scriptType, ...)
	end
	if not ok then
		CPAPI.Log('Script execution failed in %s handler:\n%s', scriptType, err)
	end
end

---------------------------------------------------------------
-- Public registration API
---------------------------------------------------------------
function env.RegisterScriptReplacement(scriptType, original, replacement)
	assert(type(scriptType)  == 'string',   'scriptType must be of type string'   )
	assert(type(original)    == 'function', 'original must be of type function'   )
	assert(type(replacement) == 'function', 'replacement must be of type function')
	Scripts[scriptType][original] = replacement;
end

-- Backward compatibility alias
env.ReplaceScript = env.RegisterScriptReplacement;

---------------------------------------------------------------
do -- FrameXML
---------------------------------------------------------------
	local ActionButtonOnEnter = ActionButton1 and ActionButton1:GetScript('OnEnter')
	if ActionButtonOnEnter then
		env.RegisterScriptReplacement('OnEnter', ActionButtonOnEnter, function(self)
			-- strips action bar highlights from action buttons
			ActionButton_SetTooltip(self)
		end)
	end
	local SpellButtonOnEnter = SpellButton1 and SpellButton1:GetScript('OnEnter')
	if SpellButtonOnEnter then
		env.RegisterScriptReplacement('OnEnter', SpellButtonOnEnter, function(self)
			-- spellbook buttons push updates to the action bar controller in order to draw highlights
			-- on actionbuttons that holds the spell in question. this taints the action bar controller.
			local slot = SpellBook_GetSpellBookSlot(self)
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetSpellBookItem(slot, SpellBookFrame.bookType)

			if ( self.SpellHighlightTexture and self.SpellHighlightTexture:IsShown() ) then
				GameTooltip:AddLine(SPELLBOOK_SPELL_NOT_ON_ACTION_BAR, LIGHTBLUE_FONT_COLOR.r, LIGHTBLUE_FONT_COLOR.g, LIGHTBLUE_FONT_COLOR.b)
			end
			GameTooltip:Show()
		end)
	end
	local SpellButtonOnLeave = SpellButton_OnLeave or SpellButton1 and SpellButton1:GetScript('OnLeave')
	if SpellButtonOnLeave then
		env.RegisterScriptReplacement('OnLeave', SpellButtonOnLeave, function(self)
			GameTooltip:Hide()
		end)
	end
end

---------------------------------------------------------------
do -- Misc addon fixes
---------------------------------------------------------------
	_('Blizzard_HelpPlate', function()
		env.RegisterScriptReplacement('OnEnter', HelpPlateButtonMixin.OnEnter, function(self)
			ExecuteFrameScript(self:GetParent(), 'OnEnter')
		end)
	end)
end
