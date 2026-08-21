---@type string, Spotlights
local _, Private = ...

--- The Click Casting tab: the bindings that cast on a spotlight and nowhere else, and the one gesture that
--- makes one -- type a spell ID, then press the combination you want it on.
---
--- **A binding is captured, not picked from a list.** The combinations that can carry one are every button
--- the mouse has, every key the keyboard has and both wheel directions, against every modifier -- a list
--- nobody wants to scroll; and the prompts below have to be about the combination that was actually pressed
--- anyway, since only the client can say what it already spends that click or key on.
---
--- Which route a capture takes is decided by which script caught it: `OnClick` is a mouse button and
--- everything else is a chord. Nothing normalises between them, because they are stored and dispatched
--- differently all the way down -- see `ClickCasts.lua`.

--- A row is two lines, the spell and what it is bound to, so it is taller than a control row and the icon
--- is sized to both lines rather than either. The same numbers the Tracked pane's spell rows use, because
--- the two lists are meant to read as one design.
local ROW_HEIGHT = 32
local ROW_INSET = 4
local ICON_SIZE = 24
local TEXT_GAP = 6

--- What the combination is drawn in, at the row's trailing edge, as the client's own click-binding list
--- draws it. Fixed rather than measured so every row's spell name ends in the same column, and wide enough
--- for a modified chord now that keys are bindable.
local BINDING_WIDTH = 200

local REMOVE_WIDTH = 20
local REMOVE_ICON_SIZE = 16
local REMOVE_HIGHLIGHT_ALPHA = 0.18
local HIGHLIGHT_ALPHA = Private.Controls.HighlightAlpha

--- The add row, mirroring the Tracked pane's: the box, the button, and a preview of what is typed. Nine
--- digits is more than any spell ID has needed.
local INPUT_WIDTH = 70
local INPUT_GAP = 14
local BUTTON_HEIGHT = 22
local BIND_TEXT_PADDING = 20
local BIND_GAP = 8
local PREVIEW_GAP = 10
local PREVIEW_ICON_SIZE = 20
local MAX_ID_DIGITS = 9

--- How long the typed ID is left alone before it is looked up, for the reason the Tracked pane debounces
--- its own: an ID is typed a digit at a time and most prefixes name nothing.
local LOOKUP_DELAY = 0.35

local GAP = 6

--- In case the window is shorter than this tab's chrome costs: better a cramped list than a negative height
--- Blizzard errors on.
local MIN_LIST_HEIGHT = 60

--- How far above the page the capture overlay is lifted. A round number rather than a measurement: the rows
--- it has to cover sit inside a scroll frame inside a pane, and the depth of that nesting is not this
--- file's business.
local OVERLAY_LEVEL = 100
local OVERLAY_ALPHA = 0.75
local OVERLAY_TEXT_INSET = 40

--- Registered at prompt time so the localisation table is filled by then, one key per prompt so
--- `StaticPopup_Show` reuses the dialog rather than stacking a second identical one.
local OVERRIDE_POPUP = "SPOTLIGHTS_CLICKCAST_OVERRIDE"
local DORMANT_POPUP = "SPOTLIGHTS_CLICKCAST_DORMANT"
local KEY_POPUP = "SPOTLIGHTS_CLICKCAST_KEY"

--- What the overlay is waiting for: the spell to bind, and the row it replaces when this is a rebind.
--- Transient, like the Tracked pane's search text -- a gesture in progress rather than a setting.
---@type { spellID: integer, replaces: integer? }?
local pending

--- The overlay itself and the add row's box, held as file locals because both are reached from handlers
--- that are not inside the node holding them.
---@type Frame?
local overlay

---@type EditBox?
local input

--- What a spell row shows, given an ID the client may not have cached yet. A missing name is not an error:
--- `C_Spell.GetSpellName` answers nil until the client has the data, so the ID stands in and the next pass
--- picks up the real one.
---@param spellID integer
---@return string label, string|integer texture
local function SpellDisplay(spellID)
	return C_Spell.GetSpellName(spellID) or tostring(spellID),
		C_Spell.GetSpellTexture(spellID) or QUESTION_MARK_ICON
