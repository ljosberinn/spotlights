---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraAppearance
Private.AuraAppearance = {}

--- The Auras tab's Appearance sub-tab: one collapsible section per kind of display the selected category
--- can draw, scrolling under a pinned reset button.
---
--- Five display modes flat would be a wall of four dozen controls with nothing saying which is on. A
--- section answers both in its header: the display's name, and a summary formatted from the very fields
--- its body edits.
---
--- Which category this is about lives in `Options/Auras.lua` and reaches here as an accessor rather than
--- a copy: the Tracked sub-tab is about the same category, and neither of them owns it.

local Orientation = Private.Enum.Orientation
local GrowDirection = Private.Enum.AuraGrowDirection

--- What the label column costs in the ~250px half of a section's control grid. Narrower than the
--- Appearance tab's 120 because these labels are one or two short words, and the sliders here are the
--- ones dragged against a preview.
local COLUMN_LABEL_WIDTH = 110

--- Between one section and the next. Wider than the kit's row rhythm on purpose: at the column default a
--- body's last control sits as close to the next header as to its own siblings.
local SECTION_GAP = 12

--- How "no border" is spelled. Restated here rather than reached for across a module boundary, so the
--- summary tests exactly what `StyleBorder` tests.
local BORDER_NONE = "None"

--- The icon's floor is where spell art is still recognisable; its ceiling is past any spotlight the frame
--- sliders can produce.
local ICON_SIZE_MIN, ICON_SIZE_MAX = 16, 128

-- Below the icon's floor deliberately: a block is the display for a size where spell art cannot be read.
local SQUARE_SIZE_MIN, SQUARE_SIZE_MAX = 4, 128
local BAR_WIDTH_MIN, BAR_WIDTH_MAX = 1, 500
local BAR_HEIGHT_MIN, BAR_HEIGHT_MAX = 1, 200
local GAP_MIN, GAP_MAX = 0, 40
local FONT_SIZE_MIN, FONT_SIZE_MAX = 6, 32
local BORDER_SIZE_MIN, BORDER_SIZE_MAX = 1, 32
local OFFSET_MIN, OFFSET_MAX = -200, 200

--- Never fully transparent: a display at zero opacity is indistinguishable from one that failed to
--- build. The step is what the value box shows -- see `Controls`' `FRACTION_STEP`.
local ALPHA_MIN, ALPHA_MAX, ALPHA_STEP = 0.05, 1, 0.01

--- The gap under the Auras tab's sub-tab strip. The scroll pane gets everything else, so it fills the
--- tab rather than a guess at how tall two sections "usually" are.
local CHROME_RESERVE = 6

--- Floor for the scroll pane, in case the window is shorter than this tab's chrome costs: better a
--- cramped pane than a negative height Blizzard errors on.
local MIN_SCROLL_HEIGHT = 80

--- Shared with the Tracked sub-tab deliberately: the dialog is registered at click time by whichever
--- button was clicked, and two keys would stack two identical prompts.
local RESET_POPUP = "SPOTLIGHTS_AURA_RESET"

--- Which category the strip has selected, and its localised name for the reset prompt. Both handed in by
--- `Build`, because the strip they come from is not this file's.
---@type fun(): SpotlightsAuraFeatureKey
local ActiveFeature

---@type fun(): string
local ActiveName

--- The parts of this tab that mirror settings rather than edit them, kept so a write can repaint them
--- without re-reading the controls it came from.
---@type SpotlightsSectionNode[]
local sections = {}

--- Which display each entry of `sections` is about, by position. **The two are built apart and have to
--- stay in step** -- `Build` assembles `sections` from five locals, and `SyncSections` pairs them off
--- against this.
---@type SpotlightsAuraDisplayKey[]
local SECTION_DISPLAY_KEYS = { "icon", "bar", "square", "text", "frameColor" }

---@type SpotlightsPreviewPaneNode[]
local panes = {}

---@return SpotlightsAuraFeatureConfig
local function Feature()
	local auras = Private.DB and Private.DB.auras
	local feature = auras and auras[ActiveFeature()]

	-- The defaults stand in only before `ADDON_LOADED`, when the panel cannot be open. Falling back to
	-- them rather than to a literal per field means a control can never show a number this addon does not
	-- ship with.
	return feature or Private.Migration.DefaultAuraFeature(ActiveFeature())
end

---@return SpotlightsAuraBarConfig
local function Bar()
	return Feature().bar
end

---@return SpotlightsAuraIconConfig
local function Icon()
	return Feature().icon
end

---@return SpotlightsAuraSquareConfig
local function Square()
	return Feature().square
end

---@return SpotlightsAuraTextConfig
local function Text()
	return Feature().text
