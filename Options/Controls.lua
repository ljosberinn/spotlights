---@type string, Spotlights
local _, Private = ...

---@class SpotlightsControls
Private.Controls = {}

--- The leaves of the layout kit, ported from `Widgets.lua` with the anchoring changed.
---
--- That kit computes every position from `LABEL_WIDTH + CONTROL_WIDTH = 410`, which is an assumption
--- rather than a width: there is one column and it is that wide. A leaf here is handed its width in
--- `Layout` and places itself inside it.

local ROW_HEIGHT = 26
local DEFAULT_LABEL_WIDTH = 130
local LABEL_GAP = 6

--- What a control keeps for itself when the label column would not leave it that much. A leaf dropped
--- into a 196px rail cannot honour 130px of label and still be a control, and a clipped label is
--- recoverable where a 20px dropdown is not.
local MIN_CONTROL_WIDTH = 80

--- Shorter than a row, so a sub-heading reads as a break between groups rather than as a control that
--- lost its widget.
local HEADING_HEIGHT = 20

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
--- (`ColorSwatch.xml`). Reproduced rather than inherited because that template hard-codes 16x16 in its
--- own `OnShow` through `PixelUtil`, so it cannot be stretched across a control column.
local SWATCH_BORDER = 1

---@param parent Frame
---@return SpotlightsNode
local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	row:SetHeight(ROW_HEIGHT)

	return row
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
---@param parent Frame
---@param label string
---@param get fun(): boolean
---@param set fun(value: boolean)
---@param full boolean?
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.Checkbox(parent, label, get, set, full, labelWidth)
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
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.Slider(parent, label, minimum, maximum, step, get, set, labelWidth)
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

	-- The step the caller gives is a *distance*; the mixin wants the number of steps across the range.
	-- `math.max` guards a `step` wider than the range, which would otherwise ask for a fractional count
	-- and then divide by it.
	local steps = math.max(math.floor((maximum - minimum) / step), 1)

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
---@param parent Frame
---@param label string
---@param choices { value: any, label: string }[] | fun(): { value: any, label: string }[]
---@param get fun(): any
---@param set fun(value: any)
---@param labelWidth number?
---@return SpotlightsNode
function Private.Controls.Dropdown(parent, label, choices, get, set, labelWidth)
	local row = CreateRow(parent)

	local caption = CreateLabel(row, label)
	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")

	-- The generator re-runs every time the menu opens, so the checked state is derived from the database at
	-- open time rather than tracked.
	dropdown:SetupMenu(function(_, rootDescription)
		local current = type(choices) == "function" and choices() or choices

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
	--- whichever report themselves selected (`DropdownButton.lua:137-139`). Writing the text ourselves
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

	button:SetHeight(BOX_HEIGHT)

	local edge = button:CreateTexture(nil, "BORDER")

	edge:SetAllPoints(button)

	local innerEdge = button:CreateTexture(nil, "ARTWORK")

	innerEdge:SetPoint("TOPLEFT", button, "TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
	innerEdge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)
	innerEdge:SetColorTexture(BLACK_FONT_COLOR:GetRGB())

	local swatch = button:CreateTexture(nil, "OVERLAY")

	swatch:SetPoint("TOPLEFT", innerEdge, "TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
	swatch:SetPoint("BOTTOMRIGHT", innerEdge, "BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)

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

		button:ClearAllPoints()
		button:SetPoint("LEFT", self, "LEFT", column, 0)
		button:SetWidth(control)

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

--- A sub-heading inside a section's body: the `Border` line above the four border controls.
---
--- Always spans, because a heading over one of two columns names half a group and reads as a control that
--- lost its widget.
---@param parent Frame
---@param text string | fun(): string
---@return SpotlightsNode
function Private.Controls.SubHeading(parent, text)
	local row = CreateRow(parent)

	row.span = true

	local heading = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")

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
--- `UIPanelButtonTemplate` declares `GameFontNormalOutline` and `GameFontHighlightOutline`, and swapping
--- font objects discards a `SetTextColor`. `SharedButtonTemplate` is the red button the game already ships
--- (`ThreeSliceButtonTemplate.xml:70`), with its own pressed and disabled states.
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

--- A scrolling multi-line text box: the Import/Export tab's read-only export pane and paste-in import
--- pane.
---
--- `set` absent is what makes a box read-only -- `EditBox` has no such flag, so a keystroke is undone
--- in `OnTextChanged` by resetting the text to `get()` whenever the two disagree, the trick the old
--- `StaticPopup`'s read-only edit box used (`Settings.lua`'s `EditBoxOnTextChanged`). Selecting and
--- copying still work; typing does not stick.
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
