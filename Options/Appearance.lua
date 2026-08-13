---@type string, Spotlights
local _, Private = ...

--- The Appearance tab: what a spotlight looks like, under a *Frame / Name / Health* sub-tab strip
--- with a preview pane beside whichever sub-tab is open.
---
--- Three pages rather than one column, because this is the largest settings group in the addon and its
--- three parts are edited one at a time -- nobody adjusts a font size and a bar texture in the same
--- sitting. The strip runs the full content width and the pane sits beside the pages rather than inside
--- each one, so switching sub-tabs moves the controls and leaves the preview where it was.
---
--- One writer per *kind* of write rather than a closure per control -- see the getter and setter
--- factories below -- because two dozen fields are read and written identically and only a handful
--- need anything more than the plain pair.

--- What the label column costs in a ~260px half of the left pane. Wider than General's 100 because
--- these labels are noun phrases -- `Out Of Range Alpha`, `Static Health Color` -- where that tab's
--- are single words, and a clipped label here would lose which of three colours a swatch is.
local COLUMN_LABEL_WIDTH = 120

local FRAME_WIDTH_MIN, FRAME_WIDTH_MAX = 40, 300
local FRAME_HEIGHT_MIN, FRAME_HEIGHT_MAX = 20, 200

--- Never fully transparent: a spotlight at zero opacity is indistinguishable from a bug, and the
--- floor is where one is still visible enough to be found and turned back up.
---
--- The step is what the value box shows, two decimals -- see `Controls`' `FRACTION_STEP`.
local ALPHA_MIN, ALPHA_MAX, ALPHA_STEP = 0.1, 1, 0.01

local FONT_SIZE_MIN, FONT_SIZE_MAX = 6, 32
local OFFSET_MIN, OFFSET_MAX = -100, 100

--- The pane, kept here so a setting can repaint it.
---
--- It is a sibling of the controls rather than one of their children, so nothing a control's own
--- `Refresh` reaches would ever redraw it -- the same problem the Grid tab's fill-order pane has, and
--- solved one step cheaper: that pane reads settings the controls beside it write, so a full
--- `Options.Refresh` is the honest answer there, while here only the preview has to be told.
---@type SpotlightsPreviewPaneNode?
local previewPane

---@return SpotlightsAppearanceConfig
local function Appearance()
	-- The defaults stand in only before `ADDON_LOADED`, when the panel cannot be open. Falling back to
	-- them rather than to a literal per field means a control can never read a number this addon does
	-- not actually ship with, and `Migration` repairs every missing field on load -- so past this
	-- point every field below is present.
	return Private.DB and Private.DB.appearance or Private.Migration.DefaultAppearance()
end

---@return SpotlightsLayoutConfig
local function Layout()
	return Private.Layout.GetConfig() or Private.Migration.DefaultLayout()
end

--- Brings every spotlight and every preview in line with the current appearance block.
---
--- One sweep, whichever field changed. Most appearance writes touch only one region, but a sweep of
--- the four updaters is cheap -- they re-read settings and repaint our own frames, no protected call
--- -- and a table mapping field to updater would duplicate knowledge the updaters already hold.
--- `UpdateTexture` ends in `UpdateHealthColor`, so the health colour rides along with it.
local function ApplyAppearance()
	Private.SlotHeader.ForEachChild(function(child)
		child:UpdateTexture()
		child:UpdateNameStyle()
		child:UpdateHealthText()
		child:UpdateRangeAlpha()
	end)

	-- Previews are not header children, so `ForEachChild` does not reach them -- and while the mover
	-- is unlocked they are the only thing on screen out of a raid.
	Private.Preview.Restyle()
end

--- Repaints the pane alone. Nothing here changes what any control reads or how tall anything is, so
--- this is deliberately not `Options.Refresh`: a colour picker fires this on every frame of a drag,
--- and a whole-tree refresh would regenerate every dropdown's menu with it.
local function RefreshPreview()
	if previewPane then
		previewPane:Refresh()
	end
end

--- Reads one appearance field. A factory rather than a function per setting: every field on this tab
--- is read the same way, and a hand-written pair each would restate that two dozen times.
---@param field string
---@return fun(): any
local function Getter(field)
	return function()
		return Appearance()[field]
	end
