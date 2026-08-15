---@type string, Spotlights
local _, Private = ...

---@class SpotlightsControls
Private.Controls = {}

--- The leaves of the layout kit. A leaf is handed its width in `Layout` and places itself inside it
--- rather than computing positions from a constant: a control that assumes one fixed-width column
--- cannot be put in a two-column grid or beside a preview pane.

local ROW_HEIGHT = 26
local DEFAULT_LABEL_WIDTH = 130
local LABEL_GAP = 6

--- Published so a pane fitting a scroll pane around a pinned button can subtract it rather than
--- restating it, which would drift the moment a row changes.
Private.Controls.RowHeight = ROW_HEIGHT

--- What a control keeps for itself when the label column would not leave it that much: a clipped label
--- is recoverable where a 20px dropdown is not.
local MIN_CONTROL_WIDTH = 80

--- A heading is its text plus a band of empty space *above* it. The pad is what makes it read as a break
--- rather than a slightly larger label: sitting under twice the gap it sits over, it belongs to the
--- group beneath. The first heading in a body pays it too, and reads as that body's top inset.
local HEADING_TOP_PAD = 10
local HEADING_TEXT_HEIGHT = 18
local HEADING_HEIGHT = HEADING_TOP_PAD + HEADING_TEXT_HEIGHT

--- Published alongside `RowHeight`: the Roster tab fits a list into what a heading above it and the
--- controls below it leave over.
Private.Controls.HeadingHeight = HEADING_HEIGHT

--- One line of `GameFontHighlightSmall`, and no pad: a caption belongs to the control under it, where a
--- heading is a break between groups. 17 is the tallest member of `SystemFont_Small` (Korean, at 13 in
--- `Fonts.xml`) plus four pixels of slack. Fixed rather than measured, because the pane reserving this
--- space asks for it before layout has run.
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

--- What a slider keeps back for its own value box. `MinimalSliderWithSteppersTemplate` reports a width
--- that does not contain its value: `RightText` is anchored `LEFT` to the *inner* slider's `RIGHT` at
--- x=25, and that inner slider is itself inset 19 from the frame's right edge (`MinimalSlider.xml`), so
--- the value starts six pixels **past** the frame and the edit box over it reaches five further. Pinning
--- the text width makes the overhang a constant the row can subtract.
local VALUE_TEXT_WIDTH = 40
local VALUE_WIDTH = 6 + VALUE_TEXT_WIDTH + 5

--- The nested squares of `ColorSwatchTemplate` (`ColorSwatch.xml`), reproduced rather than inherited
--- because that template's `OnShow` re-pins its three regions at 14, 12 and 10 pixels
--- (`ColorSwatch.lua:23-27`), so it snaps back to its own size and cannot be stretched across a column.
local SWATCH_BORDER = 1

--- How far a swatch is drawn outside the rectangle its row was given, per side. Not a margin but a
--- *match*: `WowStyle1DropdownTemplate` anchors its background eight units past each of its own side
--- edges (`Blizzard_Menu/Mainline/MenuTemplates.xml`), so a swatch drawn honestly under one stops short
--- at both ends and reads as a box that was cut off.
local SWATCH_OVERHANG = 8

---@param parent Frame
---@return SpotlightsNode
local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	row:SetHeight(ROW_HEIGHT)

	return row
end

--- The full text of a label the column was too narrow to print. `IsTruncated` is asked here rather than
--- where the width is set, because a label only learns its width in `Layout` and the answer changes
--- again on every resize.
---@param self FontString
local function ShowLabelTooltip(self)
	if not self:IsTruncated() then
		return
	end

	-- A font string is a legal tooltip owner, as `TruncatedTooltipFontStringMixin` does, but the
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

	-- Motion only, and propagated, so a row that grows a hover of its own later still hears the cursor.
	-- This is Blizzard's own `TruncatedTooltipFontStringTemplate` (`SharedUIPanelTemplates.xml`).
	label:EnableMouseMotion(true)
	label:SetPropagateMouseMotion(true)

	label:SetScript("OnEnter", ShowLabelTooltip)
	label:SetScript("OnLeave", HideLabelTooltip)

	return label
