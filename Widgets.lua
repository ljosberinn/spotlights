---@type string, Spotlights
local _, Private = ...

---@class SpotlightsWidgets
Private.Widgets = {}

--- Hand-rolled rather than Blizzard's Settings API, and the reason is combat.
---
--- `Settings.RegisterAddOnSetting` puts our panel inside Blizzard's own options frame, whose machinery
--- we do not control and cannot close on `PLAYER_REGEN_DISABLED` without reaching into it. Every
--- control here writes a setting that ends in a protected call on a header, so the whole surface has to
--- be closable and maskable by us. A kit this small is cheaper than fighting that.
---
--- Every widget follows the same contract: created once, it reads its value through a `get` callback
--- and writes through a `set` one, and `Refresh` re-reads. Nothing caches the database, so a setting
--- changed by a slash command with the panel open is not stale.

local ROW_HEIGHT = 26
local LABEL_WIDTH = 130

--- How wide a dropdown, colour swatch or sub-tab row is. Matched to `SLIDER_WIDTH` so every control in
--- the column ends at the same right edge (`LABEL_WIDTH + CONTROL_WIDTH`) rather than the dropdowns
--- stopping short of the sliders. The panel widened after the tab strip moved beside the portrait, and
--- 180 left that room unclaimed.
local CONTROL_WIDTH = 280

--- How wide the modern slider is, against the ~466 a row has after the inset and the scrollbar.
--- Blizzard's own settings use 214-250; 280 means the flat bar reads as the row's control rather than
--- as a sliver at the far end of the label's leftover space.
local SLIDER_WIDTH = 280

--- Anything the panel can put in a column. `Refresh` is the only method the panel calls.
---@class SpotlightsWidget : Frame
---@field Refresh fun(self: SpotlightsWidget)

---@param parent Frame
---@param text string
---@return FontString
local function CreateLabel(parent, text)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")

	label:SetPoint("LEFT", parent, "LEFT", 0, 0)
	label:SetWidth(LABEL_WIDTH)
	label:SetJustifyH("LEFT")
	label:SetText(text)

	return label
end

--- A row container, so every widget lines up without each one knowing the layout.
---@param parent Frame
---@return Frame
local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)

	row:SetHeight(ROW_HEIGHT)

	return row
end

--- A checkbox.
---
--- `UICheckButtonTemplate` rather than a hand-drawn box: a plain, unprotected Blizzard template with no
--- secure machinery and no shared state behind it, which is the only test that matters after WU-5b.
---@param parent Frame
---@param label string
---@param get fun(): boolean
---@param set fun(value: boolean)
---@param labelWidth number?
---@return SpotlightsWidget
function Private.Widgets.CreateCheckbox(parent, label, get, set, labelWidth)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]
	labelWidth = labelWidth or LABEL_WIDTH

	local labelWidget = CreateLabel(row, label)
	labelWidget:SetWidth(labelWidth)

	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")

	check:SetPoint("LEFT", row, "LEFT", labelWidth, 0)
	check:SetSize(ROW_HEIGHT, ROW_HEIGHT)

	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)

	function row:Refresh()
		check:SetChecked(get())
	end

	return row
end

--- A slider over a numeric setting.
---
--- Drawn by Blizzard's `MinimalSliderWithSteppersTemplate` (always-loaded `Blizzard_SharedXML`, the
--- same family as the settings panel's sliders): the bar, thumb and two steppers are atlas art, and the
--- mixin adds step-at-edge disabling and value narration for free. Writes on `OnValueChanged` rather
--- than mouse-up, which makes width and height feel like adjustments rather than guesses -- the grid
--- follows the drag. Every write goes through the deferral queue, so dragging costs one geometry pass
--- per frame rather than one per pixel.
---
--- The mixin's `Init(value, min, max, steps, formatters)` takes a *count* of steps and derives the step
--- from it, so the caller's `step` is converted back to a count here. `formatters` maps the mixin's
--- label enum to a function; `RightText` is the live value slot the old code drew by hand.
---@param parent Frame
---@param label string
---@param minimum number
---@param maximum number
---@param step number
---@param get fun(): number
---@param set fun(value: number)
---@return SpotlightsWidget
function Private.Widgets.CreateSlider(parent, label, minimum, maximum, step, get, set)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	CreateLabel(row, label)

	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")

	slider:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
	slider:SetWidth(SLIDER_WIDTH)

	-- The template's default height is 40, which the min/max labels need sitting *below* the bar. We
	-- never show those labels -- the value reads in `RightText` instead -- so the frame is crushed to
	-- the row's height and the extra 14px never overlap the row beneath.
	slider:SetHeight(ROW_HEIGHT)

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

	-- `Init` paints the control: it calls `SetValue`, which fires the mixin's `OnValueChanged` event.
	-- That first event fires *before* the callback below is registered, so it cannot reach the database
	-- -- there is no listener yet. Every event after the callback is a real change.
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

	-- Guards the write, not the read. `Refresh` re-reads a value a slash command may have changed behind
	-- the panel's back; `SetValue` fires the same event a drag does, and re-arming the guard keeps the
	-- re-draw from writing the value back.
	function row:Refresh()
		refreshing = true
		slider:SetValue(get())
		refreshing = false
	end

	return row