end

---@return SpotlightsAuraFrameColorConfig
local function FrameColor()
	return Feature().frameColor
end

--- Any display's block by key, for the read/write factories below. The typed accessors above are what
--- the summaries use, since those read named fields.
---@param displayKey SpotlightsAuraDisplayKey
---@return SpotlightsAuraDisplayConfig
local function Display(displayKey)
	if displayKey == "bar" then
		return Bar()
	end

	if displayKey == "square" then
		return Square()
	end

	if displayKey == "text" then
		return Text()
	end

	if displayKey == "frameColor" then
		return FrameColor()
	end

	return Icon()
end

--- Repaints what shows a setting without re-reading what sets it: the section headers and the preview
--- pane inside each body.
---
--- Deliberately not `Options.Refresh`. A colour picker fires on every frame of a drag, and a whole-tree
--- refresh would regenerate every dropdown's menu with it.
---
--- It does re-evaluate the combined pane's `OnlyWhen`, so a write crossing the one-versus-two boundary
--- changes a section's height from in here -- which is why `EnabledSetter` follows this with a layout
--- pass and the other setters do not.
local function RefreshSections()
	for i = 1, #sections do
		sections[i]:RefreshHeader()
	end

	for i = 1, #panes do
		panes[i]:Refresh()
	end
end

--- Writes one aura setting through the one entry point that knows what it costs. Requests nothing
--- itself: a settings file that knew which fields are frozen would be a second copy of a list that can
--- only be wrong.
---@param displayKey SpotlightsAuraDisplayKey
---@param field string
---@param value any
local function SetAura(displayKey, field, value)
	Private.Auras.SetSetting(ActiveFeature(), displayKey, field, value)

	-- The grid previews are where a drag's feedback comes from: half of these settings reach a live
	-- display only after a debounce and a rebuild.
	Private.AuraPreview.Restyle()
	RefreshSections()
end

--- Reads one display field. A factory rather than a function per setting, since every field on this tab
--- is read the same way.
---@param displayKey SpotlightsAuraDisplayKey
---@param field string
---@return fun(): any
local function Getter(displayKey, field)
	return function()
		return Display(displayKey)[field]
	end
end

---@param displayKey SpotlightsAuraDisplayKey
---@param field string
---@return fun(value: any)
local function Setter(displayKey, field)
	return function(value)
		SetAura(displayKey, field, value)
	end
end

--- Writes a display's switch, then lays the tab out again: the one field here whose write can change how
--- tall a section is, since the combined pane appears at two enabled displays and goes at one. Without a
--- pass after it the section keeps the height it had.
---
--- `Relayout` rather than the `Refresh` the setters below use: nothing here shows a changed value, and a
--- refresh would regenerate every dropdown's menu and re-read an edit in progress.
---@param displayKey SpotlightsAuraDisplayKey
---@return fun(value: any)
local function EnabledSetter(displayKey)
	return function(value)
		SetAura(displayKey, "enabled", value)
		Private.Node.Relayout()
	end
end

--- The thickness and colour beside the style gate on it but only sample it in their own `Refresh`, so
--- the plain setter would leave a just-disabled swatch looking clickable. No relayout is owed: a
--- disabled control dims rather than hides.
---@param displayKey SpotlightsAuraDisplayKey
---@return fun(value: any)
local function BorderStyleSetter(displayKey)
	return function(value)
		SetAura(displayKey, "borderTexture", value)
		Private.Options.Refresh()
	end
end

--- Writes the bar's fill axis and re-reads the whole tab: the plain setter would leave the icon-side and
--- fill-direction dropdowns naming ends of the axis the bar no longer runs along. Both lists are
--- generated per menu-open, and only a refresh regenerates the *closed* button's text.
---@param value SpotlightsOrientation
local function OrientationSetter(value)
	SetAura("bar", "orientation", value)
	Private.Options.Refresh()
end

--- Reads a colour stored as four separately named fields. Named rather than derived from a prefix: a
--- bar's own colour is `r`/`g`/`b`/`alpha` while its border's is `borderR`..`borderA`.
---@param displayKey SpotlightsAuraDisplayKey
---@param red string
---@param green string
---@param blue string
---@param alpha string
---@return fun(): number, number, number, number
local function ColorGetter(displayKey, red, green, blue, alpha)
	return function()
		local config = Display(displayKey)

		return config[red], config[green], config[blue], config[alpha]
	end
end