end

--- Writes one appearance field, then repaints whatever shows it.
---
--- Reaches for the database directly rather than through `Appearance` above, and refuses when there is
--- none: that fallback builds a *fresh* default table, so writing into it would be a setting the user
--- watched take effect and then lose.
---@param field string
---@return fun(value: any)
local function Setter(field)
	return function(value)
		local appearance = Private.DB and Private.DB.appearance

		if not appearance then
			return
		end

		appearance[field] = value

		ApplyAppearance()
		RefreshPreview()
	end
end

--- Reads a colour stored as four numbered fields.
---
--- `<prefix>R/G/B/A` is how every colour in the appearance block is spelled -- fields rather than a
--- colour object, so a database written by one build reads on another without a metatable in the way.
---@param prefix string
---@return fun(): number, number, number, number
local function ColorGetter(prefix)
	return function()
		local appearance = Appearance()

		return appearance[prefix .. "R"], appearance[prefix .. "G"], appearance[prefix .. "B"],
			appearance[prefix .. "A"]
	end
end

--- Writes all four channels, then applies once.
---
--- A colour picker fires continuously while dragged, and four single-field writes per frame would
--- sweep the whole grid four times for one visual change.
---@param prefix string
---@return fun(r: number, g: number, b: number, a: number)
local function ColorSetter(prefix)
	return function(r, g, b, a)
		local appearance = Private.DB and Private.DB.appearance

		if not appearance then
			return
		end

		appearance[prefix .. "R"] = r
		appearance[prefix .. "G"] = g
		appearance[prefix .. "B"] = b
		appearance[prefix .. "A"] = a

		ApplyAppearance()
		RefreshPreview()
	end
end

--- Writes a field another control's enablement is gated on, and refreshes the whole tab.
---
--- The gated control samples that value only in its own `Refresh`, so the plain setter would repaint the
--- frames and leave a just-disabled swatch looking clickable, or a hover-only toggle offering a setting
--- for a region that is not drawn. No relayout: a disabled control dims rather than hides, so nothing
--- moves.
---@param field string
---@return fun(value: any)
local function GatingSetter(field)
	local Set = Setter(field)

	return function(value)
		Set(value)
		Private.Options.Refresh()
	end
end

--- Writes the name strata, which is the one field on this tab the appearance sweep cannot carry.
---
--- The name layer is parented to a secure unit button, so `SetFrameStrata` on it is a protected call
--- and goes through the deferral queue -- the panel refuses to open in combat, but this setter is also
--- what a reset ends up in.
---@param value string
local function SetNameStrata(value)
	local appearance = Private.DB and Private.DB.appearance

	if not appearance then
		return
	end

	appearance.nameStrata = value

	Private.NameStyle.Request()
	Private.Preview.Restyle()
	RefreshPreview()
end

--- Whether the static colour beside a mode dropdown is the one in use.
---@param field string
---@return fun(): boolean
local function IsStaticColor(field)
	return function()
		return not Appearance()[field]
	end
end

--- Whether there is a name to qualify. Hover-only decides *when* the name shows, so with the name off
--- it is a setting for nothing.
---@return boolean
local function IsNameShown()
	return Appearance().nameEnabled
end

--- The strata list with `Inherit` at its head, built per call because the labels are localised and this
--- file loads before the localisation table is filled.
---
--- Labelled from `L.Settings.Strata` exactly as the General tab's Frame Strata dropdown is, so the two
--- cannot end up calling the same layer different things.
---@return { value: any, label: string }[]
local function NameStrataChoices()
	local L = Private.L.Settings
	local order = Private.Enum.FrameStrataOrder
	local choices = { { value = Private.Enum.NameStrataInherit, label = L.NameStrataInherit } }

	for i = 1, #order do
		choices[i + 1] = { value = order[i], label = L.Strata[order[i]] }
	end

	return choices
end

---@param field "frameWidth" | "frameHeight"
---@return fun(): number
local function SizeGetter(field)
	return function()
		return Layout()[field]
	end
end