end

--- A dropdown over a list of choices.
---
--- Takes a list of `{ value, label }` pairs rather than a map, because the order the user sees has to
--- be stable and `pairs` over a settings map is not. `value` is what reaches the database.
---
--- `choices` may be a **function** returning that list, and for the texture picker it has to be.
--- Widgets are built once, on the first open of their tab, so a list passed as a table is captured then
--- and never revisited — silently dropping any media another addon registers afterwards. Resolved per
--- menu-open instead, the list is as current as LibSharedMedia is.
---@param parent Frame
---@param label string
---@param choices { value: any, label: string }[] | fun(): { value: any, label: string }[]
---@param get fun(): any
---@param set fun(value: any)
---@return SpotlightsWidget
function Private.Widgets.CreateDropdown(parent, label, choices, get, set)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	CreateLabel(row, label)

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")

	dropdown:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(CONTROL_WIDTH)

	-- The generator re-runs every time the menu opens, so the checked state is derived from the
	-- database at open time rather than tracked.
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
	--- would be overwritten the first time the menu opened, so a stale label would appear to fix itself
	--- on click.
	---
	--- Which also means the selection callback needs nothing: `OnMenuResponse` signals the update for
	--- us. This exists for the case Blizzard's path does not cover — the value changing behind the
	--- widget's back, from a slash command.
	function row:Refresh()
		dropdown:GenerateMenu()
	end

	return row
end

--- A push button.
---
--- Left-anchored by default, so it lines up with the labelled controls above and below it. `center`
--- anchors it to the row's middle instead, for a tab that is nothing but buttons and has no column of
--- labels to align against.
---@param parent Frame
---@param label string
---@param onClick fun()
---@param center boolean?
---@return SpotlightsWidget
function Private.Widgets.CreateButton(parent, label, onClick, center)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")

	if center then
		button:SetPoint("CENTER", row, "CENTER", 0, 0)
	else
		button:SetPoint("LEFT", row, "LEFT", 0, 0)
	end

	-- Spans the whole control column, so a left-anchored button ends where the dropdowns and sliders
	-- above and below it do rather than reaching a third of the way across the row.
	button:SetSize(LABEL_WIDTH + CONTROL_WIDTH, ROW_HEIGHT - 4)
	button:SetText(label)
	button:SetScript("OnClick", onClick)

	-- Nothing to re-read, but the panel calls Refresh on everything it owns.
	function row:Refresh() end

	return row
end

---@param parent Frame
---@param leftLabel string
---@param leftClick fun()
---@param rightLabel string
---@param rightClick fun()
---@return SpotlightsWidget
function Private.Widgets.CreateButtonPair(parent, leftLabel, leftClick, rightLabel, rightClick)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]
	local gap = 4
	local width = (parent:GetWidth() - gap) / 2

	local left = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	left:SetSize(width, ROW_HEIGHT - 4)
	left:SetPoint("LEFT", row, "LEFT")
	left:SetText(leftLabel)
	left:SetScript("OnClick", leftClick)

	local right = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	right:SetSize(width, ROW_HEIGHT - 4)
	right:SetPoint("RIGHT", row, "RIGHT")
	right:SetText(rightLabel)
	right:SetScript("OnClick", rightClick)

	function row:Refresh() end

	return row
end