--- Writes all four channels, then repaints once. The four writes collapse into one rebuild entry since
--- they name the same display; the *repaint* is what must not be repeated, because a colour picker fires
--- continuously while dragged.
---@param displayKey SpotlightsAuraDisplayKey
---@param red string
---@param green string
---@param blue string
---@param alpha string
---@return fun(r: number, g: number, b: number, a: number)
local function ColorSetter(displayKey, red, green, blue, alpha)
	return function(r, g, b, a)
		local featureKey = ActiveFeature()

		Private.Auras.SetSetting(featureKey, displayKey, red, r)
		Private.Auras.SetSetting(featureKey, displayKey, green, g)
		Private.Auras.SetSetting(featureKey, displayKey, blue, b)
		Private.Auras.SetSetting(featureKey, displayKey, alpha, a)

		Private.AuraPreview.Restyle()
		RefreshSections()
	end
end

--- Whether a display draws a border at all, which is the one thing its thickness and its colour both
--- depend on: `None` is LibSharedMedia's empty path, and `StyleBorder` hides the backdrop outright
--- rather than drawing a nothing-wide edge in the chosen colour.
---@param displayKey SpotlightsAuraDisplayKey
---@return fun(): boolean
local function HasBorder(displayKey)
	return function()
		return Display(displayKey).borderTexture ~= BORDER_NONE
	end
end

--- What a summary says about a display's border, which is either its thickness or that there is none.
---@param config SpotlightsAuraDisplayConfig
---@return string
local function BorderPhrase(config)
	local L = Private.L.Settings

	if config.borderTexture == BORDER_NONE then
		return L.AuraSummaryNoBorder
	end

	return string.format(L.AuraSummaryBorder, config.borderSize)
end

--- The header line for a display that is switched off. A size and an anchor for something nothing will
--- draw is worse than no summary: the point of the header is answering "is this on" without expanding it.
---@param config SpotlightsAuraDisplayConfig
---@return string?
local function HiddenSummary(config)
	if config.enabled then
		return nil
	end

	return Private.L.Settings.AuraSummaryHidden
end

--- The anchor point in prose, falling back to the stored key. `ApplyAnchor` treats a point it does not
--- recognise as `CENTER`, but a summary that silently renamed a damaged setting would hide it.
---@param config SpotlightsAuraDisplayConfig
---@return string
local function AnchorName(config)
	return Private.L.Settings.Anchors[config.point] or config.point
end

---@return string
local function IconSummary()
	local L = Private.L.Settings
	local config = Icon()

	return HiddenSummary(config) or string.format(L.AuraSummary, config.width, config.height,
		AnchorName(config), config.showSwipe and L.AuraSummarySwipeOn or L.AuraSummarySwipeOff,
		BorderPhrase(config))
end

--- The axis and the end the fill is anchored to as one phrase, because naming only the axis summarises a
--- reversed bar as the bar it is not. Shared with the dropdown that sets it, so the header uses the
--- control's own words.
---@param config SpotlightsAuraBarConfig
---@return string
local function FillName(config)
	local L = Private.L.Settings

	if config.orientation == Orientation.Vertical then
		return config.reverseFill and L.AuraFillTopToBottom or L.AuraFillBottomToTop
	end

	return config.reverseFill and L.AuraFillRightToLeft or L.AuraFillLeftToRight
end

--- Its own format string: a `100 × 25` that drains upward reads as a lie without the direction beside it,
--- and no other display has a direction to name.
---@return string
local function BarSummary()
	local L = Private.L.Settings
	local config = Bar()

	return HiddenSummary(config) or string.format(L.AuraSummaryBar, config.width, config.height,
		FillName(config), AnchorName(config),
		config.showIcon and L.AuraSummaryInlineIcon or L.AuraSummaryNoInlineIcon, BorderPhrase(config))
end

--- The same five fields as the icon's, with the size twice over since one field drives both axes.
---@return string
local function SquareSummary()
	local L = Private.L.Settings
	local config = Square()

	return HiddenSummary(config) or string.format(L.AuraSummary, config.size, config.size,
		AnchorName(config), config.showSwipe and L.AuraSummarySwipeOn or L.AuraSummarySwipeOff,
		BorderPhrase(config))
end

--- Three fields shorter: no size setting to name, since the rect is derived from the font size, and no
--- swipe, since a swipe with nothing under it is the square.
---@return string
local function TextSummary()
	local L = Private.L.Settings
	local config = Text()

	return HiddenSummary(config) or string.format(L.AuraSummaryText, config.fontSize,
		AnchorName(config), BorderPhrase(config))
end

--- The shortest of the five: no size, anchor or border, because the rect is the health bar's. What is
--- left is the opacity, which decides whether the class colour shows through.
---@return string
local function FrameColorSummary()
	local L = Private.L.Settings
	local config = FrameColor()

	return HiddenSummary(config)
		or string.format(L.AuraSummaryFrameColor, math.floor(config.alpha * 100 + 0.5))