end

--- Whether the character has the spell at all. Naming a spell is not evidence an ID is the intended one --
--- every ID names something -- so this is what the preview cannot say by itself.
---
--- Both banks and overrides, unlike the client's own list (`Blizzard_ClickBindingUI.lua:632-638`), because
--- this only warns: a pet ability or a talent-replaced base ID is a binding that works, and warning about
--- one costs more than staying quiet about the few IDs a character can cast without owning.
---@param spellID integer
---@return boolean
local function Known(spellID)
	local includeOverrides = true

	return C_SpellBook.IsSpellKnownOrInSpellBook(spellID, Enum.SpellBookSpellBank.Player, includeOverrides)
		or C_SpellBook.IsSpellKnownOrInSpellBook(spellID, Enum.SpellBookSpellBank.Pet, includeOverrides)
end

--- Takes the overlay down and forgets what it was waiting for. Both halves, always: an overlay left up with
--- nothing pending swallows every click on the tab.
local function Disarm()
	pending = nil

	if overlay then
		overlay:Hide()
	end
end

--- Arms the capture overlay for a spell, replacing a row when this is a rebind rather than a new binding.
---@param spellID integer
---@param replaces integer?
local function Arm(spellID, replaces)
	if not overlay then
		return
	end

	pending = { spellID = spellID, replaces = replaces }

	overlay:Show()
end

--- Writes a captured binding, taking the row it replaces out first: a rebind moves the binding to another
--- combination, and the row it came from is keyed by the old one.
---@param binding SpotlightsClickCast
---@param replaces integer?
local function Commit(binding, replaces)
	if replaces then
		Private.ClickCasts.Remove(replaces)
	elseif input then
		-- Only the add row's box, and only once its binding landed: a rebind must not throw away a spell ID
		-- typed and not yet bound.
		input:SetText("")
		input:ClearFocus()
	end

	Private.ClickCasts.Store(binding)
	Private.Options.Refresh()
end

--- The game's own Target or context-menu binding sits on this combination, and ours genuinely replaces it
--- on spotlights: the interaction path rewrites which suffix is read but still dispatches our attribute
--- (`SecureTemplates.lua:863-867`).
---@param binding SpotlightsClickCast
---@param replaces integer?
---@param label string
local function ConfirmOverride(binding, replaces, label)
	local L = Private.L.Settings

	StaticPopupDialogs[OVERRIDE_POPUP] = {
		text = string.format(L.ClickCastOverridePrompt, label, Private.ClickCasts.Describe(binding)),
		button1 = L.ClickCastOverrideConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Commit(binding, replaces)
		end,
	}

	StaticPopup_Show(OVERRIDE_POPUP)
end

--- The game has a spell, macro or pet action on this combination, and **the game wins**:
--- `SecureUnitButton_OnClick` executes it and returns before our attributes are read
--- (`SecureTemplates.lua:851-858`). Stored anyway rather than refused -- the row comes alive by itself the
--- moment the user clears the client's binding, and a refusal leaves them re-entering it later with no
--- memory of having tried.
---@param binding SpotlightsClickCast
---@param replaces integer?
---@param label string?
local function ConfirmDormant(binding, replaces, label)
	local L = Private.L.Settings

	StaticPopupDialogs[DORMANT_POPUP] = {
		text = string.format(L.ClickCastDormantPrompt, label or UNKNOWN,
			Private.ClickCasts.Describe(binding)),
		button1 = L.ClickCastSaveAnyway,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Commit(binding, replaces)
		end,
	}

	StaticPopup_Show(DORMANT_POPUP)
end

