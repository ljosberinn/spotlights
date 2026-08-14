---@type string, Spotlights
local _, Private = ...

---@class SpotlightsControls
Private.Controls = {}

--- The leaves of the layout kit.
---
--- A leaf is handed its width in `Layout` and places itself inside it, rather than computing its
--- positions from a constant: a control that assumes one column of a fixed width cannot be put in a
--- two-column grid or beside a preview pane.

local ROW_HEIGHT = 26
local DEFAULT_LABEL_WIDTH = 130
local LABEL_GAP = 6

--- What one row of controls costs, published for the same reason `Node.SubTabHeight` is: a pane that
--- fits a scroll pane into whatever a pinned button leaves has to subtract the button's height, and a
--- restated constant would drift the moment a row changes.
Private.Controls.RowHeight = ROW_HEIGHT

--- What a control keeps for itself when the label column would not leave it that much. A leaf dropped
--- into a 196px rail cannot honour 130px of label and still be a control, and a clipped label is
--- recoverable where a 20px dropdown is not.
local MIN_CONTROL_WIDTH = 80

--- A heading is its text plus a band of empty space *above* it.
---
--- The pad is what makes a heading read as a break: `GameFontNormalMed2` alone, at the row rhythm, is
--- a slightly larger label in a list of labels. Sitting under twice the gap it sits over, it belongs to
--- the group beneath rather than to the row above -- which is also the Import/Export tab's whole
--- complaint, where the only thing above a heading is the button ending the previous block.
---
--- The first heading in a body pays it too, and reads as that body's top inset.
local HEADING_TOP_PAD = 10
local HEADING_TEXT_HEIGHT = 18
local HEADING_HEIGHT = HEADING_TOP_PAD + HEADING_TEXT_HEIGHT

--- Published alongside `RowHeight`, and for the same reason: the Roster tab fits a list into what a
--- heading above it and the controls below it leave over.
Private.Controls.HeadingHeight = HEADING_HEIGHT

--- One line of `GameFontHighlightSmall`, and no pad: a caption belongs to the control under it, where a
--- heading is a break between groups.
---
--- 17 is the tallest member of `SystemFont_Small` -- Korean, at 13 (`Fonts.xml`) -- plus the four pixels
--- of slack `HEADING_TEXT_HEIGHT` gives `Med2`'s tallest. Fixed rather than measured, because the pane
--- that reserves this space asks for it before layout has run.
local CAPTION_HEIGHT = 17

--- Published for the reason the two above it are.
Private.Controls.CaptionHeight = CAPTION_HEIGHT

--- The white wash a hovered row or header wears. Published rather than restated in each list, because
--- every list in the panel is meant to answer the cursor the same way and a per-file number drifts.
Private.Controls.HighlightAlpha = 0.06

--- Both templates draw their own border, and one at the full row height sits proud of the sliders beside
--- it.
local BUTTON_HEIGHT = ROW_HEIGHT - 4
local BOX_HEIGHT = ROW_HEIGHT - 6

--- Fixed, because what goes in a number box is at most four digits and a box sized to the row reads as an
--- empty field rather than as a value.
local BOX_WIDTH = 56

--- What a slider keeps back for its own value box.
---
--- `MinimalSliderWithSteppersTemplate` reports a width that does not contain its value: `RightText` is
--- anchored `LEFT` to the *inner* slider's `RIGHT` at x=25, and that inner slider is itself inset 19 from
--- the frame's right edge (`MinimalSlider.xml`). So the value starts six pixels **past** the frame, runs
--- as wide as whatever the formatter produced, and the edit box over it reaches five further -- a row that
--- hands the template all of its width puts the value in the next column. Pinning the text width makes
--- the overhang a constant the row can subtract. Forty fits five characters of `GameFontNormal`.
local VALUE_TEXT_WIDTH = 40
local VALUE_WIDTH = 6 + VALUE_TEXT_WIDTH + 5

--- The nested squares of `ColorSwatchTemplate`: a light outer edge, a black inner one, then the colour
--- (`ColorSwatch.xml`). Reproduced rather than inherited because that template's `OnShow` re-pins those
--- three regions at 14, 12 and 10 pixels through `PixelUtil` (`ColorSwatch.lua:23-27`), so it snaps back
--- to its own size every time it is shown and cannot be stretched across a control column.
local SWATCH_BORDER = 1

--- How far a swatch is drawn outside the rectangle its row was given, per side.
---
--- Not a margin but a *match*: `WowStyle1DropdownTemplate` anchors its background eight units past each
--- of its own side edges (`Blizzard_Menu/Mainline/MenuTemplates.xml`), so a dropdown laid out to a
--- column looks sixteen wider than it is. A swatch under one is the only other control in this kit with a
--- hard edge to compare against, and drawn honestly it stops short at both ends -- which at the right,
--- where no label explains the gap, reads as a box that was cut off.
local SWATCH_OVERHANG = 8

---@param parent Frame
---@return SpotlightsNode
local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	row:SetHeight(ROW_HEIGHT)

	return row
end