end

local OnlyWhen = Private.Node.OnlyWhen

--- Gives a control a row of its own, closing whatever row was being filled. `span` is the grid's own
--- field; this only lets it be set on a control built inside a list, which keeps the pairs around it from
--- re-flowing when a category changes which controls exist.
---@param node SpotlightsNode
---@return SpotlightsNode
local function Full(node)
	node.span = true

	return node
end

--- Counted through `HasDisplay` rather than over the five `enabled` flags: every feature stores a block
--- for all five kinds whatever it renders, and a profile import arrives with whatever the exporter had,
--- so a flag on a kind the category never draws must not count.
---@return integer
local function EnabledDisplayCount()
	local featureKey = ActiveFeature()
	local count = 0

	for i = 1, #SECTION_DISPLAY_KEYS do
		local displayKey = SECTION_DISPLAY_KEYS[i]

		if Private.Auras.HasDisplay(featureKey, displayKey) and Display(displayKey).enabled then
			count = count + 1
		end
	end

	return count
end

--- How tall the combined pane's stage is, against the shared 96: 55px either side of a default 100 × 50
--- spotlight, where the shared height leaves 23. Y is the axis that clips first at every frame size near
--- the default, and the axis two displays are separated along.
---
--- X is not fixed and cannot be: `PreviewPane.Width` is what the `Split` pins against, so widening this
--- pane alone re-flows every section's control grid.
local COMBINED_STAGE_HEIGHT = 160