--- A row of buttons where the active one is disabled, for switching which thing the controls below are
--- editing.
---
--- The same idiom as the panel's own tab strip: a flat row of buttons with one unclickable reads as a
--- selected tab without anyone drawing tab art. It costs no runtime, because nothing below is rebuilt
--- when the selection changes — every widget in this kit reads and writes through closures, so a switch
--- is a variable write plus the refresh the panel already does.
---@param parent Frame
---@param choices { value: any, label: string }[]
---@param get fun(): any
---@param set fun(value: any)
---@return SpotlightsWidget
function Private.Widgets.CreateSubTabs(parent, choices, get, set)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]
	local width = (LABEL_WIDTH + CONTROL_WIDTH) / #choices

	---@type Button[]
	local buttons = {}

	for i = 1, #choices do
		local choice = choices[i]
		local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")

		button:SetSize(width - 4, ROW_HEIGHT - 4)
		button:SetPoint("LEFT", row, "LEFT", (i - 1) * width, 0)
		button:SetText(choice.label)
		button:SetScript("OnClick", function()
			set(choice.value)
		end)

		buttons[i] = button
	end

	function row:Refresh()
		local current = get()

		for i = 1, #choices do
			buttons[i]:SetEnabled(choices[i].value ~= current)
		end
	end

	return row
end

--- A colour swatch that opens Blizzard's colour picker.
---
--- `get` and `set` deal in three numbers rather than a colour object, because that is how the setting
--- is stored — three fields, so a database written by one build reads on another without a metatable in
--- the way.
---
--- `swatchFunc` fires continuously while the wheel is dragged, so this writes on every move rather than
--- on confirm. That is safe for an expensive setting: `Private.Auras.SetSetting` debounces what it has
--- to, so a drag still costs one rebuild.
---
--- `cancelFunc` restores from the values captured when the picker opened, rather than the
--- `previousValues` the callback is handed — the capture cannot be wrong about which "previous" it
--- means after a drag.
---
--- `enabled`, when given, is re-read on every `Refresh` and decides whether the swatch can be opened: a
--- colour that does nothing in the current mode (a static colour while class colour is on) is dimmed
--- and made unclickable rather than hidden, so the row stays put and no relayout is needed. The caller
--- that owns the mode has to `Refresh` the panel when it changes for this to re-evaluate.
---@param parent Frame
---@param label string
---@param get fun(): number, number, number
---@param set fun(r: number, g: number, b: number)
---@param enabled fun(): boolean|nil
---@return SpotlightsWidget
function Private.Widgets.CreateColorPicker(parent, label, get, set, enabled)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	CreateLabel(row, label)

	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")

	button:SetSize(CONTROL_WIDTH, ROW_HEIGHT - 6)
	button:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)

	local swatch = button:CreateTexture(nil, "OVERLAY")

	swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -4)
	swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 4)

	button:SetScript("OnClick", function()
		local r, g, b = get()

		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			hasOpacity = false,
			swatchFunc = function()
				local newR, newG, newB = ColorPickerFrame:GetColorRGB()

				swatch:SetColorTexture(newR, newG, newB)
				set(newR, newG, newB)
			end,
			cancelFunc = function()
				swatch:SetColorTexture(r, g, b)
				set(r, g, b)
			end,
		})
	end)

	function row:Refresh()
		swatch:SetColorTexture(get())

		-- The swatch is a child texture, so the button's own disabled art does not reach it -- the alpha
		-- is what reads as "off". Left fully opaque when there is no predicate at all.
		local on = enabled == nil or enabled()

		button:SetEnabled(on)
		swatch:SetAlpha(on and 1 or 0.35)
	end

	return row
end

--- A section heading. Not a control and not body text: a tab with two independent groups of controls
--- needs the boundary between them visible, and indentation cannot express it in a single column.
---@param parent Frame
---@param text string
---@return SpotlightsWidget
function Private.Widgets.CreateHeading(parent, text)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	local heading = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")

	heading:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
	heading:SetJustifyH("LEFT")
	heading:SetText(text)

	function row:Refresh() end

	return row
end

--- A block of explanatory text. Not a control, but it takes part in the same layout and the
--- combat-reload limitation has to be documented *somewhere* the user will see it.
---@param parent Frame
---@param text string
---@return SpotlightsWidget
function Private.Widgets.CreateText(parent, text)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	local body = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	body:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

	-- The full content width rather than the control column's `LABEL_WIDTH + CONTROL_WIDTH`, which
	-- wrapped text short of the panel edge. `Stack` anchors the row across the whole of `parent`, so
	-- the row is that wide once laid out -- but the wrapped height has to be known here, before `Stack`
	-- runs, so the width is read from `parent` (which has an explicit `SetWidth`) rather than from the
	-- not-yet-anchored row.
	body:SetWidth(parent:GetWidth())
	body:SetJustifyH("LEFT")
	body:SetSpacing(2)
	body:SetText(text)

	-- Height comes from the wrapped text rather than ROW_HEIGHT, the one widget whose height is not
	-- known until the string is set.
	row:SetHeight(body:GetStringHeight() + 8)

	function row:Refresh() end

	return row