--- The two size fields live on the layout block rather than the appearance one, since the container
--- places cells from them -- so they request a layout pass instead of an appearance sweep. Every drag
--- frame comes through here and the pass is deferred and keyed, so a drag costs one pass per frame
--- rather than one per event.
---@param field "frameWidth" | "frameHeight"
---@return fun(value: number)
local function SizeSetter(field)
	return function(value)
		local layout = Private.Layout.GetConfig()

		if not layout then
			return
		end

		layout[field] = value

		Private.Layout.Request()
		RefreshPreview()
	end
end

---@return { value: any, label: string }[]
local function TextureChoices()
	return Private.Controls.MediaChoices(Private.Media.StatusBarList(), Private.Media.IsRegistered,
		Appearance().barTexture)
end

--- Both font dropdowns share this: which setting a list is for only matters for the stored key, and
--- that is read per call anyway.
---@param field string
---@return fun(): { value: any, label: string }[]
local function FontChoices(field)
	return function()
		return Private.Controls.MediaChoices(Private.Media.FontList(), Private.Media.IsFontRegistered,
			Appearance()[field])
	end
end

--- The two colour modes, shared by the bar, the name and the health text. `true` is class colour, so
--- the getters hand the stored toggle straight back and the dropdown matches on it.
---@return { value: any, label: string }[]
local function ColorModeChoices()
	local L = Private.L.Settings

	return {
		{ value = true,  label = L.ColorClass },
		{ value = false, label = L.ColorStatic },
	}
end

--- The appearance fields each sub-tab owns, in the order they appear on it. The two frame-size fields
--- live on the layout block instead and are reset alongside the Frame list by `ResetFrame`.
local FRAME_FIELDS = {
	"barTexture",
	"showAbsorb",
	"frameAlpha",
	"outOfRangeAlpha",
	"deadAlpha",
	"healthUseClassColor",
	"healthColorR",
	"healthColorG",
	"healthColorB",
	"healthColorA",
	"healthBgColorR",
	"healthBgColorG",
	"healthBgColorB",
	"healthBgColorA",
}

local NAME_FIELDS = {
	"nameEnabled",
	"nameHoverOnly",
	"nameStrata",
	"nameUseClassColor",
	"nameColorR",
	"nameColorG",
	"nameColorB",
	"nameColorA",
	"nameFont",
	"nameFontSize",
	"namePoint",
	"nameX",
	"nameY",
}

local HEALTH_TEXT_FIELDS = {
	"healthTextEnabled",
	"healthTextFormat",
	"healthTextUseClassColor",
	"healthTextColorR",
	"healthTextColorG",
	"healthTextColorB",
	"healthTextColorA",
	"healthTextFont",
	"healthTextFontSize",
	"healthTextPoint",
	"healthTextX",
	"healthTextY",
}

--- Writes a list of appearance fields back to their shipped defaults, then re-reads the whole tab --
--- the controls, and with them the pane and the swatches whose enablement a colour mode may just have
--- changed.
---
--- `Private.Migration.DefaultAppearance` is the one source of those defaults, freshly built, so a
--- reset can never drift from what a new install ships. Fields are copied by name rather than the
--- block swapped wholesale, so a sub-tab's reset touches only its own.
---@param fields string[]
local function ResetFields(fields)
	local appearance = Private.DB and Private.DB.appearance

	if not appearance then
		return
	end

	local defaults = Private.Migration.DefaultAppearance()

	for i = 1, #fields do
		local field = fields[i]

		appearance[field] = defaults[field]
	end

	ApplyAppearance()
	Private.Options.Refresh()
end

--- The Frame reset, which also restores the two size fields under that sub-tab's own sliders.
local function ResetFrame()
	local layout = Private.Layout.GetConfig()

	if layout then
		local defaults = Private.Migration.DefaultLayout()

		layout.frameWidth = defaults.frameWidth
		layout.frameHeight = defaults.frameHeight

		Private.Layout.Request()
	end

	ResetFields(FRAME_FIELDS)
end

local function ResetName()
	ResetFields(NAME_FIELDS)

	-- The one field in that list the appearance sweep does not carry -- see `SetNameStrata`.
	Private.NameStyle.Request()
end

local function ResetHealthText()
	ResetFields(HEALTH_TEXT_FIELDS)