--- The pane beside one section's controls, with that section's display and only that one hung off it. A
--- nil `displayKey` is the combined pane below it, which takes every kind the category draws.
---
--- Records are built per category and **kept** rather than rebuilt on every switch: a preview bakes the
--- spell it is about into its icon when created, so a category change needs new ones, and frames cannot
--- be destroyed -- building a set per switch would strand one per click of the strip.
---@param page Frame
---@param displayKey SpotlightsAuraDisplayKey? every kind the category draws, when omitted
---@param options { heading: string?, CaptionText: (string | fun(): string)?, stageHeight: number? }?
---@return SpotlightsPreviewPaneNode
local function BuildPreview(page, displayKey, options)
	-- Read here rather than at file scope: this file is loaded before the player exists, and the panel
	-- is not built until a tab is first selected.
	local _, class = UnitClass("player")

	local pane = Private.PreviewPane.Build(page, {
		class = class,
		heading = options and options.heading,
		CaptionText = options and options.CaptionText,
		stageHeight = options and options.stageHeight,
	})

	local Refresh = pane.Refresh

	---@type table<SpotlightsAuraFeatureKey, SpotlightsAuraPreview[]>
	local built = {}

	---@type SpotlightsAuraPreview[]?
	local shown

	function pane:Refresh()
		-- The mini spotlight first: it is scaled to fit this pane, and the display below hangs off it, so
		-- anchoring before would place the aura against the scale being replaced.
		Refresh(self)

		local featureKey = ActiveFeature()
		local set = built[featureKey]

		-- Tested for emptiness, not nil: `CreatePreviews` answers `{}` while the database is not yet
		-- readable, and an empty table is truthy -- so a first refresh before then would cache nothing
		-- forever.
		if not set or #set == 0 then
			set = Private.Auras.CreatePreviews(self.frame, featureKey, displayKey)
			built[featureKey] = set
		end

		if shown and shown ~= set then
			-- `StylePreviews` is the only thing that shows an anchor again, and it is only ever run on
			-- the selected category's set -- so one hidden here stays hidden until its own comes back.
			for i = 1, #shown do
				shown[i].anchor:Hide()
			end
		end

		shown = set

		Private.Auras.StylePreviews(set)
	end

	panes[#panes + 1] = pane

	return pane
end

--- Restores one display to its shipped values, after asking: a reset discards a layout the user may have
--- spent a while on, and a stray click on the button ending a section is what the confirmation catches.
---@param displayKey SpotlightsAuraDisplayKey
---@param label string the display's own name, which the prompt names beside the category's
local function ConfirmReset(displayKey, label)
	local L = Private.L.Settings

	-- Registered at click time rather than at load: the localisation table is filled by now, and the
	-- category named in the prompt is whichever the strip has selected at the click.
	StaticPopupDialogs[RESET_POPUP] = {
		text = string.format(L.AuraResetDisplayPrompt, label, ActiveName()),
		button1 = L.AuraResetConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Private.Auras.ResetDisplay(ActiveFeature(), displayKey)

			-- The whole tab rather than the summaries alone: every control in the section now shows a
			-- value that has just been replaced.
			Private.Options.Refresh()
			Private.AuraPreview.Restyle()
		end,
	}

	StaticPopup_Show(RESET_POPUP)
end

--- The border sub-heading and its three controls, identical for every display. Not offered on the
--- health-bar tint, which has no rect of its own for an edge to go around.
---@param page Frame
---@param displayKey SpotlightsAuraDisplayKey
---@return SpotlightsNode[]
local function BorderRows(page, displayKey)
	local L = Private.L.Settings

	return {
		Private.Controls.SubHeading(page, L.AuraBorder),

		-- Passed as a function, not its result: the list has to be re-read every time the menu opens, so
		-- a border pack registered after this tab was built is still offered.
		Private.Controls.Dropdown(page, L.AuraBorderStyle, function()
			return Private.Controls.MediaChoices(Private.Media.BorderList(),
				Private.Media.IsBorderRegistered, Display(displayKey).borderTexture)
		end, Getter(displayKey, "borderTexture"), BorderStyleSetter(displayKey)),

		-- Both dim while the style is `None`, which is otherwise only discoverable by picking a colour and
		-- watching nothing happen.
		Private.Controls.Slider(page, L.AuraBorderSize, BORDER_SIZE_MIN, BORDER_SIZE_MAX, 1,
			Getter(displayKey, "borderSize"), Setter(displayKey, "borderSize"), HasBorder(displayKey)),

		Private.Controls.ColorSwatch(page, L.AuraBorderColor,
			ColorGetter(displayKey, "borderR", "borderG", "borderB", "borderA"),
			ColorSetter(displayKey, "borderR", "borderG", "borderB", "borderA"), HasBorder(displayKey)),
	}
end

--- The anchor and the two offsets that refine it, identical for the four displays that have a rect of their
--- own to place, and always the last group in a body.
---@param page Frame
---@param displayKey SpotlightsAuraDisplayKey
---@return SpotlightsNode[]
local function PositioningRows(page, displayKey)
	local L = Private.L.Settings

	return {
		Private.Controls.SubHeading(page, L.GroupPositioning),

		Full(Private.Controls.Dropdown(page, L.AuraAnchor, Private.Controls.AnchorChoices,
			Getter(displayKey, "point"), Setter(displayKey, "point"))),

		-- Sliders rather than the kit's number pair: an offset is dragged against what it moves, and the
		-- pane beside these is what it moves.
		Private.Controls.Slider(page, L.AuraOffsetX, OFFSET_MIN, OFFSET_MAX, 1,
			Getter(displayKey, "x"), Setter(displayKey, "x")),
		Private.Controls.Slider(page, L.AuraOffsetY, OFFSET_MIN, OFFSET_MAX, 1,
			Getter(displayKey, "y"), Setter(displayKey, "y")),
	}
end

--- One section's body: its own groups, then the border group, then positioning, then the reset.
---
--- Two lists rather than one because the shared border group sits *between* what a display alone decides
--- and where it ends up, so a body cannot be one literal with `BorderRows` spliced into it.
---
--- The reset is per display rather than per category, because the displays are configured independently
--- and one button for all of them would discard the parts the user was happy with.
---@param page Frame
---@param rows SpotlightsNode[] everything above the border group
---@param displayKey SpotlightsAuraDisplayKey
---@param label string
---@param trailing SpotlightsNode[][]? the shared groups, `{}` for a display that has neither
---@return SpotlightsNode
local function BuildBody(page, rows, displayKey, label, trailing)
	-- Built here rather than defaulted at the call sites, so a body wanting neither group costs no frames
	-- for controls it will not show.
	trailing = trailing or { BorderRows(page, displayKey), PositioningRows(page, displayKey) }

	for group = 1, #trailing do
		local list = trailing[group]

		for i = 1, #list do
			rows[#rows + 1] = list[i]
		end
	end

	local L = Private.L.Settings

	rows[#rows + 1] = Private.Controls.ActionButton(page, L.AuraReset, function()
		ConfirmReset(displayKey, label)
	end, true)

	-- Under the section's own pane rather than shared at the foot of the tab, so it is beside the offset
	-- slider being dragged rather than off screen at the moment it is wanted.
	--
	-- Hidden at one enabled display, where it would duplicate the pane above it, and with the category
	-- switched off. `OnlyWhen` skips `Refresh` on a hidden node and the lazy build lives inside `Refresh`,
	-- so a category with one display enabled allocates nothing.
	local combined = OnlyWhen(BuildPreview(page, nil, {
		heading = L.AuraCombinedPreviewHeading,
		CaptionText = L.AuraCombinedPreviewCaption,
		stageHeight = COMBINED_STAGE_HEIGHT,
	}), function()
		return Feature().enabled and EnabledDisplayCount() > 1
	end)

	return Private.Node.Split(page, Private.Node.Grid(page, rows, 2, COLUMN_LABEL_WIDTH),
		Private.Node.Column(page, { BuildPreview(page, displayKey), combined }),
		{ rightWidth = Private.PreviewPane.Width })
end

---@param page Frame
---@return SpotlightsNode
local function BuildIconBody(page)
	local L = Private.L.Settings

	return BuildBody(page, {
		Private.Controls.SubHeading(page, L.GroupDisplay),

		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("icon", "enabled"),
			EnabledSetter("icon")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("icon", "alpha"), Setter("icon", "alpha")),

		Private.Controls.SubHeading(page, L.GroupSize),

		Private.Controls.Slider(page, L.AuraIconWidth, ICON_SIZE_MIN, ICON_SIZE_MAX, 1,
			Getter("icon", "width"), Setter("icon", "width")),
		Private.Controls.Slider(page, L.AuraIconHeight, ICON_SIZE_MIN, ICON_SIZE_MAX, 1,
			Getter("icon", "height"), Setter("icon", "height")),

		-- Only a category pooling several icons has anything to space; offered where it does nothing, it
		-- would read as a broken setting. The same holds for the direction below.
		OnlyWhen(Full(Private.Controls.Slider(page, L.AuraGap, GAP_MIN, GAP_MAX, 1,
			Getter("icon", "gap"), Setter("icon", "gap"))), function()
			return Private.Auras.IsPooled(ActiveFeature())
		end),

		OnlyWhen(Full(Private.Controls.Dropdown(page, L.AuraGrowDirection, {
			{ value = GrowDirection.Right, label = L.GrowRight },
			{ value = GrowDirection.Left,  label = L.GrowLeft },
			{ value = GrowDirection.Down,  label = L.GrowDown },
			{ value = GrowDirection.Up,    label = L.GrowUp },
		}, Getter("icon", "growDirection"), Setter("icon", "growDirection"))), function()
			return Private.Auras.IsPooled(ActiveFeature())
		end),

		Private.Controls.SubHeading(page, L.GroupCooldown),

		Private.Controls.Checkbox(page, L.AuraShowSwipe, Getter("icon", "showSwipe"),
			Setter("icon", "showSwipe")),
		Private.Controls.Checkbox(page, L.AuraShowText, Getter("icon", "showText"),
			Setter("icon", "showText")),

		Private.Controls.Dropdown(page, L.AuraFont, function()
			return Private.Controls.MediaChoices(Private.Media.FontList(),
				Private.Media.IsFontRegistered, Icon().font)
		end, Getter("icon", "font"), Setter("icon", "font")),
		Private.Controls.Slider(page, L.AuraFontSize, FONT_SIZE_MIN, FONT_SIZE_MAX, 1,
			Getter("icon", "fontSize"), Setter("icon", "fontSize")),
	}, "icon", L.AuraIcon)
end

---@param page Frame
---@return SpotlightsNode
local function BuildBarBody(page)
	local L = Private.L.Settings

	return BuildBody(page, {
		Private.Controls.SubHeading(page, L.GroupDisplay),

		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("bar", "enabled"),
			EnabledSetter("bar")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("bar", "alpha"), Setter("bar", "alpha")),

		Private.Controls.SubHeading(page, L.GroupBar),

		Private.Controls.Dropdown(page, L.BarTexture, function()
			return Private.Controls.MediaChoices(Private.Media.StatusBarList(),
				Private.Media.IsRegistered, Bar().texture)
		end, Getter("bar", "texture"), Setter("bar", "texture")),

		-- Beside the texture rather than with the width and height, though it decides what those two mean:
		-- it is a property of the fill, and the size group is a pair of sliders dragged against the pane.
		Private.Controls.Dropdown(page, L.Orientation, {
			{ value = Orientation.Horizontal, label = L.AuraFillHorizontal },
			{ value = Orientation.Vertical,   label = L.AuraFillVertical },
		}, Getter("bar", "orientation"), OrientationSetter),

		-- A function rather than a table: the labels are the ends of whichever axis is set, and a list
		-- built once would keep offering "Left To Right" for a bar that now runs down.
		Private.Controls.Dropdown(page, L.AuraFillDirection, function()
			if Bar().orientation == Orientation.Vertical then
				return {
					{ value = false, label = L.AuraFillBottomToTop },
					{ value = true,  label = L.AuraFillTopToBottom },
				}
			end

			return {
				{ value = false, label = L.AuraFillLeftToRight },
				{ value = true,  label = L.AuraFillRightToLeft },
			}
		end, Getter("bar", "reverseFill"), Setter("bar", "reverseFill")),

		-- The picker's own opacity writes `alpha`, which is the slider above it: one field with two
		-- controls over it, as on every other display here. The slider re-reads on the next full refresh.
		Private.Controls.ColorSwatch(page, L.AuraColor, ColorGetter("bar", "r", "g", "b", "alpha"),
			ColorSetter("bar", "r", "g", "b", "alpha")),

		Private.Controls.SubHeading(page, L.GroupSize),

		Private.Controls.Slider(page, L.AuraWidth, BAR_WIDTH_MIN, BAR_WIDTH_MAX, 1,
			Getter("bar", "width"), Setter("bar", "width")),
		Private.Controls.Slider(page, L.AuraHeight, BAR_HEIGHT_MIN, BAR_HEIGHT_MAX, 1,
			Getter("bar", "height"), Setter("bar", "height")),

		Private.Controls.SubHeading(page, L.GroupIcon),

		Private.Controls.Checkbox(page, L.AuraShowIcon, Getter("bar", "showIcon"),
			Setter("bar", "showIcon")),

		-- A function for the fill direction's reason: the labels are the *ends of the bar*, so a list built
		-- once would keep offering "Left Of The Bar" for the top of a vertical one. The stored
		-- `LEFT`/`RIGHT` is what reaches the database either way.
		Private.Controls.Dropdown(page, L.AuraIconSide, function()
			if Bar().orientation == Orientation.Vertical then
				return {
					{ value = "LEFT",  label = L.AuraIconTop },
					{ value = "RIGHT", label = L.AuraIconBottom },
				}
			end

			return {
				{ value = "LEFT",  label = L.AuraIconLeft },
				{ value = "RIGHT", label = L.AuraIconRight },
			}
		end, Getter("bar", "iconSide"), Setter("bar", "iconSide")),
	}, "bar", L.AuraBar)
