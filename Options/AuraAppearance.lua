---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraAppearance
Private.AuraAppearance = {}

--- The Auras tab's Appearance sub-tab: one collapsible section per kind of display the selected
--- category can draw, scrolling under a pinned reset button.
---
--- An aura feature has three independent display modes, each with its own size, placement, swipe, border
--- and colour. Flat, that is a wall of three dozen controls with nothing saying which mode is actually on
--- or what it is set to. A section answers both in its header: the display's name, and a summary
--- formatted from the very fields its body edits -- `25 × 25 · Bottom · swipe on · 4px border`.
---
--- Which category all of this is about lives in `Options/Auras.lua`, on the strip along the bottom of
--- the window, and reaches this file as an accessor rather than a copy: the Tracked sub-tab beside this
--- one is about the same category, and neither of them owns it.
---
--- Every setting here was on the old panel's Auras tab and writes the same field. What is new is the
--- shape, the per-section preview, and the summary.

--- What the label column costs in the ~250px half of a section's control grid. Narrower than the
--- Appearance tab's 120 because these labels are one or two short words where that tab's are noun
--- phrases, and the sliders here are the ones dragged against a preview -- so the bar is worth the room.
local COLUMN_LABEL_WIDTH = 110

--- Between one section and the next. Wider than the kit's row rhythm on purpose: sections are groups
--- rather than rows, and at the column default a body's last control sits as close to the next header as
--- to its own siblings.
local SECTION_GAP = 12

--- LibSharedMedia's own name for the empty border, and therefore how "no border" is spelled. Restated
--- here rather than reached for across a module boundary, so the summary tests exactly what `StyleBorder`
--- tests and the two can never disagree about whether a border is drawn.
local BORDER_NONE = "None"

--- The bounds of every numeric setting, as the old panel already sets them.
local ICON_SIZE_MIN, ICON_SIZE_MAX = 16, 128

-- Reaches below the icon's floor deliberately: a block is the display for a size where spell art cannot
-- be read, so its range has to cover sizes an icon has no business being.
local SQUARE_SIZE_MIN, SQUARE_SIZE_MAX = 4, 128
local BAR_WIDTH_MIN, BAR_WIDTH_MAX = 1, 500
local BAR_HEIGHT_MIN, BAR_HEIGHT_MAX = 1, 200
local GAP_MIN, GAP_MAX = 0, 40
local FONT_SIZE_MIN, FONT_SIZE_MAX = 6, 32
local BORDER_SIZE_MIN, BORDER_SIZE_MAX = 1, 32
local OFFSET_MIN, OFFSET_MAX = -200, 200

--- Never fully transparent, for the same reason a spotlight is not: a display at zero opacity is
--- indistinguishable from one that failed to build. The step is what the value box shows, two decimals
--- -- see `Controls`' `FRACTION_STEP`.
local ALPHA_MIN, ALPHA_MAX, ALPHA_STEP = 0.05, 1, 0.01

--- What this sub-tab's chrome costs its own height: the gap under the Auras tab's sub-tab strip. The
--- scroll pane gets everything else, so it fills the tab rather than a guess at how tall two sections
--- "usually" are.
local CHROME_RESERVE = 6

--- Floor for the scroll pane, in case the window is ever shorter than this tab's chrome costs -- better
--- a cramped pane than a negative height Blizzard errors on.
local MIN_SCROLL_HEIGHT = 80

--- Shared with the Tracked sub-tab deliberately, exactly as the reload prompt is: the dialog is
--- registered at click time by whichever button was clicked, and two keys would stack two identical
--- prompts.
local RESET_POPUP = "SPOTLIGHTS_AURA_RESET"

--- Which category the strip has selected, and its localised name for the reset prompt. Both handed in by
--- `Build`, because the strip they come from is not this file's.
---@type fun(): SpotlightsAuraFeatureKey
local ActiveFeature

---@type fun(): string
local ActiveName

--- The two parts of this tab that mirror settings rather than edit them, kept so a write can repaint
--- them without re-reading the controls it came from.
---@type SpotlightsSectionNode[]
local sections = {}

---@type SpotlightsPreviewPaneNode[]
local panes = {}

---@return SpotlightsAuraFeatureConfig
local function Feature()
	local auras = Private.DB and Private.DB.auras
	local feature = auras and auras[ActiveFeature()]

	-- The defaults stand in only before `ADDON_LOADED`, when the panel cannot be open. Falling back to
	-- them rather than to a literal per field means a control can never show a number this addon does
	-- not ship with, and `Migration` repairs every missing field on load -- so past this point every
	-- field read below is present.
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

	return Icon()
end