end

--- A spell row is shorter than a control row: one line of text and a checkbox, and at `ROW_HEIGHT` a
--- list of fifty reads as a very long ladder. A class heading is taller than the rows it introduces for
--- the same reason `RosterList` makes its headings taller — prominence in a flat list of same-height
--- rows comes from spacing as much as from type size.
local SPELL_ROW_HEIGHT = 20
local CLASS_ROW_HEIGHT = 26
local SPELL_ICON_SIZE = 16

--- The width the checkbox and the remove button occupy at the right edge.
---
--- The remove column is reserved in **both** lists even though only the custom one uses it, so the
--- checkboxes line up between the two tables rather than sitting 20px apart.
local REMOVE_WIDTH = 20

--- Sized to the spell row rather than to `ROW_HEIGHT`, which is six pixels taller. A checkbox that
--- overhangs its own row overlaps the one under it, and in a fifty-row list that reads as the rows
--- being crooked rather than the checkbox being too big.
local CHECK_WIDTH = SPELL_ROW_HEIGHT

--- How long typing has to stop before an ID is looked up.
---
--- `C_Spell.GetSpellName` on a not-yet-cached spell is a request as much as a read, so debouncing is
--- not only about the frames — typing `123456` unthrottled asks the client about five spells nobody
--- was looking for on the way to the sixth.
local LOOKUP_DELAY = 0.35

--- What a spell row shows, given an ID the client may not have cached yet.
---
--- A missing name is not an error and not a permanently unknown spell: `C_Spell.GetSpellName` answers
--- nil until the client has the data and fills it in afterwards, so the ID stands in for the name and
--- the next `Refresh` picks up the real one. An ID that is genuinely not a spell keeps showing as its
--- own number.
--- The texture is a **file ID** when the spell has one and a path when it does not, which is why the
--- annotation admits both: `SetTexture` takes either, and normalising them would mean resolving a file
--- ID to a path for no reader's benefit.
---@param spellID integer
---@return string label, string|integer texture
local function SpellDisplay(spellID)
	local name = C_Spell.GetSpellName(spellID)

	return name and string.format("%s (%d)", name, spellID) or tostring(spellID),
		C_Spell.GetSpellTexture(spellID) or QUESTION_MARK_ICON
end

--- One row of a spell list, built once and re-pointed at whatever the list needs it to be.
---
--- Every part exists on every row and unused ones are hidden, rather than a row type per kind. Which
--- kind a given frame is changes on every rebuild — the rows are pooled and a heading can become a
--- spell — so a row that carried only some parts would have to be destroyed to change kind, and frames
--- cannot be destroyed.
---@param list Frame
---@param rows table[]
---@param index integer
---@return table
local function AcquireSpellRow(list, rows, index)
	local row = rows[index]

	if row then
		return row
	end

	row = CreateFrame("Frame", nil, list)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

	-- The border every icon file ships with, cropped off, exactly as the aura displays crop theirs.
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -(CHECK_WIDTH + REMOVE_WIDTH + 4), 0)
	row.label:SetJustifyH("LEFT")

	row.heading = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.heading:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
	row.heading:SetJustifyH("LEFT")

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(CHECK_WIDTH, CHECK_WIDTH)
	row.check:SetPoint("RIGHT", row, "RIGHT", -REMOVE_WIDTH, 0)

	-- The same red exit atlas the roster's remove buttons use, rather than an "X" text button, so the
	-- gesture that means "remove this" looks the same in both lists. The icon carries the meaning, so no
	-- text is set; a hover tint sized to the icon stands in for the button-template highlight.
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(REMOVE_WIDTH, SPELL_ROW_HEIGHT - 2)
	row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	row.remove.icon = row.remove:CreateTexture(nil, "ARTWORK")
	row.remove.icon:SetPoint("CENTER")
	row.remove.icon:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
	row.remove.icon:SetAtlas("RedButton-Exit")

	row.remove.highlight = row.remove:CreateTexture(nil, "HIGHLIGHT")
	row.remove.highlight:SetPoint("CENTER")
	row.remove.highlight:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
	row.remove.highlight:SetColorTexture(1, 1, 1, 0.18)

	rows[index] = row

	return row
end