end

---@param page Frame
---@return SpotlightsNode
local function BuildSquareBody(page)
	local L = Private.L.Settings

	-- `Block` rather than `Size`, because one field drives both axes and the colour belongs beside it:
	-- colour is what tells two squares apart.
	return BuildBody(page, {
		Private.Controls.SubHeading(page, L.GroupDisplay),

		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("square", "enabled"),
			EnabledSetter("square")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("square", "alpha"), Setter("square", "alpha")),

		Private.Controls.SubHeading(page, L.GroupBlock),

		-- Paired with the colour rather than given a row of its own, so the rows below stay in the
		-- two-column rhythm the icon and the bar have.
		Private.Controls.Slider(page, L.AuraSquareSize, SQUARE_SIZE_MIN, SQUARE_SIZE_MAX, 1,
			Getter("square", "size"), Setter("square", "size")),

		Private.Controls.ColorSwatch(page, L.AuraSquareColor,
			ColorGetter("square", "r", "g", "b", "alpha"),
			ColorSetter("square", "r", "g", "b", "alpha")),

		Private.Controls.SubHeading(page, L.GroupCooldown),

		Private.Controls.Checkbox(page, L.AuraShowSwipe, Getter("square", "showSwipe"),
			Setter("square", "showSwipe")),
		Private.Controls.Checkbox(page, L.AuraShowText, Getter("square", "showText"),
			Setter("square", "showText")),

		Private.Controls.Dropdown(page, L.AuraFont, function()
			return Private.Controls.MediaChoices(Private.Media.FontList(),
				Private.Media.IsFontRegistered, Square().font)
		end, Getter("square", "font"), Setter("square", "font")),
		Private.Controls.Slider(page, L.AuraFontSize, FONT_SIZE_MIN, FONT_SIZE_MAX, 1,
			Getter("square", "fontSize"), Setter("square", "fontSize")),
	}, "square", L.AuraSquare)