--- Repaints what shows a setting without re-reading what sets it: the section headers, whose summaries
--- are a formatting of the fields just written, and the preview pane inside each body.
---
--- Deliberately not `Options.Refresh`. A colour picker fires on every frame of a drag, and a whole-tree
--- refresh would regenerate every dropdown's menu with it -- while nothing written from a control can
--- change what is shown or how tall anything is, so there is nothing to lay out either.
local function RefreshSections()
	for i = 1, #sections do
		sections[i]:RefreshHeader()
	end

	for i = 1, #panes do
		panes[i]:Refresh()
	end
end

--- Writes one aura setting through the one entry point that knows what it costs.
---
--- Requests nothing itself, unlike the appearance tab's setter: `Private.Auras` asks the display kind
--- whether the field is a next-frame reapply or a debounced rebuild, and that decision has to live with
--- the frames -- a settings file that knew which fields are frozen would be a second copy of a list that
--- can only be wrong.
---@param displayKey SpotlightsAuraDisplayKey
---@param field string
---@param value any
local function SetAura(displayKey, field, value)
	Private.Auras.SetSetting(ActiveFeature(), displayKey, field, value)

	-- The grid previews are where a drag's feedback comes from: half of these settings reach a live
	-- display only after a debounce and a rebuild, and all of them reach a preview now.
	Private.AuraPreview.Restyle()
	RefreshSections()
end

--- Reads one display field. A factory rather than a function per setting: every field on this tab is
--- read the same way, and a hand-written pair each would restate that two dozen times.
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

--- Writes the border style and re-reads the whole tab.
---
--- `None` is how "no border" is spelled, and the thickness and colour beside it gate on that but only
--- sample it in their own `Refresh` -- so the plain setter would leave a just-disabled swatch looking
--- clickable. No relayout is owed: a disabled control dims rather than hides, so nothing moves.
---@param displayKey SpotlightsAuraDisplayKey
---@return fun(value: any)
local function BorderStyleSetter(displayKey)
	return function(value)
		SetAura(displayKey, "borderTexture", value)
		Private.Options.Refresh()
	end
end

--- Reads a colour stored as four separately named fields.
---
--- Named rather than derived from a prefix: a bar's own colour is `r`/`g`/`b`/`alpha` while its border's
--- is `borderR`..`borderA`, and one spelling rule cannot cover both.
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

--- Writes all four channels, then repaints once.
---
--- Four writes rather than one costs nothing extra: each may queue a rebuild, but all four name the same
--- display, so they collapse into one entry and one timer. The *repaint* is what must not be repeated --
--- a colour picker fires continuously while dragged, and a sweep per channel would restyle every preview
--- four times for one visual change.
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

--- The header line for a display that is switched off, for both summaries.
---
--- A size and an anchor for something nothing will draw is worse than no summary at all: the whole point
--- of the header is answering "is this mode on" without expanding it.
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

---@return string
local function BarSummary()
	local L = Private.L.Settings
	local config = Bar()

	return HiddenSummary(config) or string.format(L.AuraSummary, config.width, config.height,
		AnchorName(config), config.showIcon and L.AuraSummaryInlineIcon or L.AuraSummaryNoInlineIcon,
		BorderPhrase(config))
end

--- The square's summary, in the same five fields as the other two: its size twice over, since one field
--- drives both axes, and the swipe as the option that most changes how it reads -- a block with no swipe
--- and no text says only that something is up.
---@return string
local function SquareSummary()
	local L = Private.L.Settings
	local config = Square()

	return HiddenSummary(config) or string.format(L.AuraSummary, config.size, config.size,
		AnchorName(config), config.showSwipe and L.AuraSummarySwipeOn or L.AuraSummarySwipeOff,
		BorderPhrase(config))
end

local OnlyWhen = Private.Node.OnlyWhen

--- Gives a control a row of its own, closing whatever row was being filled.
---
--- `span` is the grid's own field; this is only what lets it be set on a control built inside a list. Two
--- controls here want it: the gap slider, which one kind of category does not have at all, and the anchor
--- dropdown above the two offsets that refine it. Both keep the pairs around them from re-flowing when a
--- category changes which controls exist.
---@param node SpotlightsNode
---@return SpotlightsNode
local function Full(node)
	node.span = true

	return node
end

--- The pane beside one section's controls: the Appearance tab's mini spotlight, with that section's
--- display -- and only that one -- hung off it.
---
--- Records are built per category and kept rather than rebuilt on every switch. A preview bakes the spell
--- it is about into its icon when it is created, so a category change needs new ones; frames cannot be
--- destroyed, so building a set per switch would strand one per click of the strip. Five categories is
--- the whole of what can ever be kept.
---@param page Frame
---@param displayKey SpotlightsAuraDisplayKey
---@return SpotlightsPreviewPaneNode
local function BuildPreview(page, displayKey)
	local pane = Private.PreviewPane.Build(page)
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

		if not set then
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