--- The full text of a label the column was too narrow to print.
---
--- `IsTruncated` is asked here rather than wherever the width is set, because a label only learns its
--- width in `Layout` and the answer changes again every time the panel is resized. Under the cursor,
--- layout has certainly run and the answer is current.
---@param self FontString
local function ShowLabelTooltip(self)
	if not self:IsTruncated() then
		return
	end

	-- A font string is a legal tooltip owner -- `TruncatedTooltipFontStringMixin` does the same -- but the
	-- annotation only admits a frame.
	GameTooltip:SetOwner(self --[[@as Frame]], "ANCHOR_RIGHT")
	GameTooltip:SetText(self:GetText(), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
		HIGHLIGHT_FONT_COLOR.b, 1, true)
	GameTooltip:Show()
end

--- Owner-checked, because by the time the cursor leaves, something else may have taken the tooltip.
---@param self FontString
local function HideLabelTooltip(self)
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

---@param parent Frame
---@param text string
---@return FontString
local function CreateLabel(parent, text)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")

	label:SetPoint("LEFT", parent, "LEFT", 0, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetText(text)

	-- Motion only, and propagated: the label is the whole hit region, so a row that grows a hover of its
	-- own later still hears the cursor. This is Blizzard's own `TruncatedTooltipFontStringTemplate`
	-- (`SharedUIPanelTemplates.xml`) -- a bare font string carrying the two scripts, no frame over it.
	label:EnableMouseMotion(true)
	label:SetPropagateMouseMotion(true)

	label:SetScript("OnEnter", ShowLabelTooltip)
	label:SetScript("OnLeave", HideLabelTooltip)

	return label
end

--- Splits a row's width into a label column and what is left for the control.
---
--- The label column comes from the leaf's own argument if it was given one, otherwise from whatever
--- container is holding it, otherwise from the default -- and is then capped so the control always has
--- `MIN_CONTROL_WIDTH`. A row with no label at all spends nothing on one.
---@param row SpotlightsNode
---@param width number
---@param own number?
---@param label FontString?
---@return number labelWidth, number controlWidth
local function Divide(row, width, own, label)
	if not label then
		return 0, math.max(width, 1)
	end

	local labelWidth = math.max(math.min(own or row.labelWidth or DEFAULT_LABEL_WIDTH,
		width - MIN_CONTROL_WIDTH), 0)

	label:SetWidth(math.max(labelWidth - LABEL_GAP, 1))

	return labelWidth, math.max(width - labelWidth, 1)
end

--- A checkbox.
---
--- `full` spans the row instead of taking one grid cell. The box still sits at the label column, so a
--- full-width checkbox lines up with the half-width ones above it rather than drifting to the far edge.
---
--- `enabled` sits where `Slider` and `ColorSwatch` put theirs and is re-read on every `Refresh`, for the
--- same reason: a toggle that does nothing in the current state -- Show Name On Hover Only while Show
--- Name is off -- dims rather than hides, so the row stays put and no relayout is owed. The caption is
--- dimmed alongside the box, since a greyed box beside a bright label reads as art rather than as a
--- state. Whoever owns the state it gates has to refresh the tree when it changes.
---@param parent Frame
---@param label string
---@param get fun(): boolean
---@param set fun(value: boolean)
---@param enabled (fun(): boolean)? absent means always enabled
---@param full boolean?
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.Checkbox(parent, label, get, set, enabled, full, labelWidth)
	local row = CreateRow(parent)

	row.span = full or nil

	local caption = CreateLabel(row, label)
	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")

	check:SetSize(ROW_HEIGHT, ROW_HEIGHT)

	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)

	function row:Refresh()
		check:SetChecked(get())

		local on = enabled == nil or enabled()

		check:SetEnabled(on)
		caption:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column = Divide(self, width, labelWidth, caption)

		check:ClearAllPoints()
		check:SetPoint("LEFT", self, "LEFT", column, 0)

		return ROW_HEIGHT
	end

	return row
end

--- What a fractional slider steps by, whatever step its caller asked for.
---
--- The value box prints two decimals for any step below one, so the stepper has to be able to reach
--- every value that box will show: at a coarser step the arrows walk past a number the user typed and
--- can never come back to it.
local FRACTION_STEP = 0.01