--- A key binding is an *override* (`SetOverrideBindingClick` with priority), so it always wins: while a
--- spotlight is hovered the key stops doing whatever the user has it on. That makes this a confirmation
--- rather than the dormant case -- the row is never inert.
---
--- Two texts, because "your own keybind" and "another addon already overrides this" are different sentences.
--- Neither claims more than `GetBindingAction` can see: an addon that reads keys through its own `OnKeyDown`
--- registers no binding at all, and which of two addons' overrides wins is not queryable.
---@param binding SpotlightsClickCast
---@param replaces integer?
---@param label string
---@param overridden boolean the conflict is another addon's override rather than the user's own keybind
local function ConfirmKeyOverride(binding, replaces, label, overridden)
	local L = Private.L.Settings

	StaticPopupDialogs[KEY_POPUP] = {
		text = string.format(overridden and L.ClickCastKeyOverriddenPrompt or L.ClickCastKeyBoundPrompt,
			label, Private.ClickCasts.Describe(binding)),
		button1 = L.ClickCastOverrideConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Commit(binding, replaces)
		end,
	}

	StaticPopup_Show(KEY_POPUP)
end

--- What the keybinding system already spends a chord on, and what to call it.
---
--- Both passes, because `checkOverride` answers with the override when there is one and the plain binding
--- otherwise, so the two together tell an addon's override from the user's own keybind. This is the same
--- conflict check the game's own keybinding UI runs before it rebinds a key
--- (`Blizzard_Keybindings.lua:127`), and `GetBindingName` is what names the binding it is about to steal.
---
--- `bindingContext` is left nil deliberately: the non-default contexts are the housing editor's, and a
--- spotlight is not hovered inside one.
---@param key string
---@return string? label, boolean overridden
local function KeyConflict(key)
	local bound = GetBindingAction(key)
	local checkOverride = true
	local effective = GetBindingAction(key, checkOverride)

	if effective ~= "" and effective ~= bound then
		return GetBindingName(effective), true
	end

	if bound ~= "" then
		return GetBindingName(bound), false
	end

	return nil, false
end

--- Turns the key or wheel direction the overlay caught into a binding.
---
--- The chord comes from `CreateKeyChordStringUsingMetaKeyState` rather than a hand-built prefix because it
--- is the string `SetBindingClick` and `GetBindingAction` are both handed: a modifier order the binding
--- system does not use binds nothing and detects nothing.
---@param key string
local function CapturedKey(key)
	-- The bare modifiers, which are held rather than pressed, and `UNKNOWN`. `BUTTON1` and `BUTTON2` are in
	-- that list too -- correct for a keybinding UI, wrong for us -- which is why this guards the key route
	-- only, after `OnClick` has claimed every real button press.
	if IsKeyPressIgnoredForBinding(key) then
		return
	end

	local chord = CreateKeyChordStringUsingMetaKeyState(key)
	local request = pending

	Disarm()

	if not request then
		return
	end

	---@type SpotlightsClickCast
	local binding = { key = chord, spellID = request.spellID }
	local label, overridden = KeyConflict(chord)

	if label then
		ConfirmKeyOverride(binding, request.replaces, label, overridden)
	else
		Commit(binding, request.replaces)
	end
end

--- Turns the click the overlay caught into a binding.
---
--- The prefix comes from `SecureButton_GetModifierPrefix` and the bitfield from `MakeModifiers`, both read
--- here while the keys are still held, so the two projections cannot disagree -- see `SpotlightsClickCast`.
---@param button string
local function Captured(button)
	local request = pending

	Disarm()

	if not request then
		return
	end

	local modifiers = MakeModifiers()

	---@type SpotlightsClickCast
	local binding = {
		button = button,
		prefix = SecureButton_GetModifierPrefix(),
		modifiers = modifiers,
		spellID = request.spellID,
	}

	local bindingType, label = Private.ClickCasts.GameBinding(button, modifiers)

	if bindingType == Enum.ClickBindingType.Interaction then
		ConfirmOverride(binding, request.replaces, label or UNKNOWN)
	elseif bindingType ~= Enum.ClickBindingType.None then
		ConfirmDormant(binding, request.replaces, label)
	else
		Commit(binding, request.replaces)
	end