--- Restores one display to its shipped values, after asking.
---
--- Confirmed rather than immediate: a reset discards a layout the user may have spent a while on, and a
--- stray click on the button ending a section is the accident a confirmation exists to catch.
---@param displayKey SpotlightsAuraDisplayKey
---@param label string the display's own name, which the prompt names beside the category's
local function ConfirmReset(displayKey, label)
	local L = Private.L.Settings

	-- Registered at click time rather than at load: the localisation table is filled by now, and the
	-- category named in the prompt is whichever the strip has selected at the click rather than whichever
	-- it had when this tab was built.
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

--- The border sub-heading and its three controls, identical for both displays.
---
--- A border is the one piece of styling that does not care whether it is around a bar or an icon, so
--- writing these twice would duplicate the same thing.
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

		-- Both dim while the style is `None`, because both are then settings for something that is not
		-- drawn -- which is otherwise only discoverable by picking a colour and watching nothing happen.
		Private.Controls.Slider(page, L.AuraBorderSize, BORDER_SIZE_MIN, BORDER_SIZE_MAX, 1,
			Getter(displayKey, "borderSize"), Setter(displayKey, "borderSize"), HasBorder(displayKey)),

		Private.Controls.ColorSwatch(page, L.AuraBorderColor,
			ColorGetter(displayKey, "borderR", "borderG", "borderB", "borderA"),
			ColorSetter(displayKey, "borderR", "borderG", "borderB", "borderA"), HasBorder(displayKey)),
	}
end

--- One section's body: its own controls, then the border group, then the reset that belongs to it.
---
--- The reset is per display rather than one for the category, because the two displays are configured
--- independently and one button for both would discard the half the user was happy with. Inside the
--- grid, so it ends the controls it resets rather than floating under the pane beside them.
---@param page Frame
---@param rows SpotlightsNode[]
---@param displayKey SpotlightsAuraDisplayKey
---@param label string
---@return SpotlightsNode
local function BuildBody(page, rows, displayKey, label)
	local border = BorderRows(page, displayKey)

	for i = 1, #border do
		rows[#rows + 1] = border[i]
	end

	rows[#rows + 1] = Private.Controls.ActionButton(page, Private.L.Settings.AuraReset, function()
		ConfirmReset(displayKey, label)
	end, true)

	return Private.Node.Split(page, Private.Node.Grid(page, rows, 2, COLUMN_LABEL_WIDTH),
		BuildPreview(page, displayKey), { rightWidth = Private.PreviewPane.Width })
end

---@param page Frame
---@return SpotlightsNode
local function BuildIconBody(page)
	local L = Private.L.Settings

	return BuildBody(page, {
		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("icon", "enabled"),
			Setter("icon", "enabled")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("icon", "alpha"), Setter("icon", "alpha")),

		Private.Controls.Slider(page, L.AuraIconWidth, ICON_SIZE_MIN, ICON_SIZE_MAX, 1,
			Getter("icon", "width"), Setter("icon", "width")),
		Private.Controls.Slider(page, L.AuraIconHeight, ICON_SIZE_MIN, ICON_SIZE_MAX, 1,
			Getter("icon", "height"), Setter("icon", "height")),

		--- The spacing between icons, so only a category that pools several of them has anything to
		--- space. Offered where it does nothing, it would read as a setting that is broken.
		OnlyWhen(Full(Private.Controls.Slider(page, L.AuraGap, GAP_MIN, GAP_MAX, 1,
			Getter("icon", "gap"), Setter("icon", "gap"))), function()
			return Private.Auras.IsPooled(ActiveFeature())
		end),

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

		Full(Private.Controls.Dropdown(page, L.AuraAnchor, Private.Controls.AnchorChoices,
			Getter("icon", "point"), Setter("icon", "point"))),

		-- Sliders rather than the kit's number pair: an offset is dragged against what it moves, and the
		-- pane beside these is what it moves.
		Private.Controls.Slider(page, L.AuraOffsetX, OFFSET_MIN, OFFSET_MAX, 1, Getter("icon", "x"),
			Setter("icon", "x")),
		Private.Controls.Slider(page, L.AuraOffsetY, OFFSET_MIN, OFFSET_MAX, 1, Getter("icon", "y"),
			Setter("icon", "y")),
	}, "icon", L.AuraIcon)
end