--- A slider over a numeric setting, with the value in an edit box that can be typed into.
---
--- Writes on `OnValueChanged` rather than on mouse-up, so a size drag reads as an adjustment rather than a
--- guess -- every write goes through the deferral queue, so the cost is one geometry pass per frame.
---
--- The mixin's `Init(value, min, max, steps, formatters)` takes a *count* of steps and derives the step
--- from it, so the caller's `step` is converted back to a count here. `formatters` maps the mixin's label
--- enum to a function; `RightText` is the live value slot the edit box overlays.
---@param parent Frame
---@param label string
---@param minimum number
---@param maximum number
---@param step number
---@param get fun(): number
---@param set fun(value: number)
---@param enabled (fun(): boolean)? absent means always enabled
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.Slider(parent, label, minimum, maximum, step, get, set, enabled, labelWidth)
	local row = CreateRow(parent)

	local caption = CreateLabel(row, label)
	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")

	-- The template's default height is 40, which the min/max labels need sitting *below* the bar. Those
	-- labels are never shown -- the value reads in `RightText` instead -- so the frame is crushed to the
	-- row's height and the extra 14px never overlap the row beneath.
	slider:SetHeight(ROW_HEIGHT)

	-- Pinned so the overhang is a constant rather than a function of the longest number the formatter
	-- produced. See `VALUE_WIDTH`.
	slider.RightText:SetWidth(VALUE_TEXT_WIDTH)
	slider.RightText:SetJustifyH("CENTER")
	slider.RightText:SetWordWrap(false)

	-- Whole numbers print as themselves; a 0..1 alpha prints to two places.
	local wholeNumbers = step >= 1

	local function Format(number)
		if wholeNumbers then
			-- Rounded rather than truncated: a slider quantised to whole steps can still hand back
			-- 99.99999, and `%d` on that reads as 99.
			return tostring(math.floor(number + 0.5))
		end

		return string.format("%.2f", number)
	end

	--- The step the caller gives is a *distance*; the mixin wants the number of steps across the range,
	--- which it divides the range back by. **Rounded rather than truncated**, since a range that is a
	--- whole number of steps rarely divides to one in binary -- `0.9 / 0.05` is `17.999...`, and
	--- truncating that hands back a slider stepping by `0.0529`.
	---
	--- `math.max` guards a `step` wider than the range, which would otherwise ask for a fractional count
	--- and then divide by it.
	local steps = math.max(math.floor((maximum - minimum) / (wholeNumbers and step or FRACTION_STEP)
		+ 0.5), 1)

	-- `Init` paints the control: it calls `SetValue`, which fires the mixin's `OnValueChanged` event. That
	-- first event fires *before* the callback below is registered, so it cannot reach the database -- there
	-- is no listener yet. Every event after the callback is a real change.
	local refreshing = false

	slider:Init(get(), minimum, maximum, steps, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return Format(value)
		end,
	})

	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if refreshing then
			return
		end

		set(value)
	end)

	local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")

	editBox:SetPoint("TOPLEFT", slider.RightText)
	editBox:SetPoint("BOTTOMLEFT", slider.RightText)
	editBox:SetPoint("RIGHT", slider.RightText, 5, 0)
	editBox:SetAutoFocus(false)
	editBox:SetJustifyH("CENTER")

	editBox:SetScript("OnEditFocusGained", function(self)
		slider:Hide()

		self:ClearAllPoints()
		self:SetPoint("RIGHT", slider.RightText, 5, 0)
		self:SetPoint("TOPLEFT", slider)
		self:SetPoint("BOTTOMLEFT", slider)
		self:SetText(slider.Slider:GetValue())
		self:SetCursorPosition(0)
	end)

	local function ResetEditBox(self)
		slider:Show()
		self:SetText("")
		self:ClearFocus()

		self:ClearAllPoints()
		self:SetPoint("RIGHT", slider.RightText, 5, 0)
		self:SetPoint("TOPLEFT", slider.RightText)
		self:SetPoint("BOTTOMLEFT", slider.RightText)
	end

	editBox:SetScript("OnEnterPressed", function(self)
		local minimumValue, maximumValue = slider.Slider:GetMinMaxValues()
		local value = tonumber(self:GetText())

		if value then
			slider:SetValue(math.min(math.max(value, minimumValue), maximumValue))
		end

		self:ClearFocus()
	end)

	editBox:SetScript("OnEscapePressed", ResetEditBox)
	editBox:SetScript("OnEditFocusLost", ResetEditBox)

	-- Guards the write, not the read. `Refresh` re-reads a value a slash command may have changed behind
	-- the panel's back; `SetValue` fires the same event a drag does, and re-arming the guard keeps the
	-- re-draw from writing the value back.
	function row:Refresh()
		refreshing = true
		slider:SetValue(get())
		refreshing = false

		--- Re-read on every pass, like the colour swatch's: a setting that does nothing in the current
		--- mode dims rather than hides, so the row stays put and no relayout is needed. The mixin greys
		--- the thumb, the value and both steppers; the edit box over the value is ours to stop, and must
		--- be -- a disabled slider you can still type into is worse than no dimming at all.
		local on = enabled == nil or enabled()

		slider:SetEnabled(on)
		editBox:SetEnabled(on)
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)

		slider:ClearAllPoints()
		slider:SetPoint("LEFT", self, "LEFT", column, 0)

		-- The bar gets what is left after the value box, which lives outside the width set here.
		slider:SetWidth(math.max(control - VALUE_WIDTH, 1))

		return ROW_HEIGHT
	end

	return row
end