end

---@param page Frame
---@return SpotlightsNode
local function BuildFrameSubTab(page)
	local L = Private.L.Settings

	--- A heading spans, so each group below starts back in the left column and an odd group leaves a
	--- hole. Members are ordered so that hole falls at the group's end rather than in its middle: the
	--- absorb checkbox ends the health bar group, the frame opacity ends the opacity one.
	return Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.GroupSize),

		Private.Controls.Slider(page, L.Width, FRAME_WIDTH_MIN, FRAME_WIDTH_MAX, 1,
			SizeGetter("frameWidth"), SizeSetter("frameWidth")),
		Private.Controls.Slider(page, L.Height, FRAME_HEIGHT_MIN, FRAME_HEIGHT_MAX, 1,
			SizeGetter("frameHeight"), SizeSetter("frameHeight")),

		Private.Controls.SubHeading(page, L.GroupHealthBar),

		-- Passed as a function, not its result: the list has to be re-read every time the menu opens.
		Private.Controls.Dropdown(page, L.BarTexture, TextureChoices, Getter("barTexture"),
			Setter("barTexture")),

		Private.Controls.Dropdown(page, L.HealthColorMode, ColorModeChoices(),
			Getter("healthUseClassColor"), GatingSetter("healthUseClassColor")),

		Private.Controls.ColorSwatch(page, L.HealthColor, ColorGetter("healthColor"),
			ColorSetter("healthColor"), IsStaticColor("healthUseClassColor")),

		-- The unfilled tail of the bar. Only meaningful in static mode -- class mode derives it -- so
		-- it dims alongside the static bar colour above.
		Private.Controls.ColorSwatch(page, L.HealthBgColor, ColorGetter("healthBgColor"),
			ColorSetter("healthBgColor"), IsStaticColor("healthUseClassColor")),

		Private.Controls.Checkbox(page, L.ShowAbsorb, Getter("showAbsorb"), Setter("showAbsorb")),

		Private.Controls.SubHeading(page, L.GroupOpacity),

		Private.Controls.Slider(page, L.OutOfRangeAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("outOfRangeAlpha"), Setter("outOfRangeAlpha")),
		Private.Controls.Slider(page, L.DeadAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("deadAlpha"), Setter("deadAlpha")),
		Private.Controls.Slider(page, L.FrameAlpha, ALPHA_MIN, ALPHA_MAX, ALPHA_STEP,
			Getter("frameAlpha"), Setter("frameAlpha")),

		-- Outside every group: it ends the body rather than belonging to one part of it.
		Private.Controls.ActionButton(page, L.ResetFrame, ResetFrame, true),
	}, 2, COLUMN_LABEL_WIDTH)
end

---@param page Frame
---@return SpotlightsNode
local function BuildNameSubTab(page)
	local L = Private.L.Settings

	return Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.GroupText),

		Private.Controls.Checkbox(page, L.ShowName, Getter("nameEnabled"),
			GatingSetter("nameEnabled")),

		--- Dims while Show Name is off rather than disappearing, so the pair reads as one decision with a
		--- qualifier instead of a control that comes and goes.
		Private.Controls.Checkbox(page, L.NameHoverOnly, Getter("nameHoverOnly"),
			Setter("nameHoverOnly"), IsNameShown),

		Private.Controls.Dropdown(page, L.NameFont, FontChoices("nameFont"), Getter("nameFont"),
			Setter("nameFont")),
		Private.Controls.Slider(page, L.NameFontSize, FONT_SIZE_MIN, FONT_SIZE_MAX, 1,
			Getter("nameFontSize"), Setter("nameFontSize")),

		Private.Controls.SubHeading(page, L.GroupColor),

		Private.Controls.Dropdown(page, L.NameColorMode, ColorModeChoices(),
			Getter("nameUseClassColor"), GatingSetter("nameUseClassColor")),

		Private.Controls.ColorSwatch(page, L.NameColor, ColorGetter("nameColor"),
			ColorSetter("nameColor"), IsStaticColor("nameUseClassColor")),

		Private.Controls.SubHeading(page, L.GroupPositioning),

		Private.Controls.Dropdown(page, L.NameAnchor, Private.Controls.AnchorChoices, Getter("namePoint"),
			Setter("namePoint")),

		--- Which layer the name is drawn in, rather than where on the frame it sits -- but it belongs
		--- here for the same reason the anchor does: both answer "where does the name end up", and an
		--- aura display over the name is a placement problem however it is solved.
		Private.Controls.Dropdown(page, L.NameStrata, NameStrataChoices(), Getter("nameStrata"),
			SetNameStrata),

		-- Sliders rather than the kit's number pair, unlike the Grid tab's spacing: an offset is
		-- dragged against what it moves, and the pane beside these is what it moves.
		Private.Controls.Slider(page, L.NameOffsetX, OFFSET_MIN, OFFSET_MAX, 1, Getter("nameX"),
			Setter("nameX")),
		Private.Controls.Slider(page, L.NameOffsetY, OFFSET_MIN, OFFSET_MAX, 1, Getter("nameY"),
			Setter("nameY")),

		Private.Controls.ActionButton(page, L.ResetName, ResetName, true),
	}, 2, COLUMN_LABEL_WIDTH)