---@param page Frame
---@return SpotlightsNode
local function BuildBarBody(page)
	local L = Private.L.Settings

	return BuildBody(page, {
		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("bar", "enabled"),
			Setter("bar", "enabled")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("bar", "alpha"), Setter("bar", "alpha")),

		Private.Controls.Dropdown(page, L.BarTexture, function()
			return Private.Controls.MediaChoices(Private.Media.StatusBarList(),
				Private.Media.IsRegistered, Bar().texture)
		end, Getter("bar", "texture"), Setter("bar", "texture")),

		--- The picker's own opacity writes `alpha`, which is the slider above it -- one field with two
		--- controls over it, as the old panel also has. The slider re-reads on the next full refresh.
		Private.Controls.ColorSwatch(page, L.AuraColor, ColorGetter("bar", "r", "g", "b", "alpha"),
			ColorSetter("bar", "r", "g", "b", "alpha")),

		Private.Controls.Slider(page, L.AuraWidth, BAR_WIDTH_MIN, BAR_WIDTH_MAX, 1,
			Getter("bar", "width"), Setter("bar", "width")),
		Private.Controls.Slider(page, L.AuraHeight, BAR_HEIGHT_MIN, BAR_HEIGHT_MAX, 1,
			Getter("bar", "height"), Setter("bar", "height")),

		Private.Controls.Checkbox(page, L.AuraShowIcon, Getter("bar", "showIcon"),
			Setter("bar", "showIcon")),
		Private.Controls.Dropdown(page, L.AuraIconSide, {
			{ value = "LEFT",  label = L.AuraIconLeft },
			{ value = "RIGHT", label = L.AuraIconRight },
		}, Getter("bar", "iconSide"), Setter("bar", "iconSide")),

		Full(Private.Controls.Dropdown(page, L.AuraAnchor, Private.Controls.AnchorChoices,
			Getter("bar", "point"), Setter("bar", "point"))),

		Private.Controls.Slider(page, L.AuraOffsetX, OFFSET_MIN, OFFSET_MAX, 1, Getter("bar", "x"),
			Setter("bar", "x")),
		Private.Controls.Slider(page, L.AuraOffsetY, OFFSET_MIN, OFFSET_MAX, 1, Getter("bar", "y"),
			Setter("bar", "y")),
	}, "bar", L.AuraBar)
end

---@param page Frame
---@return SpotlightsNode
local function BuildSquareBody(page)
	local L = Private.L.Settings

	return BuildBody(page, {
		Private.Controls.Checkbox(page, L.AuraEnabled, Getter("square", "enabled"),
			Setter("square", "enabled")),
		Private.Controls.Slider(page, L.AuraAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("square", "alpha"), Setter("square", "alpha")),

		--- One slider where the other sections have two, because one field drives both axes -- and paired
		--- with the colour rather than given a row of its own, so the rows below it stay in the two-column
		--- rhythm the icon and the bar have.
		Private.Controls.Slider(page, L.AuraSquareSize, SQUARE_SIZE_MIN, SQUARE_SIZE_MAX, 1,
			Getter("square", "size"), Setter("square", "size")),

		--- The picker's own opacity writes `alpha`, which is the slider above it -- the same one field with
		--- two controls over it the bar's colour has.
		Private.Controls.ColorSwatch(page, L.AuraSquareColor,
			ColorGetter("square", "r", "g", "b", "alpha"),
			ColorSetter("square", "r", "g", "b", "alpha")),

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

		Full(Private.Controls.Dropdown(page, L.AuraAnchor, Private.Controls.AnchorChoices,
			Getter("square", "point"), Setter("square", "point"))),

		Private.Controls.Slider(page, L.AuraOffsetX, OFFSET_MIN, OFFSET_MAX, 1, Getter("square", "x"),
			Setter("square", "x")),
		Private.Controls.Slider(page, L.AuraOffsetY, OFFSET_MIN, OFFSET_MAX, 1, Getter("square", "y"),
			Setter("square", "y")),
	}, "square", L.AuraSquare)
end

--- Collapses nothing and expands everything: the open state is transient, and this is what makes it so.
---
--- Called when the tab goes off screen rather than tracked as a setting. Persisting it would mean a
--- saved-variable field per section and a migration, to remember something the user changes by looking at
--- the panel.
function Private.AuraAppearance.ResetSections()
	for i = 1, #sections do
		sections[i]:SetOpen(true)
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

	--- A pooled category draws icons only, so there is neither a status bar nor a square to configure and
	--- no section for either. Asked of `Private.Auras` rather than decided here: which display kinds a
	--- category renders is the build path's rule, and a second copy of it could only be wrong.
	OnlyWhen(bar, function()
		return Private.Auras.HasDisplay(ActiveFeature(), "bar")
	end)

	OnlyWhen(square, function()
		return Private.Auras.HasDisplay(ActiveFeature(), "square")
	end)

	sections = { icon, bar, square }

	local scrollHeight = math.max(page:GetHeight() - Private.Node.SubTabHeight - CHROME_RESERVE,
		MIN_SCROLL_HEIGHT)

	return Private.Node.ScrollPane(page, Private.Node.Column(page, {
		icon,
		bar,
		square,

		-- Last, and the explanation of everything above it: the one place the cost of a frozen setting
		-- is visible to the user.
		Private.Controls.Paragraph(page, L.AurasRebuildHelp),
	}, SECTION_GAP), scrollHeight)
end