--- A list of spells with a checkbox each, optionally removable, grouped by whatever headings the caller
--- interleaves into its entries.
---
--- **A single widget that rebuilds its own rows**, the same shape as `Private.RosterList.Build` and for
--- the same reason: the panel's `Stack` pass runs once, and a list whose length changes when the user
--- adds a spell cannot be a run of widgets in `tab.widgets` without invalidating every offset below it.
--- One widget with a height it sets itself keeps that list fixed-length.
---
--- `rows` is per widget rather than a module local — unlike `RosterList`, which affords one cache
--- because there is only ever one of it. There are two of these on the aura tab, and a shared cache
--- would have them fighting over the same frames.
---
--- `Entries` returns a flat ordered array so grouping is the caller's business, not this widget's:
--- `{ heading = "Warrior", r = 0.78, g = 0.61, b = 0.43 }` draws a class heading, and
--- `{ spellID = 1719 }` draws a spell. The built-in list interleaves both; the custom list supplies
--- only the second.
---@param parent Frame
---@param Entries fun(): { heading: string?, spellID: integer?, r: number?, g: number?, b: number? }[]
---@param IsEnabled fun(spellID: integer): boolean
---@param SetEnabled fun(spellID: integer, enabled: boolean)
---@param OnRemove fun(spellID: integer)? when absent, no row is removable
---@return SpotlightsWidget
function Private.Widgets.CreateSpellList(parent, Entries, IsEnabled, SetEnabled, OnRemove)
	local list = CreateFrame("Frame", nil, parent) --[[@as SpotlightsWidget]]

	---@type table[]
	local rows = {}

	--- Rebuilt wholesale rather than diffed, on the same grounds as the roster list: the entries number
	--- in the dozens, this runs when the panel is opened or a checkbox clicked, and a diff would be more
	--- code than the whole widget.
	function list:Refresh()
		local entries = Entries()
		local offset = 0

		for i = 1, #entries do
			local entry = entries[i]
			local row = AcquireSpellRow(list, rows, i)
			local heading = entry.heading

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -offset)
			row:SetHeight(heading and CLASS_ROW_HEIGHT or SPELL_ROW_HEIGHT)
			row:Show()

			-- Set every time rather than only when it changes, because the rows are pooled: the frame
			-- that is a heading now was a spell row a rebuild ago.
			row.heading:SetShown(heading ~= nil)
			row.icon:SetShown(heading == nil)
			row.label:SetShown(heading == nil)
			row.check:SetShown(heading == nil)
			row.remove:SetShown(heading == nil and OnRemove ~= nil)

			if heading then
				row.heading:SetText(heading)
				row.heading:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1)
			else
				local spellID = entry.spellID --[[@as integer]]
				local label, texture = SpellDisplay(spellID)

				row.label:SetText(label)
				row.icon:SetTexture(texture)
				row.check:SetChecked(IsEnabled(spellID))

				-- Rebound on every rebuild rather than captured once, for the pooling reason above: a
				-- handler closed over the spell this frame showed last time would toggle the wrong one.
				row.check:SetScript("OnClick", function(check)
					SetEnabled(spellID, check:GetChecked() and true or false)
				end)

				row.remove:SetScript("OnClick", function()
					if OnRemove then
						OnRemove(spellID)
					end
				end)
			end

			offset = offset + row:GetHeight()
		end

		for i = #entries + 1, #rows do
			rows[i]:Hide()
		end

		-- Not knowable until the rows exist, and the scroll child's height is the sum of every widget on
		-- the tab -- so this sets its own and asks the panel to add them up again.
		list:SetHeight(math.max(offset, 1))
	end

	return list
end