end

---@param page Frame
---@return SpotlightsNode
local function BuildHealthSubTab(page)
	local L = Private.L.Settings

	return Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.GroupText),

		Private.Controls.Checkbox(page, L.HealthTextEnabled, Getter("healthTextEnabled"),
			Setter("healthTextEnabled")),

		Private.Controls.Dropdown(page, L.HealthTextFormat, {
			{ value = "percent",             label = L.HealthTextPercent },
			{ value = "absValue",            label = L.HealthTextAbsValue },
			{ value = "absValueAbbreviated", label = L.HealthTextAbsValueAbbreviated },
		}, Getter("healthTextFormat"), Setter("healthTextFormat")),

		Private.Controls.Dropdown(page, L.HealthTextFont, FontChoices("healthTextFont"),
			Getter("healthTextFont"), Setter("healthTextFont")),
		Private.Controls.Slider(page, L.HealthTextFontSize, FONT_SIZE_MIN, FONT_SIZE_MAX, 1,
			Getter("healthTextFontSize"), Setter("healthTextFontSize")),

		Private.Controls.SubHeading(page, L.GroupColor),

		Private.Controls.Dropdown(page, L.HealthTextColorMode, ColorModeChoices(),
			Getter("healthTextUseClassColor"), GatingSetter("healthTextUseClassColor")),

		Private.Controls.ColorSwatch(page, L.HealthTextColor, ColorGetter("healthTextColor"),
			ColorSetter("healthTextColor"), IsStaticColor("healthTextUseClassColor")),

		Private.Controls.SubHeading(page, L.GroupPositioning),

		Private.Controls.Dropdown(page, L.HealthTextAnchor, Private.Controls.AnchorChoices,
			Getter("healthTextPoint"), Setter("healthTextPoint")),

		Private.Controls.Slider(page, L.HealthTextOffsetX, OFFSET_MIN, OFFSET_MAX, 1,
			Getter("healthTextX"), Setter("healthTextX")),
		Private.Controls.Slider(page, L.HealthTextOffsetY, OFFSET_MIN, OFFSET_MAX, 1,
			Getter("healthTextY"), Setter("healthTextY")),

		Private.Controls.ActionButton(page, L.ResetHealthText, ResetHealthText, true),
	}, 2, COLUMN_LABEL_WIDTH)
end

---@param page Frame
---@return SpotlightsNode
local function BuildAppearance(page)
	local L = Private.L.Settings

	previewPane = Private.PreviewPane.Build(page)

	local strip, pages = Private.Node.SubTabs(page, {
		{ name = L.FrameHeading,      node = BuildFrameSubTab(page) },
		{ name = L.NameHeading,       node = BuildNameSubTab(page) },
		{ name = L.HealthTextHeading, node = BuildHealthSubTab(page) },
	}, Private.Options.Refresh)

	return Private.Node.Column(page, {
		strip,
		Private.Node.Split(page, pages, previewPane, { rightWidth = Private.PreviewPane.Width }),
	})
end

Private.Options.Builders.appearance = BuildAppearance