--- A dropdown over a list of choices.
---
--- Takes a list of `{ value, label }` pairs rather than a map, because the order the user sees has to be
--- stable and `pairs` over a settings map is not. `value` is what reaches the database.
---
--- `choices` may be a **function** returning that list, and for the media pickers it has to be. Controls
--- are built once, on the first open of their tab, so a list passed as a table is captured then and never
--- revisited -- silently dropping any media another addon registers afterwards. Resolved per menu-open
--- instead, the list is as current as the media library is.
---
--- A `placeholder` is for the dropdowns whose `get` can legitimately return `nil`. Without one the button
--- falls back to the template's default text, which is unset -- a blank button, which reads as a broken
--- setting rather than as an empty selection. Said as an entry rather than through `SetDefaultText`
--- because the *list* has the same gap: presets with none of them ticked and no line saying so.
---@param parent Frame
---@param label string? omitted for a dropdown that spans its column, where a `Caption` or a heading above says what it picks
---@param choices { value: any, label: string }[] | fun(): { value: any, label: string }[]
---@param get fun(): any
---@param set fun(value: any)
---@param labelWidth number?
---@param placeholder string? what the button reads while `get` returns nil
---@return SpotlightsNode
function Private.Controls.Dropdown(parent, label, choices, get, set, labelWidth, placeholder)
	local row = CreateRow(parent)

	local caption = label and CreateLabel(row, label) or nil
	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")

	-- The generator re-runs every time the menu opens, so the checked state is derived from the database at
	-- open time rather than tracked.
	dropdown:SetupMenu(function(_, rootDescription)
		local current = type(choices) == "function" and choices() or choices

		-- Only while nothing is selected, so there is no entry to come back to once something is: it is a
		-- name for the empty state rather than a choice, and there is no setting it answers.
		--
		-- Disabled and still selected: `MenuUtil.GetSelections` does not test `IsEnabled`, so the entry the
		-- user cannot click is the one the closed button reads.
		if placeholder and get() == nil then
			local none = rootDescription:CreateRadio(placeholder, function()
				return true
			end)

			none:SetEnabled(false)
		end

		for i = 1, #current do
			local choice = current[i]

			rootDescription:CreateRadio(choice.label, function()
				return get() == choice.value
			end, function()
				set(choice.value)
			end)
		end
	end)

	--- Regenerating the menu is how the button's *text* is refreshed, which is why there is no `SetText`
	--- here.
	---
	--- `DropdownButtonMixin` derives its own label by walking the generated descriptions and combining
	--- whichever report themselves selected (`DropdownButton.lua:17-40` collects them, `:326-328` applies
	--- them to the button). Writing the text ourselves
	--- would be overwritten the first time the menu opened, so a stale label would appear to fix itself on
	--- click.
	function row:Refresh()
		dropdown:GenerateMenu()
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)

		dropdown:ClearAllPoints()
		dropdown:SetPoint("LEFT", self, "LEFT", column, 0)
		dropdown:SetWidth(control)

		return ROW_HEIGHT
	end

	return row
end

--- A dropdown over a list of choices where any number may be picked at once.
---
--- `CreateCheckbox` rather than `CreateRadio` is the whole difference, and it is what keeps the menu open
--- on a click: the description ships `MenuResponse.Refresh`
--- (`Blizzard_Menu/MenuTemplates.lua:341`), so a tick re-runs the generator in place instead of
--- dismissing the list. Three separate opens to pick three roles is the alternative.
---
--- `SetSelected` is handed the new state rather than left to derive it, so a caller storing a set does
--- not have to read its own database back to know which way the click went.
---
--- The button's text is derived the same way `Dropdown`'s is -- from whichever descriptions report
--- themselves selected, joined -- so `SetDefaultText` is the only way to name the empty case. `NONE` is
--- the game's own word for it, and every multiselect this panel grows wants the same one.
---@param parent Frame
---@param label string? omitted for a dropdown that spans its column, where a `Caption` or a heading above says what it picks
---@param choices { value: any, label: string }[] | fun(): { value: any, label: string }[]
---@param IsSelected fun(value: any): boolean
---@param SetSelected fun(value: any, selected: boolean)
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.MultiselectDropdown(parent, label, choices, IsSelected, SetSelected, labelWidth)
	local row = CreateRow(parent)

	local caption = label and CreateLabel(row, label) or nil
	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")

	dropdown:SetDefaultText(NONE)

	dropdown:SetupMenu(function(_, rootDescription)
		local current = type(choices) == "function" and choices() or choices

		for i = 1, #current do
			local choice = current[i]

			rootDescription:CreateCheckbox(choice.label, function()
				return IsSelected(choice.value)
			end, function()
				SetSelected(choice.value, not IsSelected(choice.value))
			end)
		end
	end)

	--- Regenerating the menu, for the reason `Dropdown:Refresh` does it: the button's text is derived from
	--- the generated descriptions, so there is nothing to `SetText`.
	---
	--- **Not while the menu is open**, which is the one thing separating this from `Dropdown:Refresh`: a
	--- multiselect's setter refreshes the tab on every tick, and the tick leaves the list down. The click
	--- already re-derives the text on its own -- a checkbox response signals an update, which walks the
	--- descriptions the same way (`Blizzard_Menu/DropdownButton.lua:290-299`), and the responder runs before
	--- the response is processed, so what it reads is the write that just happened. Regenerating on top of
	--- that reinitialises the open list under the cursor for nothing. `CloseMenu` signals an update too, so
	--- a database change from anywhere else lands on the button as the menu goes away.
	function row:Refresh()
		if dropdown:IsMenuOpen() then
			return
		end

		dropdown:GenerateMenu()
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)

		dropdown:ClearAllPoints()
		dropdown:SetPoint("LEFT", self, "LEFT", column, 0)
		dropdown:SetWidth(control)

		return ROW_HEIGHT
	end

	return row
end

--- The choices for a media picker, rebuilt per call from whatever LibSharedMedia currently knows.
---
--- Not cached: another addon can register media after a tab is built, and a list captured then would omit
--- it until a reload. `Dropdown` takes a function for exactly this.
---
--- A stored key nothing currently registers is added anyway, marked. The setting is legitimately kept in
--- that case (a media pack can be disabled for one session), so the honest display is the name plus a note
--- rather than a blank dropdown -- the button derives its label from whichever choice reports itself
--- selected, so without a matching entry the setting would look lost rather than unavailable.
---@param list string[]
---@param IsRegistered fun(key: string): boolean
---@param stored string?
---@return { value: any, label: string }[]
function Private.Controls.MediaChoices(list, IsRegistered, stored)
	local choices = {}

	for i = 1, #list do
		choices[i] = { value = list[i], label = list[i] }
	end

	if stored and not IsRegistered(stored) then
		choices[#choices + 1] = {
			value = stored,
			label = string.format(Private.L.Settings.TextureMissing, stored),
		}
	end

	return choices