end

---@param page Frame
---@return SpotlightsNode
local function BuildTextBody(page)
	local L = Private.L.Settings

	-- The shortest body with a rect of its own: no size group, since the rect follows the font size, and
	-- no cooldown group, since the countdown *is* the display. So the labels drop the `Duration` the other
	-- sections need to say which of their parts is being styled.
	return BuildBody(page, {
		Private.Controls.SubHeading(page, L.GroupDisplay),

		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("text", "enabled"),
			EnabledSetter("text")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("text", "alpha"), Setter("text", "alpha")),

		Private.Controls.SubHeading(page, L.GroupText),

		Private.Controls.Dropdown(page, L.AuraTextFont, function()
			return Private.Controls.MediaChoices(Private.Media.FontList(),
				Private.Media.IsFontRegistered, Text().font)
		end, Getter("text", "font"), Setter("text", "font")),

		-- Sets the display's rect as well as its glyphs, since `Size` derives one from the other, so this
		-- is the slider that moves the anchor the positioning group below places.
		Private.Controls.Slider(page, L.AuraTextFontSize, FONT_SIZE_MIN, FONT_SIZE_MAX, 1,
			Getter("text", "fontSize"), Setter("text", "fontSize")),

		Private.Controls.ColorSwatch(page, L.AuraTextColor, ColorGetter("text", "r", "g", "b", "alpha"),
			ColorSetter("text", "r", "g", "b", "alpha")),
	}, "text", L.AuraText)