--- A numeric entry box with an Add button and a preview of whatever is currently typed.
---
--- The preview is the point. A spell ID is not something anyone can proofread, so the only way to know
--- that 466772 is Doom Winds and not a typo is to be shown the icon and name before committing -- and
--- to be shown nothing when the number names no spell, which is the same signal.
---
--- `OnAdd` is expected to answer whether the ID was taken, and the box clears only when it was.
---@param parent Frame
---@param label string
---@param addLabel string
---@param OnAdd fun(spellID: integer): boolean
---@return SpotlightsWidget
function Private.Widgets.CreateSpellInput(parent, label, addLabel, OnAdd)
	local row = CreateRow(parent) --[[@as SpotlightsWidget]]

	local caption = CreateLabel(row, label)

	local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")

	-- Against the caption's *text* rather than at `LABEL_WIDTH`, where every other control starts. A
	-- control row spends that width on a label so the controls below line up; this row has a preview to
	-- fit instead, and "Spell ID" is a third of the column. Measured rather than guessed, so a
	-- translation that needs more of it takes more.
	--
	-- `InputBoxTemplate` insets its own left edge by 8, hence the extra offset.
	input:SetPoint("LEFT", caption, "LEFT", caption:GetStringWidth() + 14, 0)
	input:SetSize(70, ROW_HEIGHT - 6)
	input:SetAutoFocus(false)

	-- Digits only, the whole of the validation this needs: a spell ID is a positive integer, and
	-- refusing the keystroke is a clearer answer than accepting text and rejecting it on Add.
	input:SetNumeric(true)
	input:SetMaxLetters(9)

	local add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")

	add:SetSize(52, ROW_HEIGHT - 4)
	add:SetPoint("LEFT", input, "RIGHT", 8, 0)
	add:SetText(addLabel)

	--- The preview, inline in whatever the controls left over.
	---
	--- Beside the box rather than under it, the difference between a preview and an interruption: below
	--- the row it lived inside the scroll content, so appearing made the content taller and pushed the
	--- answer to what had just been typed below the fold. Filling space the row already occupies cannot
	--- move anything -- the row's height never changes, and nothing here asks the panel to lay out again.
	local icon = row:CreateTexture(nil, "ARTWORK")

	icon:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
	icon:SetPoint("LEFT", add, "RIGHT", 10, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local previewLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	previewLabel:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	previewLabel:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	previewLabel:SetJustifyH("LEFT")

	-- Long names get an ellipsis rather than overrunning the row, since what is left after the controls
	-- is not much and a spell name is not a fixed width.
	previewLabel:SetWordWrap(false)

	---@type FunctionContainer?
	local timer

	--- Shows what the typed ID names, or nothing.
	---
	--- Both regions are children of the row, so hiding the row hides them -- every route that matters:
	--- the sub-tab switching away, the tab switching away, and the panel closing.
	local function ShowPreview()
		local spellID = tonumber(input:GetText())
		local name = spellID and spellID > 0 and C_Spell.GetSpellName(spellID)
		local found = type(name) == "string"

		icon:SetShown(found)
		previewLabel:SetShown(found)

		if found and spellID then
			local text, texture = SpellDisplay(spellID)

			previewLabel:SetText(text)
			icon:SetTexture(texture)
		end
	end

	input:SetScript("OnTextChanged", function()
		if timer then
			timer:Cancel()
		end

		timer = C_Timer.NewTimer(LOOKUP_DELAY, ShowPreview)
	end)

	--- Hands the ID over, and clears only if it was accepted.
	---
	--- Clearing unconditionally would silently swallow a duplicate — the box would empty, the list would
	--- not change, and nothing would say why. Left in place, the number is still there to look at.
	local function Commit()
		local spellID = tonumber(input:GetText())

		if not spellID or spellID <= 0 or not OnAdd(spellID) then
			return
		end

		input:SetText("")
		input:ClearFocus()
		ShowPreview()
	end

	add:SetScript("OnClick", Commit)
	input:SetScript("OnEnterPressed", Commit)

	-- Escape gives the box back rather than trapping the user in it, since the panel itself is in
	-- `UISpecialFrames` and Escape would otherwise be swallowed.
	input:SetScript("OnEscapePressed", function()
		input:ClearFocus()
	end)

	function row:Refresh()
		ShowPreview()
	end

	return row
end

--- Stacks widgets down a column, and is the only thing that knows the spacing.
---
--- Returns the total height so the panel can size a scroll child without every caller adding up rows.
---
--- **A hidden widget takes no space and gets no anchor.** That is what lets a tab hold controls
--- belonging to only one of its sub-tabs: the widget hides itself in its own `Refresh`, the next stack
--- pass closes the gap, and the scroll extent shrinks to match. Anchoring one anyway would leave a hole
--- the height of a section, and the aura tab's spell lists are hundreds of pixels tall.
---
--- Which makes the ordering a real requirement: `Refresh` decides visibility and has to have run before
--- this does, so `Relayout` is the entry point and not this.
---@param widgets SpotlightsWidget[]
---@param parent Frame
---@return number height
function Private.Widgets.Stack(widgets, parent)
	local offset = 0

	for i = 1, #widgets do
		local widget = widgets[i]

		if widget:IsShown() then
			widget:ClearAllPoints()
			widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -offset)
			widget:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -offset)

			offset = offset + widget:GetHeight() + 4
		end
	end

	return offset
end