end

--- Splits a row's width into a label column and what is left for the control. The column comes from the
--- leaf's own argument, else its container's, else the default, and is capped so the control always has
--- `MIN_CONTROL_WIDTH`. A row with no label spends nothing on one.
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

--- A checkbox. `full` spans the row instead of taking one grid cell; the box still sits at the label
--- column, so a full-width checkbox lines up with the half-width ones above it.
---
--- `enabled` is re-read on every `Refresh`: a toggle that does nothing in the current state dims rather
--- than hides, so the row stays put and no relayout is owed. The caption dims with it, since a greyed
--- box beside a bright label reads as art. Whoever owns the state it gates has to refresh the tree.
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

--- What a fractional slider steps by, whatever step its caller asked for. The value box prints two
--- decimals below one, so at a coarser step the arrows would walk past a number the user typed and
--- never come back to it.
local FRACTION_STEP = 0.01

--- A slider over a numeric setting, with the value in an edit box that can be typed into.
---
--- Writes on `OnValueChanged` rather than mouse-up, so a size drag reads as an adjustment; every write
--- goes through the deferral queue, so the cost is one geometry pass per frame.
---
--- The mixin's `Init` takes a *count* of steps and derives the step from it, so the caller's `step` is
--- converted back to a count here. `RightText` is the live value slot the edit box overlays.
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
	-- are never shown, so the frame is crushed to the row's height and the extra 14px never overlap the
	-- row beneath.
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

	-- The caller's `step` is a *distance*; the mixin wants a count across the range. **Rounded rather
	-- than truncated**, since a range that is a whole number of steps rarely divides to one in binary --
	-- `0.9 / 0.05` is `17.999...`, and truncating hands back a slider stepping by `0.0529`. `math.max`
	-- guards a `step` wider than the range.
	local steps = math.max(math.floor((maximum - minimum) / (wholeNumbers and step or FRACTION_STEP)
		+ 0.5), 1)

	-- `Init` paints the control by calling `SetValue`, which fires `OnValueChanged` before the callback
	-- below is registered, so that first event cannot reach the database.
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

		-- The mixin greys the thumb, the value and both steppers; the edit box over the value is ours to
		-- stop, and must be -- a disabled slider you can still type into is worse than no dimming.
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

--- A dropdown over a list of choices. A list of `{ value, label }` pairs rather than a map, because the
--- order the user sees has to be stable and `pairs` over a settings map is not.
---
--- `choices` may be a **function** returning that list, and for the media pickers it has to be: controls
--- are built once on the first open of their tab, so a table is captured then and silently drops media
--- another addon registers afterwards.
---
--- A `placeholder` is for dropdowns whose `get` can legitimately return `nil`; without one the button
--- falls back to unset default text and reads as broken rather than empty. Said as an entry rather than
--- through `SetDefaultText`, because the *list* has the same gap.
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

		-- Only while nothing is selected: it is a name for the empty state rather than a choice. Disabled
		-- and still selected, because `MenuUtil.GetSelections` does not test `IsEnabled`, so the entry
		-- the user cannot click is the one the closed button reads.
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

	-- Regenerating the menu is how the button's *text* is refreshed: `DropdownButtonMixin` derives its own
	-- label by walking the generated descriptions (`DropdownButton.lua:17-40`, `:326-328`), so a `SetText`
	-- here would be overwritten the first time the menu opened.
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
--- `CreateCheckbox` rather than `CreateRadio` is the whole difference, and is what keeps the menu open on
--- a click: the description ships `MenuResponse.Refresh` (`Blizzard_Menu/MenuTemplates.lua:341`), so a
--- tick re-runs the generator in place instead of dismissing the list.
---
--- `SetSelected` is handed the new state rather than left to derive it, so a caller storing a set does
--- not have to read its own database back to know which way the click went.
---
--- The button's text is derived as `Dropdown`'s is, so `SetDefaultText` is the only way to name the
--- empty case.
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

	-- Regenerating the menu, for `Dropdown:Refresh`'s reason, but **not while it is open**: a
	-- multiselect's setter refreshes the tab on every tick and the tick leaves the list down. The click
	-- already re-derives the text (`Blizzard_Menu/DropdownButton.lua:290-299`), so regenerating on top
	-- would reinitialise the open list under the cursor for nothing.
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