end

--- The nine anchor points, in reading order, with prose labels. Built per call because the labels are
--- localised and the files that ask load before the localisation table is filled.
---@return { value: any, label: string }[]
function Private.Controls.AnchorChoices()
	local L = Private.L.Settings
	local order = Private.Enum.AnchorPointOrder
	local choices = {}

	for i = 1, #order do
		choices[i] = { value = order[i], label = L.Anchors[order[i]] }
	end

	return choices
end

--- A colour swatch that opens Blizzard's colour picker.
---
--- `get` and `set` deal in separate channel numbers rather than a colour object, because that is how the
--- setting is stored -- fields, so a database written by one build reads on another without a metatable in
--- the way.
---
--- `swatchFunc` fires continuously while the wheel is dragged, so this writes on every move rather than on
--- confirm; the aura setter debounces what it has to, so a drag still costs one rebuild. `cancelFunc`
--- restores from the values captured when the picker opened rather than the `previousValues` it is handed,
--- which cannot be wrong about which "previous" it means after a drag.
---
--- `enabled` decides whether the swatch can be opened, re-read on every `Refresh`: a colour that does
--- nothing in the current mode (a static colour while class colour is on) dims rather than hides, so the
--- row stays put and no relayout is needed. Whoever owns the mode has to refresh the tree when it changes.
---@param parent Frame
---@param label string
---@param get fun(): number, number, number, number
---@param set fun(r: number, g: number, b: number, a: number)
---@param enabled (fun(): boolean)? absent means always enabled
---@param full boolean?
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.ColorSwatch(parent, label, get, set, enabled, full, labelWidth)
	local row = CreateRow(parent)

	row.span = full or nil

	local caption = CreateLabel(row, label)

	--- Not `UIPanelButtonTemplate` with a colour laid inside it: that template is three pieces of gold
	--- dialog-button art whose visible extent is not the frame's rectangle -- its own highlight is inset
	--- twelve pixels either side -- so a colour inset far enough to clear the bevel wastes half the swatch
	--- and anything less leaves gold showing around it.
	local button = CreateFrame("Button", nil, row)

	PixelUtil.SetHeight(button, BOX_HEIGHT)

	local edge = button:CreateTexture(nil, "BORDER")

	edge:SetAllPoints(button)

	--- Snapped, all three rectangles, and this is what keeps the swatch's right and bottom edges drawn:
	--- a grid cell is rarely a whole number of pixels wide -- two columns and a gutter out of 527 leave
	--- halves -- so a one-*unit* inset from a boundary that lands mid-pixel rasterises to nothing on that
	--- side, and the swatch reads as a box left open at the right.
	local innerEdge = button:CreateTexture(nil, "ARTWORK")

	PixelUtil.SetPoint(innerEdge, "TOPLEFT", button, "TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
	PixelUtil.SetPoint(innerEdge, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)
	innerEdge:SetColorTexture(BLACK_FONT_COLOR:GetRGB())

	local swatch = button:CreateTexture(nil, "OVERLAY")

	PixelUtil.SetPoint(swatch, "TOPLEFT", innerEdge, "TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
	PixelUtil.SetPoint(swatch, "BOTTOMRIGHT", innerEdge, "BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)

	--- The outer edge turning gold *is* the hover state, as `ColorSwatchMixin:OnEnter` does it. A separate
	--- highlight texture would sit over the colour and misreport it.
	local function UpdateEdge(hovered)
		edge:SetColorTexture((hovered and button:IsEnabled() and NORMAL_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
			:GetRGB())
	end

	button:SetScript("OnEnter", function()
		UpdateEdge(true)
	end)

	button:SetScript("OnLeave", function()
		UpdateEdge(false)
	end)

	UpdateEdge(false)

	button:SetScript("OnClick", function()
		local r, g, b, a = get()

		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			hasOpacity = true,
			opacity = 1 - a,
			swatchFunc = function()
				local newR, newG, newB = ColorPickerFrame:GetColorRGB()
				local newA = ColorPickerFrame:GetColorAlpha()

				swatch:SetColorTexture(newR, newG, newB)
				set(newR, newG, newB, newA)
			end,
			cancelFunc = function()
				swatch:SetColorTexture(r, g, b)
				set(r, g, b, a)
			end,
		})
	end)

	function row:Refresh()
		swatch:SetColorTexture(get())

		-- The alpha is what reads as "off", and it says so about the colour itself rather than about a frame
		-- around it. Fully opaque when there is no predicate at all.
		local on = enabled == nil or enabled()

		button:SetEnabled(on)
		swatch:SetAlpha(on and 1 or 0.35)
		UpdateEdge(false)
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)

		--- Widened to the dropdown's own overhang, and shifted by it, so a swatch and a dropdown in the
		--- same column line up. `WowStyle1DropdownTemplate` anchors its background eight units past each of
		--- its own side edges (`MenuTemplates.xml`), so a control drawn to its rectangle stops eight short
		--- of the one above it and reads as trimmed. The row still *occupies* only its column: the overhang
		--- is art, and the gutter it reaches into is 26 wide.
		button:ClearAllPoints()
		PixelUtil.SetPoint(button, "LEFT", self, "LEFT", column - SWATCH_OVERHANG, 0)
		PixelUtil.SetWidth(button, control + SWATCH_OVERHANG * 2)

		return ROW_HEIGHT
	end

	return row
end

--- A row of buttons where the selected one is disabled: the design's segmented Left/Right and Up/Down
--- controls, and the sub-tab strips inside a pane.
---
--- Nothing below is rebuilt when the selection changes -- every control in this kit reads and writes
--- through closures, so a switch is a variable write plus the refresh the panel already does.
---@param parent Frame
---@param label string? omitted for a strip that spans the row
---@param choices { value: any, label: string }[]
---@param get fun(): any
---@param set fun(value: any)
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.Segmented(parent, label, choices, get, set, labelWidth)
	local row = CreateRow(parent)

	local caption = label and CreateLabel(row, label) or nil

	---@type Button[]
	local buttons = {}

	for i = 1, #choices do
		local choice = choices[i]
		local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")

		button:SetHeight(BUTTON_HEIGHT)
		button:SetText(choice.label)

		button:SetScript("OnClick", function()
			set(choice.value)

			-- The selection is what the buttons themselves display, so the strip repaints without waiting
			-- for whoever owns the tree to refresh it.
			row:Refresh()
		end)

		buttons[i] = button
	end

	function row:Refresh()
		local current = get()

		for i = 1, #choices do
			buttons[i]:SetEnabled(choices[i].value ~= current)
		end
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)
		local each = control / #choices

		for i = 1, #buttons do
			local button = buttons[i]

			button:ClearAllPoints()
			button:SetPoint("LEFT", self, "LEFT", column + (i - 1) * each, 0)

			-- Two pixels off each button rather than a gap added between them, so the strip as a whole ends
			-- exactly where the sliders and dropdowns above it do.
			button:SetWidth(math.max(each - 2, 1))
		end

		return ROW_HEIGHT
	end

	return row