end

--- The capture surface: everything on the tab, covered, so no click during the gesture can land on a row or
--- a button behind it.
---
--- Keyboard input is taken and **not propagated**, which is what makes Escape cancel rather than close the
--- panel: the window is in `UISpecialFrames` and would otherwise go with it. Given back on the way out,
--- since a frame holding the keyboard while invisible is a chat box nobody can type in.
---@param page Frame
---@return Frame
local function BuildOverlay(page)
	local frame = CreateFrame("Button", nil, page)

	frame:SetAllPoints(page)
	frame:SetFrameLevel(page:GetFrameLevel() + OVERLAY_LEVEL)
	frame:RegisterForClicks("AnyUp")

	-- Once rather than per arming, unlike the keyboard: a hidden frame receives no wheel either way, and
	-- nothing else on the tab scrolls with the overlay up.
	frame:EnableMouseWheel(true)
	frame:Hide()

	local backdrop = frame:CreateTexture(nil, "BACKGROUND")

	backdrop:SetAllPoints(frame)
	backdrop:SetColorTexture(0, 0, 0, OVERLAY_ALPHA)

	local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")

	text:SetPoint("LEFT", frame, "LEFT", OVERLAY_TEXT_INSET, 0)
	text:SetPoint("RIGHT", frame, "RIGHT", -OVERLAY_TEXT_INSET, 0)
	text:SetJustifyH("CENTER")
	text:SetWordWrap(true)

	frame:SetScript("OnShow", function(self)
		local spellID = pending and pending.spellID
		local name = spellID and SpellDisplay(spellID) or ""

		text:SetText(string.format(Private.L.Settings.ClickCastCapture, name))

		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
	end)

	frame:SetScript("OnHide", function(self)
		self:EnableKeyboard(false)
		self:SetPropagateKeyboardInput(true)

		pending = nil
	end)

	frame:SetScript("OnKeyDown", function(_, key)
		-- Escape is spent on cancelling rather than offered as a binding, and `IsKeyPressIgnoredForBinding`
		-- does not reject it.
		if key == "ESCAPE" then
			Disarm()

			return
		end

		CapturedKey(key)
	end)

	-- The wheel reaches the binding system as `MOUSEWHEELUP`/`MOUSEWHEELDOWN`, which are binding keys and
	-- never button suffixes, so it rides the key route rather than the click one.
	frame:SetScript("OnMouseWheel", function(_, delta)
		CapturedKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
	end)

	frame:SetScript("OnClick", function(_, button)
		Captured(button)
	end)

	return frame
end

--- `ANCHOR_RIGHT` so the tooltip stands outside the list rather than over the rows under the cursor.
---@param owner Frame
---@param spellID integer?
local function ShowSpellTooltip(owner, spellID)
	if not spellID then
		return
	end

	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(spellID)
end

--- Drops the tooltip when the frame it belongs to goes away under the cursor, which `OnLeave` does not
--- answer. Owner-checked, since by then something else may have taken it.
---@param self Frame
local function HideSpellTooltip(self)
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

---@class SpotlightsClickCastRow : Button
---@field icon Texture
---@field label FontString
---@field meta FontString the conflict note, or the spell ID when there is nothing to warn about
---@field binding FontString
---@field remove Button
---@field spellID integer? which spell the row currently stands for