--- The choices for a media picker, rebuilt per call from whatever LibSharedMedia currently knows. Not
--- cached: another addon can register media after a tab is built.
---
--- A stored key nothing currently registers is added anyway, marked. The setting is legitimately kept in
--- that case, and the button derives its label from whichever choice reports itself selected -- so
--- without a matching entry the setting would look lost rather than unavailable.
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
--- setting is stored -- so a database written by one build reads on another with no metatable in the way.
---
--- `swatchFunc` fires continuously while the wheel is dragged, so this writes on every move rather than
--- on confirm. `cancelFunc` restores from values captured when the picker opened rather than the
--- `previousValues` it is handed, which cannot be wrong about which "previous" it means after a drag.
---
--- `enabled` is re-read on every `Refresh`: a colour that does nothing in the current mode dims rather
--- than hides, so the row stays put. Whoever owns the mode has to refresh the tree when it changes.
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

	-- Not `UIPanelButtonTemplate` with a colour laid inside it: that template's visible extent is not its
	-- frame rectangle (its own highlight is inset twelve pixels either side), so a colour inset far
	-- enough to clear the bevel wastes half the swatch and anything less leaves gold showing.
	local button = CreateFrame("Button", nil, row)

	PixelUtil.SetHeight(button, BOX_HEIGHT)

	local edge = button:CreateTexture(nil, "BORDER")

	edge:SetAllPoints(button)

	-- Snapped, all three rectangles, which is what keeps the swatch's right and bottom edges drawn: a
	-- grid cell is rarely a whole number of pixels wide, so a one-*unit* inset from a boundary landing
	-- mid-pixel rasterises to nothing on that side.
	local innerEdge = button:CreateTexture(nil, "ARTWORK")

	PixelUtil.SetPoint(innerEdge, "TOPLEFT", button, "TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
	PixelUtil.SetPoint(innerEdge, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)
	innerEdge:SetColorTexture(BLACK_FONT_COLOR:GetRGB())

	local swatch = button:CreateTexture(nil, "OVERLAY")

	PixelUtil.SetPoint(swatch, "TOPLEFT", innerEdge, "TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
	PixelUtil.SetPoint(swatch, "BOTTOMRIGHT", innerEdge, "BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)

	-- The outer edge turning gold *is* the hover state, as `ColorSwatchMixin:OnEnter` does it. A separate
	-- highlight texture would sit over the colour and misreport it.
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

			-- The alpha itself: `info.opacity` is "1.0 is fully shown, 0 is transparent"
			-- (`UIDropDownMenu.lua:301`), which is what the stored channel already means.
			opacity = a,
			swatchFunc = function()
				-- `SetupColorPickerAndShow` calls `SetColorRGB` before `Show`, so this fires once with the
				-- alpha of whatever the picker was last opened for (`ColorPickerFrame.lua:43,103`), and
				-- that write would land on this colour.
				if not ColorPickerFrame:IsShown() then
					return
				end

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

		-- The alpha is what reads as "off", and says so about the colour itself rather than a frame around
		-- it.
		local on = enabled == nil or enabled()

		button:SetEnabled(on)
		swatch:SetAlpha(on and 1 or 0.35)
		UpdateEdge(false)
	end

	function row:Layout(width)
		self:SetWidth(width)

		local column, control = Divide(self, width, labelWidth, caption)

		-- Widened to the dropdown's own overhang and shifted by it, so a swatch and a dropdown in the same
		-- column line up. The row still *occupies* only its column: the overhang is art, and the gutter it
		-- reaches into is 26 wide.
		button:ClearAllPoints()
		PixelUtil.SetPoint(button, "LEFT", self, "LEFT", column - SWATCH_OVERHANG, 0)
		PixelUtil.SetWidth(button, control + SWATCH_OVERHANG * 2)

		return ROW_HEIGHT
	end

	return row
end

--- A row of buttons where the selected one is disabled: the segmented Left/Right and Up/Down controls,
--- and the sub-tab strips inside a pane.
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

--- Two numbers on one row, for a setting that is really a pair. Boxes rather than two sliders, because a
--- pair is compared as much as it is set -- reading "4" and "4" off two thumbs means measuring both
--- against their own ranges first.
---
--- Commits on Enter or on losing focus, clamping rather than refusing.
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

			-- Re-read rather than left as typed, so a clamped or rejected entry shows what was stored.
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

--- A group heading inside a body.
---
--- Always spans, because a heading over one of two columns names half a group. A grid gives it a row of
--- its own and the group beneath starts back in the left column, so a group with an odd number of
--- controls leaves a hole -- order its members so that hole falls at the end rather than the middle.
---
--- `GameFontNormalMed2` is the one step between a control's label and a section title: 14 against
--- `GameFontNormal`'s 12 and `GameFontNormalLarge`'s 16, all three shadowed. `Med1` is 13 but carries no
--- shadow, so it reads as a different family rather than a level between them.
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

--- A single line naming the control beneath it, for one that spans its column and so has no label of its
--- own.
---
--- Neither existing leaf would do: `SubHeading` pads itself away from what it is meant to sit on, and
--- `Paragraph` only learns its height in `Layout` -- a caption wrapping to two lines in one locale would
--- silently push the list past the bottom of the tab. So: one line, no wrap, clipped with the truncation
--- tooltip every other clipped string carries.
---
--- Anchored `BOTTOMLEFT` like `SubHeading`'s text, so a taller alphabet grows up into the gap rather than
--- down into the control it captions.
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

--- Wrapped explanatory prose, and the one leaf whose height is not the row height: a string only knows
--- how tall it is once it knows how wide it may be, so the height is read in `Layout` after the width is
--- set. A column that narrows re-wraps and reports the taller answer on the next pass.
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

--- A button across the whole row.
---
--- `destructive` swaps the template rather than tinting the caption, and has to: red text on
--- `UI-DialogBox-goldbutton-up-middle` is dark on dark, and would not survive a mouseover either, since
--- `UIPanelButtonTemplate` swaps font objects on hover and that discards a `SetTextColor`.
--- `SharedButtonTemplate` (`ThreeSliceButtonTemplate.xml:69`) is the red button the game already ships.
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

--- Several buttons across one row, dividing it evenly.
---
--- `Segmented` looks like this and is not it: there the selection *is* the state and the disabled button
--- is the chosen one, where these are independent actions each dimmed by a question about the database.
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

--- A scrolling multi-line text box.
---
--- `set` absent is what makes a box read-only -- `EditBox` has no such flag, so a keystroke is undone in
--- `OnTextChanged` by resetting the text whenever the two disagree, the same trick a read-only
--- `StaticPopup` edit box uses. Selecting and copying still work.
---
--- `InputScrollFrameTemplate` sizes its `EditBox` once in its own `OnLoad`, against a width of one pixel
--- since nothing has laid it out yet, so `Layout` restates it every pass.
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

	-- The template only reads `hideCharCount` in its own `OnLoad`, before this box has been told anything.
	scroll.CharCount:Hide()

	local editBox = scroll.EditBox

	editBox:SetAutoFocus(false)

	-- What the box is meant to say, held here so the read-only guard below never calls `get`: for the
	-- export boxes that getter serialises, compresses and base64s the whole database, and calling it from
	-- `OnTextChanged` meant one full encode per keystroke.
	local expected = ""

	if set then
		editBox:SetScript("OnTextChanged", function(self)
			set(self:GetText())
		end)
	else
		editBox:SetScript("OnTextChanged", function(self)
			if self:GetText() ~= expected then
				self:SetText(expected)
			end
		end)

		-- Selected as soon as it is focused, not only through the Copy button beside it.
		editBox:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
		end)
	end

	function row:SetText(text)
		expected = text
		editBox:SetText(text)
	end

	function row:Highlight()
		editBox:SetFocus()
		editBox:HighlightText()
	end

	function row:Refresh()
		expected = get()

		if editBox:GetText() ~= expected then
			editBox:SetText(expected)
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