end

--- One half of a number pair. A named class rather than an inline table type in the `@param` below,
--- which LuaLS reads only partially once a `fun(...)` field is nested in one.
---@class SpotlightsNumberField
---@field label string
---@field get fun(): number
---@field set fun(value: number)
---@field minimum number? clamped to, when given
---@field maximum number?

--- Two numbers on one row, for a setting that is really a pair: horizontal and vertical spacing, an x/y
--- offset.
---
--- Boxes rather than two sliders, because a pair is compared as much as it is set -- reading "4" and "4"
--- off two thumbs means measuring both against their own ranges first.
---
--- Commits on Enter or on losing focus, clamping rather than refusing: the number typed is the number
--- meant, at the closest the setting can get to it.
---@param parent Frame
---@param label string
---@param fields SpotlightsNumberField[]
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.NumberPair(parent, label, fields, labelWidth)
	local row = CreateRow(parent)

	local caption = CreateLabel(row, label)

	---@type { caption: FontString, box: EditBox }[]
	local entries = {}

	for i = 1, #fields do
		local field = fields[i]

		local fieldCaption = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

		fieldCaption:SetJustifyH("LEFT")
		fieldCaption:SetWordWrap(false)
		fieldCaption:SetText(field.label)

		local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")

		box:SetSize(BOX_WIDTH, BOX_HEIGHT)
		box:SetAutoFocus(false)
		box:SetJustifyH("CENTER")

		-- Not `SetNumeric`, which refuses a minus sign: an offset is signed. Anything that is not a number
		-- is dropped on commit instead.
		box:SetMaxLetters(6)

		local function Commit(self)
			local value = tonumber(self:GetText())

			if value then
				if field.minimum then
					value = math.max(value, field.minimum)
				end

				if field.maximum then
					value = math.min(value, field.maximum)
				end

				field.set(value)
			end

			-- Re-read rather than left as typed, so a clamped or rejected entry shows what was actually
			-- stored instead of what was asked for.
			self:SetText(tostring(field.get()))
			self:ClearFocus()
		end

		box:SetScript("OnEnterPressed", Commit)
		box:SetScript("OnEditFocusLost", Commit)

		-- Escape gives the box back rather than trapping the user in it, since the panel itself is in
		-- `UISpecialFrames` and Escape would otherwise be swallowed.
		box:SetScript("OnEscapePressed", function(self)
			self:SetText(tostring(field.get()))
			self:ClearFocus()
		end)

		entries[i] = { caption = fieldCaption, box = box }
	end

	function row:Refresh()
		for i = 1, #fields do
			entries[i].box:SetText(tostring(fields[i].get()))
		end
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)
		local each = control / #entries

		for i = 1, #entries do
			local entry = entries[i]
			local left = column + (i - 1) * each

			entry.caption:ClearAllPoints()
			entry.caption:SetPoint("LEFT", self, "LEFT", left, 0)

			-- The box follows the caption's measured width rather than a fixed offset, so a translation that
			-- spells "Horizontal" where English has "H" pushes its own box along instead of overlapping it.
			entry.box:ClearAllPoints()
			entry.box:SetPoint("LEFT", entry.caption, "RIGHT", 8, 0)
			entry.box:SetWidth(math.max(math.min(BOX_WIDTH, each - entry.caption:GetStringWidth() - 12), 1))
		end

		return ROW_HEIGHT
	end

	return row
end