--- One pooled binding row. A `Button`, because clicking it is how a binding is moved to another
--- combination; the remove button sits on top and keeps its own clicks.
---@param list Frame
---@param rows SpotlightsClickCastRow[]
---@param index integer
---@return SpotlightsClickCastRow
local function AcquireRow(list, rows, index)
	local row = rows[index]

	if row then
		return row
	end

	row = CreateFrame("Button", nil, list) --[[@as SpotlightsClickCastRow]]

	row:SetHeight(ROW_HEIGHT)

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")

	highlight:SetAllPoints(row)
	highlight:SetColorTexture(1, 1, 1, HIGHLIGHT_ALPHA)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("LEFT", row, "LEFT", ROW_INSET, 0)

	-- The border every icon file ships with, cropped off, exactly as the aura displays crop theirs.
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(REMOVE_WIDTH, ROW_HEIGHT - 2)
	row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	-- The same red exit atlas the roster's and the Tracked pane's remove buttons use, so the gesture looks
	-- the same everywhere in the panel.
	local removeIcon = row.remove:CreateTexture(nil, "ARTWORK")

	removeIcon:SetPoint("CENTER")
	removeIcon:SetSize(REMOVE_ICON_SIZE, REMOVE_ICON_SIZE)
	removeIcon:SetAtlas("RedButton-Exit")

	local removeHighlight = row.remove:CreateTexture(nil, "HIGHLIGHT")

	removeHighlight:SetPoint("CENTER")
	removeHighlight:SetSize(REMOVE_ICON_SIZE, REMOVE_ICON_SIZE)
	removeHighlight:SetColorTexture(1, 1, 1, REMOVE_HIGHLIGHT_ALPHA)

	row.binding = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.binding:SetPoint("RIGHT", row.remove, "LEFT", -TEXT_GAP, 0)
	row.binding:SetWidth(BINDING_WIDTH)
	row.binding:SetJustifyH("RIGHT")
	row.binding:SetWordWrap(false)

	-- Both lines anchored at each end, the right one against the combination rather than the row: a spell
	-- name running under its own binding text would read as one string.
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", TEXT_GAP, 0)
	row.label:SetPoint("RIGHT", row.binding, "LEFT", -TEXT_GAP, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.meta = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.meta:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -1)
	row.meta:SetPoint("RIGHT", row.binding, "LEFT", -TEXT_GAP, 0)
	row.meta:SetJustifyH("LEFT")
	row.meta:SetWordWrap(false)

	-- Read off the row rather than closed over, which lets these be set once while the click handlers are
	-- rebound every pass: a captured ID would be the previous binding's.
	local function ShowRowTooltip()
		ShowSpellTooltip(row, row.spellID)
	end

	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row.remove:SetScript("OnEnter", ShowRowTooltip)
	row.remove:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnHide", HideSpellTooltip)

	rows[index] = row

	return row
end

--- What a row's second line says about the client's own bindings, re-read on every pass rather than stored:
--- a combination that was free when it was bound can be taken later, and nothing fires when it is.
---
--- Mouse rows only. `C_ClickBindings` is a mouse-only system, and a key row's own conflict is an override
--- our binding outranks, so there is no state a key row could be dormant in.
---@param binding SpotlightsClickCast
---@return string text, boolean dormant
local function Note(binding)
	local L = Private.L.Settings

	if Private.ClickCasts.KeyOf(binding) then
		return tostring(binding.spellID), false
	end

	local bindingType, label = Private.ClickCasts.GameBinding(binding.button, binding.modifiers)

	if bindingType == Enum.ClickBindingType.Interaction then
		return string.format(L.ClickCastOverrides, label or UNKNOWN), false
	end

	if bindingType ~= Enum.ClickBindingType.None then
		return string.format(L.ClickCastDormant, label or UNKNOWN), true
	end

	return tostring(binding.spellID), false
end