end

---@param page Frame
---@return SpotlightsNode
local function BuildFrameColorBody(page)
	local L = Private.L.Settings

	-- The only body with neither the border nor the positioning group: this display's rect is the
	-- spotlight's health bar, so there is no edge to draw and no offset to place. The opacity is the
	-- control that matters -- at 1 the chosen colour replaces the class colour outright.
	return BuildBody(page, {
		Private.Controls.SubHeading(page, L.GroupDisplay),

		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("frameColor", "enabled"),
			EnabledSetter("frameColor")),

		Private.Controls.ColorSwatch(page, L.AuraFrameColorColor,
			ColorGetter("frameColor", "r", "g", "b", "alpha"),
			ColorSetter("frameColor", "r", "g", "b", "alpha")),

		Full(Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("frameColor", "alpha"), Setter("frameColor", "alpha"))),

		Private.Controls.Paragraph(page, L.AuraFrameColorNote),
	}, "frameColor", L.AuraFrameColor, {})
end

--- Opens the sections whose display is switched on and collapses the rest. The open state is transient
--- and stays that way: remembering it would persist something the user changes by looking at the panel.
---
--- **Initial, not forced.** The enable checkbox is the first row *inside* each body, so a section held
--- collapsed while its display is off would be a display that can never be switched back on. Called only
--- from the two moments a visit to a category begins, never from a write.
---
--- Not `startOpen`: `Build` runs once per session, before `RefreshCategories` picks the selected
--- category, so a constructor argument would answer for whichever category the file was loaded pointing
--- at.
---
--- Must run *before* the `Refresh` that follows it: `SetOpen` relayouts when the state changes, and a
--- relayout from under a pass in progress is what `Refresh`-before-`Layout` exists to prevent.
function Private.AuraAppearance.SyncSections()
	for i = 1, #sections do
		sections[i]:SetOpen(Display(SECTION_DISPLAY_KEYS[i]).enabled)
	end
end

--- The sub-tab.
---@param page Frame
---@param GetFeature fun(): SpotlightsAuraFeatureKey which category the strip has selected
---@param GetName fun(): string its localised name, for the reset prompt
---@return SpotlightsNode
function Private.AuraAppearance.Build(page, GetFeature, GetName)
	local L = Private.L.Settings

	ActiveFeature = GetFeature
	ActiveName = GetName
	panes = {}

	local icon = Private.Node.Section(page, function()
		return L.AuraIcon
	end, IconSummary, BuildIconBody(page))

	local bar = Private.Node.Section(page, function()
		return L.AuraBar
	end, BarSummary, BuildBarBody(page))

	local square = Private.Node.Section(page, function()
		return L.AuraSquare
	end, SquareSummary, BuildSquareBody(page))

	local text = Private.Node.Section(page, function()
		return L.AuraText
	end, TextSummary, BuildTextBody(page))

	local frameColor = Private.Node.Section(page, function()
		return L.AuraFrameColor
	end, FrameColorSummary, BuildFrameColorBody(page))

	-- A pooled category draws icons only, so the other four have no section. Asked of `Private.Auras`
	-- rather than decided here: a second copy of the build path's rule could only be wrong.
	OnlyWhen(bar, function()
		return Private.Auras.HasDisplay(ActiveFeature(), "bar")
	end)

	OnlyWhen(square, function()
		return Private.Auras.HasDisplay(ActiveFeature(), "square")
	end)

	OnlyWhen(text, function()
		return Private.Auras.HasDisplay(ActiveFeature(), "text")
	end)

	OnlyWhen(frameColor, function()
		return Private.Auras.HasDisplay(ActiveFeature(), "frameColor")
	end)

	sections = { icon, bar, square, text, frameColor }

	local scrollHeight = math.max(page:GetHeight() - Private.Node.SubTabHeight - CHROME_RESERVE,
		MIN_SCROLL_HEIGHT)

	return Private.Node.ScrollPane(page, Private.Node.Column(page, {
		icon,
		bar,
		square,
		text,
		frameColor,

		-- Last, and the explanation of everything above it: the one place the cost of a frozen setting
		-- is visible to the user.
		Private.Controls.Paragraph(page, L.AurasRebuildHelp),
	}, SECTION_GAP), scrollHeight)
end