--- A group heading inside a body: the `Border` line above the four border controls, the `Opacity` line
--- above the three alpha sliders.
---
--- Always spans, because a heading over one of two columns names half a group and reads as a control that
--- lost its widget. A grid therefore gives it a row of its own and the group beneath it starts back in the
--- left column -- so a group with an odd number of controls leaves a hole, and its members are ordered so
--- that hole falls at the end rather than in the middle.
---
--- `GameFontNormalMed2` is the one step between a control's own label and a section title: 14 against
--- `GameFontNormal`'s 12 and `GameFontNormalLarge`'s 16, all three shadowed. `GameFontNormalMed1` is 13
--- but carries no shadow, so beside the other two it reads as a different family rather than as a level
--- between them.
---
--- The text is anchored `BOTTOMLEFT` so `HEADING_TOP_PAD` falls above it.
---@param parent Frame
---@param text string | fun(): string
---@return SpotlightsNode
function Private.Controls.SubHeading(parent, text)
	local row = CreateRow(parent)

	row.span = true

	local heading = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")

	heading:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	heading:SetJustifyH("LEFT")

	function row:Refresh()
		heading:SetText(type(text) == "function" and text() or text)
	end

	function row:Layout(width)
		self:SetSize(width, HEADING_HEIGHT)

		return HEADING_HEIGHT
	end

	return row
end

--- A single line naming the control beneath it, for a control that spans its column and so has no label
--- of its own to be named by.
---
--- Neither of the two leaves already here would do. `SubHeading` is fixed height but reads as a second
--- heading under the first, and pads itself away from what it is meant to sit on. `Paragraph` is the
--- right weight but only learns its height in `Layout`, and a pane that reserves room for this has to
--- know the number before that -- a caption that wrapped to two lines in one locale would silently push
--- the list past the bottom of the tab.
---
--- So: one line, no wrap, and clipped when the column is too narrow -- with the truncation tooltip every
--- other clipped string in the panel carries.
---
--- Anchored `BOTTOMLEFT` like `SubHeading`'s text, so a taller alphabet grows upwards into the gap
--- rather than downwards into the control it captions.
---@param parent Frame
---@param text string | fun(): string
---@return SpotlightsNode
function Private.Controls.Caption(parent, text)
	local row = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	row.span = true

	local caption = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	caption:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	caption:SetJustifyH("LEFT")
	caption:SetWordWrap(false)

	caption:EnableMouseMotion(true)
	caption:SetPropagateMouseMotion(true)

	caption:SetScript("OnEnter", ShowLabelTooltip)
	caption:SetScript("OnLeave", HideLabelTooltip)

	function row:Refresh()
		caption:SetText(type(text) == "function" and text() or text)
	end

	function row:Layout(width)
		self:SetSize(width, CAPTION_HEIGHT)
		caption:SetWidth(width)

		return CAPTION_HEIGHT
	end

	return row
end

--- Wrapped explanatory prose: the General tab's slash-command hint, and whatever else has to say
--- something a label cannot.
---
--- The one leaf whose height is not the row height, and the reason it is a node at all: a string
--- only knows how tall it is once it knows how wide it may be, so the height is read in `Layout`
--- after the width is set rather than measured at construction. A column that narrows re-wraps and
--- reports the taller answer on the next pass.
---@param parent Frame
---@param text string | fun(): string
---@return SpotlightsNode
function Private.Controls.Paragraph(parent, text)
	local row = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	row.span = true

	local body = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	body:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetWordWrap(true)

	function row:Refresh()
		body:SetText(type(text) == "function" and text() or text)
	end

	function row:Layout(width)
		body:SetWidth(width)

		-- Floored at 1, since a frame may not be zero tall and a paragraph whose text is empty this
		-- pass is still a node its container will size.
		local height = math.max(body:GetStringHeight(), 1)

		self:SetSize(width, height)

		return height
	end

	return row
end

--- A button across the whole row: "Reset frame settings", "Clear all slots".
---
--- `destructive` swaps the template rather than tinting the caption, and has to: red text on
--- `UI-DialogBox-goldbutton-up-middle` is dark on dark, and it would not survive a mouseover either --
--- `UIPanelButtonTemplate` inherits a `NormalFont`/`HighlightFont` pair from
--- `UIPanelButtonNoTooltipTemplate`, and swapping font objects on hover discards a `SetTextColor`.
--- `SharedButtonTemplate` is the red button the game already ships
--- (`ThreeSliceButtonTemplate.xml:69`), with its own pressed and disabled states.
---@param parent Frame
---@param label string
---@param onClick fun()
---@param destructive boolean?
---@return SpotlightsNode
function Private.Controls.ActionButton(parent, label, onClick, destructive)
	local row = CreateRow(parent)

	row.span = true

	local button = CreateFrame("Button", nil, row,
		destructive and "SharedButtonTemplate" or "UIPanelButtonTemplate")

	button:SetPoint("LEFT", row, "LEFT", 0, 0)
	button:SetHeight(BUTTON_HEIGHT)
	button:SetText(label)
	button:SetScript("OnClick", onClick)

	function row:Refresh() end

	function row:Layout(width)
		self:SetWidth(width)
		button:SetWidth(width)

		return ROW_HEIGHT
	end

	return row
end

--- One button in a row of them.
---@class SpotlightsButtonSpec
---@field label string
---@field onClick fun()
---@field destructive boolean? swaps in the red template, as `ActionButton`'s own flag does
---@field enabled (fun(): boolean)? absent means always enabled