--- The list of bindings. Rows are configured in `Refresh` and anchored in `Layout`, which is the kit's own
--- split: what a row says depends on the database, where it sits depends on a width this node is not handed
--- until afterwards.
---@param page Frame
---@return SpotlightsNode
local function BuildList(page)
	local list = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	---@type SpotlightsClickCastRow[]
	local rows = {}

	local shown = 0

	function list:Refresh()
		local bindings = Private.ClickCasts.Get()

		shown = #bindings

		for i = 1, shown do
			local binding = bindings[i]
			local row = AcquireRow(list, rows, i)
			local label, texture = SpellDisplay(binding.spellID)
			local note, dormant = Note(binding)

			row.spellID = binding.spellID
			row.icon:SetTexture(texture)
			row.label:SetText(label)
			row.binding:SetText(Private.ClickCasts.Describe(binding))
			row.meta:SetText(note)
			row.meta:SetTextColor((dormant and RED_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())

			-- The row can change binding under a cursor that never moved -- removing one pulls the next up
			-- into the row being hovered -- and no `OnEnter` fires for a frame the cursor has not left.
			if GameTooltip:IsShown() and GameTooltip:GetOwner() == row then
				ShowSpellTooltip(row, binding.spellID)
			end

			-- Rebound on every pass rather than captured once, because the rows are pooled: a handler closed
			-- over the position this frame stood for last time would act on the wrong binding.
			row:SetScript("OnClick", function()
				Arm(binding.spellID, i)
			end)

			row.remove:SetScript("OnClick", function()
				Private.ClickCasts.Remove(i)

				-- A row has gone, which is a height as well as a repaint, and the height is derived from
				-- `Refresh` -- so the whole pass rather than a relayout.
				Private.Options.Refresh()
			end)

			row:Show()
		end

		for i = shown + 1, #rows do
			rows[i]:Hide()
		end
	end

	function list:Layout(width)
		self:SetWidth(width)

		local offset = 0

		for i = 1, shown do
			local row = rows[i]

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)

			offset = offset + ROW_HEIGHT
		end

		-- The scroll pane above reads this as its extent, so a shorter list shortens the bar rather than
		-- leaving empty space under the last row.
		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return list
end

--- The add row. **The preview is the point**: a spell ID cannot be proofread, so the only way to know a
--- number is not a typo is to be shown the icon and name before committing -- and the Bind button stays
--- dark until there is something to be shown, which is the whole of this row's validation.
---@param page Frame
---@return SpotlightsNode
local function BuildAddRow(page)
	local L = Private.L.Settings
	local node = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local caption = node:CreateFontString(nil, "ARTWORK", "GameFontNormal")

	caption:SetPoint("LEFT", node, "LEFT", 0, 0)
	caption:SetJustifyH("LEFT")
	caption:SetWordWrap(false)
	caption:SetText(L.AuraCustomSpellID)

	local box = CreateFrame("EditBox", nil, node, "InputBoxTemplate")

	box:SetSize(INPUT_WIDTH, Private.Controls.RowHeight - 6)
	box:SetAutoFocus(false)

	-- Digits only, as the Tracked pane's box is: refusing the keystroke is a clearer answer than accepting
	-- text and rejecting it afterwards.
	box:SetNumeric(true)
	box:SetMaxLetters(MAX_ID_DIGITS)

	input = box

	local bind = CreateFrame("Button", nil, node, "UIPanelButtonTemplate")

	bind:SetHeight(BUTTON_HEIGHT)
	bind:SetPoint("LEFT", box, "RIGHT", BIND_GAP, 0)
	bind:SetText(L.ClickCastBind)

	-- Beside the box rather than under it: a row that grew when a preview appeared would push the answer to
	-- what had just been typed down the tab. Filling space the row already occupies cannot.
	local icon = node:CreateTexture(nil, "ARTWORK")

	icon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
	icon:SetPoint("LEFT", bind, "RIGHT", PREVIEW_GAP, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- At the row's trailing edge and emptied rather than hidden when there is nothing to warn about, so the
	-- name beside the icon gets the width back instead of ending short of a blank region.
	local warning = node:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	warning:SetPoint("RIGHT", node, "RIGHT", 0, 0)
	warning:SetJustifyH("RIGHT")
	warning:SetWordWrap(false)
	warning:SetTextColor(ORANGE_FONT_COLOR:GetRGB())

	local preview = node:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	preview:SetPoint("LEFT", icon, "RIGHT", TEXT_GAP, 0)
	preview:SetPoint("RIGHT", warning, "LEFT", -PREVIEW_GAP, 0)
	preview:SetJustifyH("LEFT")
	preview:SetWordWrap(false)

	---@type FunctionContainer?
	local timer

	--- Shows what the typed ID names, or nothing, and arms or disarms the button with it.
	local function ShowPreview()
		local spellID = tonumber(box:GetText())
		local found = spellID ~= nil and spellID > 0 and C_Spell.GetSpellName(spellID) ~= nil

		icon:SetShown(found)
		preview:SetShown(found)
		bind:SetEnabled(found)

		if found and spellID then
			local label, texture = SpellDisplay(spellID)

			preview:SetText(label)
			icon:SetTexture(texture)
		end

		warning:SetText(found and spellID and not Known(spellID) and L.ClickCastUnknown or "")
	end

	box:SetScript("OnTextChanged", function()
		if timer then
			timer:Cancel()
		end

		timer = C_Timer.NewTimer(LOOKUP_DELAY, ShowPreview)
	end)

	local function Begin()
		local spellID = tonumber(box:GetText())

		-- The button is dark without a preview, but Enter in the box reaches this before the lookup has run.
		if not spellID or spellID <= 0 or not C_Spell.GetSpellName(spellID) then
			return
		end

		box:ClearFocus()
		Arm(spellID)
	end

	bind:SetScript("OnClick", Begin)
	box:SetScript("OnEnterPressed", Begin)

	-- Escape gives the box back rather than trapping the user in it, since the panel itself is in
	-- `UISpecialFrames` and Escape would otherwise be swallowed.
	box:SetScript("OnEscapePressed", function()
		box:ClearFocus()
	end)

	function node:Refresh()
		ShowPreview()
	end

	function node:Layout(width)
		self:SetSize(width, Private.Controls.RowHeight)

		-- Against the caption's *text* rather than at a label column, because this row has a preview to fit
		-- and "Spell ID" is a third of that column. `InputBoxTemplate` insets its own left edge, hence the
		-- extra offset.
		box:ClearAllPoints()
		box:SetPoint("LEFT", caption, "LEFT", caption:GetStringWidth() + INPUT_GAP, 0)

		bind:SetWidth(bind:GetTextWidth() + BIND_TEXT_PADDING)

		return Private.Controls.RowHeight
	end

	return node
end

---@param page Frame
---@return SpotlightsNode
local function BuildClickCasts(page)
	local L = Private.L.Settings

	overlay = BuildOverlay(page)

	local intro = Private.Controls.Paragraph(page, L.ClickCastIntro)

	--- The intro wraps to a different number of lines per locale, so what is left for the list is read off
	--- it during the pass rather than reserved as a constant. The column lays its children out in order, so
	--- by the time the pane is measured the paragraph above it has its height.
	local function ListHeight()
		return math.max(page:GetHeight() - intro:GetHeight() - Private.Controls.RowHeight - GAP * 3,
			MIN_LIST_HEIGHT)
	end

	--- Inside the pane rather than pinned above it, so the tab's height does not change with the first
	--- binding: a blank list says only that something is missing.
	local empty = Private.Node.OnlyWhen(Private.Controls.Paragraph(page, L.ClickCastNone), function()
		return #Private.ClickCasts.Get() == 0
	end)

	local root = Private.Node.Column(page, {
		intro,
		Private.Node.ScrollPane(page, Private.Node.Column(page, { empty, BuildList(page) }), ListHeight),
		BuildAddRow(page),
	}, GAP)

	local Refresh = root.Refresh

	--- Re-resolved on every pass, not only when a binding changes: which suffix one occupies follows the
	--- client's own interaction buttons, and nothing fires when the user moves those. Opening this tab is
	--- the one moment we know the user is thinking about click bindings.
	function root:Refresh()
		Private.ClickCasts.Request()

		Refresh(self)
	end

	return root
end

Private.Options.Builders.clickCasts = BuildClickCasts