--- Several buttons across one row, dividing it evenly: the presets block's Save / Delete pair and the
--- Import / Export pair under it.
---
--- `Segmented` looks like this and is not it. There the selection *is* the state and the disabled
--- button is the chosen one; these are independent actions, each dimmed or not by a question about
--- the database -- there is nothing to delete without a preset selected, and nothing to save without
--- a slot.
---@param parent Frame
---@param buttons SpotlightsButtonSpec[]
---@return SpotlightsNode
function Private.Controls.ButtonRow(parent, buttons)
	local row = CreateRow(parent)

	row.span = true

	---@type Button[]
	local frames = {}

	for i = 1, #buttons do
		local spec = buttons[i]
		local button = CreateFrame("Button", nil, row,
			spec.destructive and "SharedButtonTemplate" or "UIPanelButtonTemplate")

		button:SetHeight(BUTTON_HEIGHT)
		button:SetText(spec.label)
		button:SetScript("OnClick", spec.onClick)

		frames[i] = button
	end

	function row:Refresh()
		for i = 1, #buttons do
			local enabled = buttons[i].enabled

			frames[i]:SetEnabled(enabled == nil or enabled())
		end
	end

	function row:Layout(width)
		self:SetWidth(width)

		local each = width / #frames

		for i = 1, #frames do
			local button = frames[i]

			button:ClearAllPoints()
			button:SetPoint("LEFT", self, "LEFT", (i - 1) * each, 0)

			-- Two pixels off each rather than a gap between them, so the row ends exactly where the
			-- controls above it do. `Segmented` divides itself the same way.
			button:SetWidth(math.max(each - 2, 1))
		end

		return ROW_HEIGHT
	end

	return row
end

--- A scrolling multi-line text box: the Import/Export tab's read-only export pane and paste-in import
--- pane.
---
--- `set` absent is what makes a box read-only -- `EditBox` has no such flag, so a keystroke is undone
--- in `OnTextChanged` by resetting the text to `get()` whenever the two disagree, the same trick a
--- read-only `StaticPopup` edit box uses. Selecting and copying still work; typing does not stick.
---
--- `InputScrollFrameTemplate` sizes its `EditBox` once, in its own `OnLoad`, against whatever width the
--- frame happened to have at creation -- one pixel, since nothing has laid it out yet. `Layout` restates
--- it every pass instead of relying on that.
---@class SpotlightsTextAreaNode : SpotlightsNode
---@field SetText fun(self: SpotlightsTextAreaNode, text: string)
---@field Highlight fun(self: SpotlightsTextAreaNode) focuses the box and selects everything, for a Copy button
---@param parent Frame
---@param height number
---@param get fun(): string
---@param set (fun(value: string))? absent for a read-only box
---@return SpotlightsTextAreaNode
function Private.Controls.TextArea(parent, height, get, set)
	local row = CreateFrame("Frame", nil, parent) --[[@as SpotlightsTextAreaNode]]

	row.span = true

	local scroll = CreateFrame("ScrollFrame", nil, row, "InputScrollFrameTemplate")

	scroll:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

	-- The template only reads `hideCharCount` in its own `OnLoad`, before this box has been told
	-- anything -- hidden here instead, once, since nothing after this ever wants it shown.
	scroll.CharCount:Hide()

	local editBox = scroll.EditBox

	editBox:SetAutoFocus(false)

	if set then
		editBox:SetScript("OnTextChanged", function(self)
			set(self:GetText())
		end)
	else
		editBox:SetScript("OnTextChanged", function(self)
			local text = self:GetText()
			local expected = get()

			if text ~= expected then
				self:SetText(expected)
			end
		end)

		-- The design's own words for a read-only box: selected as soon as it is focused, not only
		-- through the Copy button beside it.
		editBox:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
		end)
	end

	function row:SetText(text)
		editBox:SetText(text)
	end

	function row:Highlight()
		editBox:SetFocus()
		editBox:HighlightText()
	end

	function row:Refresh()
		local text = get()

		if editBox:GetText() ~= text then
			editBox:SetText(text)
		end
	end

	function row:Layout(width)
		self:SetSize(width, height)
		scroll:SetSize(width, height)
		editBox:SetWidth(math.max(width - 18, 1))

		return height
	end

	return row
end

--- A search box, for filtering a list beside it.
---
--- `SearchBoxTemplate` drives its own clear button and instruction text from `OnTextChanged`, so the
--- caller's handler is **hooked** rather than set -- setting it leaves both frozen at whatever they were.
---@param parent Frame
---@param OnChanged fun(text: string)
---@param placeholder string? defaults to the client's own "Search"
---@return SpotlightsNode
function Private.Controls.SearchBox(parent, OnChanged, placeholder)
	local row = CreateRow(parent)

	row.span = true

	local box = CreateFrame("EditBox", nil, row, "SearchBoxTemplate")

	box:SetPoint("LEFT", row, "LEFT", 0, 0)
	box:SetHeight(BOX_HEIGHT)
	box:SetAutoFocus(false)
	box.Instructions:SetText(placeholder or SEARCH)

	box:HookScript("OnTextChanged", function(self)
		OnChanged(self:GetText())
	end)

	-- Escape clears the filter before it closes the panel, which is the same order the game's own search
	-- boxes use.
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)

	-- The filter is not a setting; it lives only as long as the pane is open.
	function row:Refresh() end

	function row:Layout(width)
		self:SetWidth(width)
		box:SetWidth(width)

		return ROW_HEIGHT
	end

	return row
end
