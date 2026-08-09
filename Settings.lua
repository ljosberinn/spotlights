--- The addon name is kept here: the panel reads its own portrait out of the TOC, and
--- `C_AddOns.GetAddOnMetadata` needs the name to do it.
---@type string, Spotlights
local addonName, Private = ...

---@class SpotlightsSettings
Private.Settings = {}

local Enum = Private.Enum
local Widgets = Private.Widgets

--- The tab strip's five tabs have 520 - 70 = 450px available, but the layout adds 1px between each
--- pair. `maxTabWidth` 89 therefore uses 5 * 89 + 4 * 1 = 449px, leaving the final pixel inside the
--- panel instead of clipping the right edge.
local PANEL_WIDTH = 520

--- The panel's height, now all content: the tab strip sits right of the portrait, so nothing above the
--- scroll area is reserved for it.
local PANEL_HEIGHT = 490
local CONTENT_INSET = 16

--- Where the tab strip starts relative to the panel's left edge, right of the portrait. Shared by the
--- tab system's own anchor and the scroll frames' top anchor, which follows the strip's bottom and has
--- to know the strip's left edge to land content back at `CONTENT_INSET`.
local TAB_STRIP_X = 70

---@type Frame?
local panel

---@class SpotlightsSettingsTab
---@field name string
---@field content Frame the scroll child the widgets are stacked into
---@field widgets SpotlightsWidget[] empty until the tab is first opened

---@type SpotlightsSettingsTab[]
local tabs = {}

local activeTab = 1

---@return SpotlightsLayoutConfig?
local function Layout()
	return Private.DB and Private.DB.layout
end

---@return SpotlightsAppearanceConfig?
local function GetCurrentAppearanceSettings()
	return Private.DB and Private.DB.appearance
end

--- Writes a layout field and requests the passes it invalidates.
---
--- Every setting goes through a writer like this rather than assigning directly, because a write is
--- both a database change and a request: doing only the first leaves the panel and frames disagreeing
--- until something else triggers a pass, reading as the setting having been ignored.
---
--- No combat guard here, deliberately. The write is a plain table assignment and always succeeds; it
--- is the *pass* that is protected, and `Private.Events` already defers that to `PLAYER_REGEN_ENABLED`.
--- So a setting changed as combat starts is stored immediately and applied on regen.
---@param field string
---@param value any
local function SetLayout(field, value)
	local layout = Layout()

	if not layout then
		return
	end

	layout[field] = value

	Private.Layout.Request()
end

--- Brings every spotlight and every preview in line with the current appearance block.
---
--- One sweep, whichever field changed. Most appearance writes touch only one region, but a sweep of
--- the three updaters is cheap (they re-read settings and repaint our own frames, no protected call)
--- and a table mapping field to updater would duplicate knowledge the updaters already hold.
--- `UpdateTexture` ends in `UpdateHealthColor`, so the health colour rides along with it.
local function ApplyAppearance()
	Private.SlotHeader.ForEachChild(function(child)
		child:UpdateTexture()
		child:UpdateNameStyle()
		child:UpdateHealthText()
		child:UpdateRangeAlpha()
	end)

	-- Previews are not header children, so `ForEachChild` does not reach them -- and while the mover
	-- is unlocked they are the only thing on screen out of a raid, the surface an appearance change
	-- most needs to show up on.
	Private.Preview.Restyle()
end

---@param field string
---@param value any
local function SetAppearance(field, value)
	local appearance = GetCurrentAppearanceSettings()

	if not appearance then
		return
	end

	appearance[field] = value

	ApplyAppearance()
end

--- Writes the three channels of a colour in one go, then applies once.
---
--- A colour picker fires continuously while dragged, and three `SetAppearance` calls per frame would
--- sweep the whole grid three times for one visual change. Writing the fields directly and sweeping
--- once collapses that to a single pass, the way the aura colour pickers lean on `SetSetting`'s
--- debounce.
---@param rField string
---@param gField string
---@param bField string
---@param r number
---@param g number
---@param b number
local function SetAppearanceColor(rField, gField, bField, r, g, b)
	local appearance = GetCurrentAppearanceSettings()

	if not appearance then
		return
	end

	appearance[rField], appearance[gField], appearance[bField] = r, g, b

	ApplyAppearance()
end

--- Writes a colour-mode toggle and refreshes the panel so the static pickers re-read their enablement.
---
--- The pickers gate `enabled` on this value but only sample it on `Refresh`, so a bare `SetAppearance`
--- would repaint the frames and leave the just-disabled swatch looking clickable. No relayout: the
--- pickers dim rather than hide, so nothing moves.
---@param field string
---@param value boolean
local function SetColorMode(field, value)
	SetAppearance(field, value)
	Private.Settings.Refresh()
end

--- The appearance fields the Frame section owns, in the order they appear. The two frame-size fields
--- live on the layout block instead and are reset alongside these by `ResetFrame`.
local FRAME_APPEARANCE_FIELDS = {
	"barTexture",
	"showAbsorb",
	"frameAlpha",
	"outOfRangeAlpha",
	"deadAlpha",
	"healthUseClassColor",
	"healthColorR",
	"healthColorG",
	"healthColorB",
	"healthBgColorR",
	"healthBgColorG",
	"healthBgColorB",
}

--- The appearance fields the Name section owns.
local NAME_APPEARANCE_FIELDS = {
	"nameUseClassColor",
	"nameColorR",
	"nameColorG",
	"nameColorB",
	"nameFont",
	"nameFontSize",
	"namePoint",
	"nameX",
	"nameY",
}

local HEALTH_TEXT_APPEARANCE_FIELDS = {
	"healthTextEnabled",
	"healthTextFormat",
	"healthTextUseClassColor",
	"healthTextColorR",
	"healthTextColorG",
	"healthTextColorB",
	"healthTextFont",
	"healthTextFontSize",
	"healthTextPoint",
	"healthTextX",
	"healthTextY",
}

--- Writes a list of appearance fields back to their shipped defaults.
---
--- `Private.Migration.DefaultAppearance` is the one source of those defaults, freshly built, so a reset
--- can never drift from what a new install ships. Fields are copied by name rather than the block
--- swapped wholesale, so a section reset touches only its own fields.
---@param fields string[]
local function ResetAppearanceFields(fields)
	local appearance = GetCurrentAppearanceSettings()

	if not appearance then
		return
	end

	local defaults = Private.Migration.DefaultAppearance()

	for i = 1, #fields do
		local field = fields[i]

		appearance[field] = defaults[field]
	end
end

--- Resets the Frame section: its appearance fields plus the two frame-size fields on the layout block,
--- which sit under the same heading. One layout request and one appearance sweep, then a panel refresh
--- so every control re-reads -- the sliders, the mode dropdown, and the static pickers whose enablement
--- the mode just changed.
local function ResetFrame()
	local layout = Layout()

	if layout then
		local defaults = Private.Migration.DefaultLayout()

		layout.frameWidth = defaults.frameWidth
		layout.frameHeight = defaults.frameHeight

		Private.Layout.Request()
	end

	ResetAppearanceFields(FRAME_APPEARANCE_FIELDS)
	ApplyAppearance()
	Private.Settings.Refresh()
end

--- Resets the Name section. Only appearance fields, so no layout request.
local function ResetName()
	ResetAppearanceFields(NAME_APPEARANCE_FIELDS)
	ApplyAppearance()
	Private.Settings.Refresh()
end

--- Moves every widget of `list` onto the end of `target`.
---
--- For the two tabs assembled in pieces: the roster list, whose contents come from another module, and
--- the aura tab, where the same three border controls appear once per display.
---@param target SpotlightsWidget[]
---@param list SpotlightsWidget[]
local function Append(target, list)
	for i = 1, #list do
		target[#target + 1] = list[i]
	end
end

--- The texture choices, rebuilt per call from whatever LibSharedMedia currently knows.
---
--- Not cached: another addon can register media after we build the panel, and a list captured at load
--- would omit it until a reload. `Private.Media` handles the same problem for the *applied* texture.
---
--- Takes the stored key and the media kind rather than reading a setting itself, because several
--- settings now hold a media key (the health bar, both aura bars, four borders) and only the caller
--- knows which one a list is for.
---@param list string[]
---@param IsRegistered fun(key: string): boolean
---@param stored string?
---@return { value: any, label: string }[]
local function MediaChoices(list, IsRegistered, stored)
	local choices = {}

	for i = 1, #list do
		choices[i] = { value = list[i], label = list[i] }
	end

	-- A stored key nothing currently registers gets added anyway, marked. The setting is legitimately
	-- kept in that case (a media pack can be disabled for one session), so the honest display is the
	-- name plus a note, not a blank dropdown and not the default silently standing in. The dropdown
	-- derives its label from whichever choice reports itself selected, so without a matching entry
	-- there would be no label and the setting would look lost rather than merely unavailable.
	if stored and not IsRegistered(stored) then
		choices[#choices + 1] = {
			value = stored,
			label = string.format(Private.L.Settings.TextureMissing, stored),
		}
	end

	return choices
end

---@param stored string?
---@return { value: any, label: string }[]
local function TextureChoices(stored)
	return MediaChoices(Private.Media.StatusBarList(), Private.Media.IsRegistered, stored)
end

---@param stored string?
---@return { value: any, label: string }[]
local function BorderChoices(stored)
	return MediaChoices(Private.Media.BorderList(), Private.Media.IsBorderRegistered, stored)
end

---@param stored string?
---@return { value: any, label: string }[]
local function FontChoices(stored)
	return MediaChoices(Private.Media.FontList(), Private.Media.IsFontRegistered, stored)
end

--- The nine anchor points, in reading order, with prose labels.
---
--- Built per call rather than once at load, because the labels are localised and this file loads
--- before the localisation table is filled. Shared by the appearance tab's name placement and the aura
--- tab's display placement.
---@return { value: any, label: string }[]
local function AnchorChoices()
	local L = Private.L.Settings
	local order = Enum.AnchorPointOrder
	local choices = {}

	for i = 1, #order do
		choices[i] = { value = order[i], label = L.Anchors[order[i]] }
	end

	return choices
end

---@param content Frame
---@return SpotlightsWidget[]
local function BuildGeneralTab(content)
	local L = Private.L.Settings

	return {
		Widgets.CreateButtonPair(content, L.ToggleMover, function()
			Private.Mover.SetUnlocked(not Private.Mover.IsUnlocked())
		end, L.Recenter, function()
			local position = Private.Container.GetPosition()

			if not position or InCombatLockdown() then
				return
			end

			position.point, position.x, position.y = "CENTER", 0, 0

			Private.Container.Request()
		end),

		Widgets.CreateCheckbox(content, L.ShowMinimapButton, function()
			local minimap = Private.DB and Private.DB.minimap

			return minimap and not minimap.hide or false
		end, function(value)
			local minimap = Private.DB and Private.DB.minimap

			if not minimap then
				return
			end

			minimap.hide = not value

			local icon = LibStub("LibDBIcon-1.0")

			if value then
				icon:Show(addonName)
			else
				icon:Hide(addonName)
			end
		end, 160),
	}
end

local function ResetHealthText()
	ResetAppearanceFields(HEALTH_TEXT_APPEARANCE_FIELDS)
	ApplyAppearance()
	Private.Settings.Refresh()
end

---@param content Frame
---@return SpotlightsWidget[]
local function BuildAppearanceTab(content)
	local L = Private.L.Settings

	-- The two colour modes, shared by the health bar and the name. `true` is class colour, so the get
	-- closures below hand the toggle straight back and the dropdown matches on it.
	local colorModes = {
		{ value = true,  label = L.ColorClass },
		{ value = false, label = L.ColorStatic },
	}

	return {
		Widgets.CreateHeading(content, L.FrameHeading),

		Widgets.CreateSlider(content, L.Width, 40, 300, 1, function()
			return Layout() and Layout().frameWidth or 90
		end, function(value)
			SetLayout("frameWidth", value)
		end),

		Widgets.CreateSlider(content, L.Height, 20, 200, 1, function()
			return Layout() and Layout().frameHeight or 40
		end, function(value)
			SetLayout("frameHeight", value)
		end),

		-- Passed as a function, not its result: the list has to be re-read every time the menu
		-- opens so media registered after the panel was built still appears.
		Widgets.CreateDropdown(content, L.BarTexture, function()
			local appearance = GetCurrentAppearanceSettings()

			return TextureChoices(appearance and appearance.barTexture)
		end, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.barTexture
		end, function(value)
			SetAppearance("barTexture", value)
		end),

		Widgets.CreateDropdown(content, L.HealthColorMode, colorModes, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthUseClassColor
		end, function(value)
			SetColorMode("healthUseClassColor", value)
		end),

		-- Kept in place and dimmed rather than hidden when class colour is on: a swatch that does
		-- nothing in the current mode reads as disabled, and hiding it would cost a relayout every time
		-- the mode dropdown moved. The predicate re-reads the mode on each panel refresh, which
		-- `SetColorMode` triggers.
		Widgets.CreateColorPicker(content, L.HealthColor, function()
			local appearance = GetCurrentAppearanceSettings()

			if not appearance then
				return 0.1, 0.7, 0.1
			end

			return appearance.healthColorR, appearance.healthColorG, appearance.healthColorB
		end, function(r, g, b)
			SetAppearanceColor("healthColorR", "healthColorG", "healthColorB", r, g, b)
		end, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and not appearance.healthUseClassColor
		end),

		-- The unfilled tail of the bar. Only meaningful in static mode (class mode derives it) so it
		-- disables alongside the static bar colour above.
		Widgets.CreateColorPicker(content, L.HealthBgColor, function()
			local appearance = GetCurrentAppearanceSettings()

			if not appearance then
				return 0.02, 0.14, 0.02
			end

			return appearance.healthBgColorR, appearance.healthBgColorG, appearance.healthBgColorB
		end, function(r, g, b)
			SetAppearanceColor("healthBgColorR", "healthBgColorG", "healthBgColorB", r, g, b)
		end, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and not appearance.healthUseClassColor
		end),

		Widgets.CreateCheckbox(content, L.ShowAbsorb, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.showAbsorb or false
		end, function(value)
			SetAppearance("showAbsorb", value)
		end),

		Widgets.CreateSlider(content, L.OutOfRangeAlpha, 0.1, 1, 0.05, function()
			local appearance = GetCurrentAppearanceSettings()
			return appearance and appearance.outOfRangeAlpha or 0.45
		end, function(value)
			SetAppearance("outOfRangeAlpha", value)
		end),

		Widgets.CreateSlider(content, L.DeadAlpha, 0.1, 1, 0.05, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.deadAlpha or 0.45
		end, function(value)
			SetAppearance("deadAlpha", value)
		end),

		Widgets.CreateSlider(content, L.FrameAlpha, 0.1, 1, 0.05, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.frameAlpha or 1
		end, function(value)
			SetAppearance("frameAlpha", value)
		end),

		Widgets.CreateButton(content, L.ResetFrame, ResetFrame),

		Widgets.CreateHeading(content, L.NameHeading),

		Widgets.CreateDropdown(content, L.NameColorMode, colorModes, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.nameUseClassColor
		end, function(value)
			SetColorMode("nameUseClassColor", value)
		end),

		Widgets.CreateColorPicker(content, L.NameColor, function()
			local appearance = GetCurrentAppearanceSettings()

			if not appearance then
				return 1, 1, 1
			end

			return appearance.nameColorR, appearance.nameColorG, appearance.nameColorB
		end, function(r, g, b)
			SetAppearanceColor("nameColorR", "nameColorG", "nameColorB", r, g, b)
		end, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and not appearance.nameUseClassColor
		end),

		Widgets.CreateDropdown(content, L.NameFont, function()
			local appearance = GetCurrentAppearanceSettings()

			return FontChoices(appearance and appearance.nameFont)
		end, function()
			local appearance = GetCurrentAppearanceSettings()
			return appearance and appearance.nameFont
		end, function(value)
			SetAppearance("nameFont", value)
		end),

		Widgets.CreateSlider(content, L.NameFontSize, 6, 32, 1, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.nameFontSize or 10
		end, function(value)
			SetAppearance("nameFontSize", value)
		end),

		Widgets.CreateDropdown(content, L.NameAnchor, AnchorChoices, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.namePoint
		end, function(value)
			SetAppearance("namePoint", value)
		end),

		Widgets.CreateSlider(content, L.NameOffsetX, -100, 100, 1, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.nameX or 0
		end, function(value)
			SetAppearance("nameX", value)
		end),

		Widgets.CreateSlider(content, L.NameOffsetY, -100, 100, 1, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.nameY or 0
		end, function(value)
			SetAppearance("nameY", value)
		end),

		Widgets.CreateButton(content, L.ResetName, ResetName),

		Widgets.CreateHeading(content, L.HealthTextHeading),

		Widgets.CreateCheckbox(content, L.HealthTextEnabled, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextEnabled or false
		end, function(value)
			SetAppearance("healthTextEnabled", value)
			Private.Settings.Refresh()
		end),

		Widgets.CreateDropdown(content, L.HealthTextFormat, {
			{ value = "percent",             label = L.HealthTextPercent },
			{ value = "absValue",            label = L.HealthTextAbsValue },
			{ value = "absValueAbbreviated", label = L.HealthTextAbsValueAbbreviated },
		}, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextFormat
		end, function(value)
			SetAppearance("healthTextFormat", value)
		end),

		Widgets.CreateDropdown(content, L.HealthTextColorMode, colorModes, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextUseClassColor
		end, function(value)
			SetColorMode("healthTextUseClassColor", value)
		end),

		Widgets.CreateColorPicker(content, L.HealthTextColor, function()
			local appearance = GetCurrentAppearanceSettings()

			if not appearance then
				return 0.5, 0.5, 0.5
			end

			return appearance.healthTextColorR, appearance.healthTextColorG, appearance.healthTextColorB
		end, function(r, g, b)
			SetAppearanceColor("healthTextColorR", "healthTextColorG", "healthTextColorB", r, g, b)
		end, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and not appearance.healthTextUseClassColor
		end),

		Widgets.CreateDropdown(content, L.HealthTextFont, function()
			local appearance = GetCurrentAppearanceSettings()

			return FontChoices(appearance and appearance.healthTextFont)
		end, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextFont
		end, function(value)
			SetAppearance("healthTextFont", value)
		end),

		Widgets.CreateSlider(content, L.HealthTextFontSize, 6, 32, 1, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextFontSize or 10
		end, function(value)
			SetAppearance("healthTextFontSize", value)
		end),

		Widgets.CreateDropdown(content, L.HealthTextAnchor, AnchorChoices, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextPoint
		end, function(value)
			SetAppearance("healthTextPoint", value)
		end),

		Widgets.CreateSlider(content, L.HealthTextOffsetX, -100, 100, 1, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextX or 0
		end, function(value)
			SetAppearance("healthTextX", value)
		end),

		Widgets.CreateSlider(content, L.HealthTextOffsetY, -100, 100, 1, function()
			local appearance = GetCurrentAppearanceSettings()

			return appearance and appearance.healthTextY or 0
		end, function(value)
			SetAppearance("healthTextY", value)
		end),

		Widgets.CreateButton(content, L.ResetHealthText, ResetHealthText),
	}
end

---@param content Frame
---@return SpotlightsWidget[]
local function BuildGridTab(content)
	local L = Private.L.Settings

	return {
		Widgets.CreateDropdown(content, L.Orientation, {
			{ value = Enum.Orientation.Horizontal, label = L.Horizontal },
			{ value = Enum.Orientation.Vertical,   label = L.Vertical },
		}, function()
			return Layout() and Layout().orientation
		end, function(value)
			SetLayout("orientation", value)
		end),

		Widgets.CreateSlider(content, L.Stride, 1, 40, 1, function()
			return Layout() and Layout().stride or 5
		end, function(value)
			SetLayout("stride", value)
		end),

		Widgets.CreateDropdown(content, L.GrowX, {
			{ value = Enum.GrowX.Right, label = L.GrowRight },
			{ value = Enum.GrowX.Left,  label = L.GrowLeft },
		}, function()
			return Layout() and Layout().growX
		end, function(value)
			SetLayout("growX", value)
		end),

		Widgets.CreateDropdown(content, L.GrowY, {
			{ value = Enum.GrowY.Down, label = L.GrowDown },
			{ value = Enum.GrowY.Up,   label = L.GrowUp },
		}, function()
			return Layout() and Layout().growY
		end, function(value)
			SetLayout("growY", value)
		end),

		Widgets.CreateSlider(content, L.SpacingX, 0, 40, 1, function()
			return Layout() and Layout().spacingX or 3
		end, function(value)
			SetLayout("spacingX", value)
		end),

		Widgets.CreateSlider(content, L.SpacingY, 0, 40, 1, function()
			return Layout() and Layout().spacingY or 3
		end, function(value)
			SetLayout("spacingY", value)
		end),
	}
end

--- The roster tab: the empty-cell setting, the combat caveat, and the roster list itself.
---
--- These share a tab because they are the same subject: the setting decides what happens to a cell when
--- its player leaves, the caveat says when a list change takes effect, and the list is where both are
--- acted on.
---@param content Frame
---@return SpotlightsWidget[]
local function BuildRosterTab(content)
	local L = Private.L.Settings

	local widgets = {
		Widgets.CreateCheckbox(content, L.AllowGaps, function()
			return Layout() and Layout().allowGaps or false
		end, function(value)
			SetLayout("allowGaps", value)

			-- Gaps changes what each cell *holds* rather than where the cells are, so the registry
			-- has to re-resolve. Geometry alone would leave the same names in the same cells.
			Private.Events.Request(Enum.DeferralKey.Registry)
		end),

		Widgets.CreateText(content, L.AllowGapsHelp),

		Widgets.CreateCheckbox(content, L.ClearOnLeave, function()
			return Layout() and Layout().clearOnLeave or false
		end, function(value)
			-- Through the same writer as every other layout field, even though this one invalidates
			-- nothing on screen: the pass it requests is coalesced and costs a click.
			SetLayout("clearOnLeave", value)
		end),

		Widgets.CreateText(content, L.ClearOnLeaveHelp),

		-- The one user-visible consequence of the architecture, documented in this panel because there
		-- is nowhere else to put it.
		Widgets.CreateText(content, L.CombatHelp),
	}

	-- The list goes last, because it is the only widget whose height changes after the tab is built.
	-- Anything stacked below it would be repositioned on every roster event.
	Append(widgets, Private.RosterList.Build(content))

	return widgets
end

--- Which aura the tab's controls are currently pointed at.
---
--- Every widget in the kit reads and writes through closures, so a sub-tab switch is one variable
--- write plus the `RefreshActive` the panel already does — no widget is rebuilt and no second set
--- exists.
---@type SpotlightsAuraFeatureKey
local activeFeature = "prescience"

---@return SpotlightsAuraFeatureConfig?
local function Feature()
	local auras = Private.DB and Private.DB.auras

	return auras and auras[activeFeature]
end

---@return SpotlightsAuraBarConfig?
local function Bar()
	local feature = Feature()

	return feature and feature.bar
end

---@return SpotlightsAuraIconConfig?
local function Icon()
	local feature = Feature()

	return feature and feature.icon
end

--- Writes one aura setting through the one entry point that knows what it costs.
---
--- Unlike `SetLayout` and `SetAppearance`, this requests nothing itself. `Private.Auras` decides
--- between a next-frame reapply and a debounced rebuild from the field name, and that decision has to
--- live with the frames: a settings file that knew which fields are frozen would be a second copy of a
--- list that can only be wrong.
---@param displayKey SpotlightsAuraDisplayKey
---@param field string
---@param value any
local function SetAura(displayKey, field, value)
	Private.Auras.SetSetting(activeFeature, displayKey, field, value)

	-- Unconditional, and the one place the preview earns its keep. Half of these settings reach a live
	-- display only after a debounce and a rebuild; all reach a preview now. So a drag's feedback comes
	-- from here, and the frames catch up when the hand stops.
	Private.AuraPreview.Restyle()
end

--- The three border controls, identical for both displays.
---
--- A border is the one piece of styling that does not care whether it is around a bar or an icon, so
--- writing these twice would duplicate the same thing.
---@param content Frame
---@param displayKey SpotlightsAuraDisplayKey
---@param Get fun(): SpotlightsAuraDisplayConfig?
---@return SpotlightsWidget[]
local function BorderWidgets(content, displayKey, Get)
	local L = Private.L.Settings

	return {
		Widgets.CreateDropdown(content, L.AuraBorder, function()
			local config = Get()

			return BorderChoices(config and config.borderTexture)
		end, function()
			local config = Get()

			return config and config.borderTexture
		end, function(value)
			SetAura(displayKey, "borderTexture", value)
		end),

		Widgets.CreateSlider(content, L.AuraBorderSize, 1, 32, 1, function()
			local config = Get()

			return config and config.borderSize or 12
		end, function(value)
			SetAura(displayKey, "borderSize", value)
		end),

		Widgets.CreateColorPicker(content, L.AuraBorderColor, function()
			local config = Get()

			if not config then
				return 0, 0, 0
			end

			return config.borderR, config.borderG, config.borderB
		end, function(r, g, b)
			SetAura(displayKey, "borderR", r)
			SetAura(displayKey, "borderG", g)
			SetAura(displayKey, "borderB", b)
		end),
	}
end

--- The sub-tab the spell pool belongs to. Only Sense Power reads the pool, so only Sense Power shows it.
local SENSE_POWER = "sensePower"

local RESET_POPUP = "SPOTLIGHTS_AURA_RESET"

--- Every class that has cooldowns, in class-ID order.
---
--- Derived from `Constants.UICharacterClasses` rather than counted to thirteen, so a class added to the
--- game arrives here without this file being edited. Sorted because `pairs` over that map has no order.
---@return integer[]
local function ClassOrder()
	local order = {}

	for _, classID in pairs(Constants.UICharacterClasses) do
		order[#order + 1] = classID
	end

	table.sort(order)

	return order
end

--- The built-in rows: a class heading, then that class's cooldowns, for every class that has any.
---
--- Built once and kept, unlike the custom list beside it. The shipped table cannot change while the
--- game is running, so rebuilding this on every refresh would be thirteen sorts to reach the same
--- answer. The *toggles* are read per row by the widget, not baked in here.
---@type { heading: string?, spellID: integer?, r: number?, g: number?, b: number? }[]?
local cooldownEntries

---@return { heading: string?, spellID: integer?, r: number?, g: number?, b: number? }[]
local function CooldownEntries()
	if cooldownEntries then
		return cooldownEntries
	end

	local cooldowns = Private.Auras.Cooldowns()
	local order = ClassOrder()

	cooldownEntries = {}

	for i = 1, #order do
		local classID = order[i]
		local spells = cooldowns[classID]

		-- A class with no cooldowns left in the list gets no heading. Pruning the shipped table is
		-- expected, and an empty class heading would advertise a group with nothing in it.
		if spells then
			local info = C_CreatureInfo.GetClassInfo(classID)
			local color = info and RAID_CLASS_COLORS[info.classFile]
			local spellIDs = {}

			for spellID in pairs(spells) do
				spellIDs[#spellIDs + 1] = spellID
			end

			table.sort(spellIDs)

			cooldownEntries[#cooldownEntries + 1] = {
				heading = info and info.className or tostring(classID),
				r = color and color.r or 1,
				g = color and color.g or 1,
				b = color and color.b or 1,
			}

			for j = 1, #spellIDs do
				cooldownEntries[#cooldownEntries + 1] = { spellID = spellIDs[j] }
			end
		end
	end

	return cooldownEntries
end

--- The custom rows, which are whatever the user has added.
---@return { spellID: integer }[]
local function CustomEntries()
	local spellIDs = Private.Auras.CustomCooldowns()
	local entries = {}

	for i = 1, #spellIDs do
		entries[i] = { spellID = spellIDs[i] }
	end

	return entries
end

--- Makes a widget belong to the Sense Power sub-tab alone.
---
--- Wrapping `Refresh` rather than asking every widget to check for itself, because the check is the
--- same for all of them and the widgets are shared with the other sub-tab's controls, which must not
--- learn about sub-tabs. `Stack` skips a hidden widget, so hiding is all this has to do — and contents
--- are only refreshed when visible, keeping a fifty-row list from rebuilding on every slider touch on
--- the other sub-tab.
---@param widget SpotlightsWidget
---@return SpotlightsWidget
local function SensePowerOnly(widget)
	local Refresh = widget.Refresh

	function widget:Refresh()
		local shown = activeFeature == SENSE_POWER

		self:SetShown(shown)

		if shown then
			Refresh(self)
		end
	end

	return widget
end

--- The Auras tab: one customisation set, pointed at either spell by the sub-tabs.
---
--- **Nothing but a line of text on a client that cannot have the feature.** Building the controls
--- anyway and disabling them would invite the reading that the settings are broken.
---@param content Frame
---@return SpotlightsWidget[]
local function BuildAurasTab(content)
	local L = Private.L.Settings

	if not Private.Auras.IsSupported then
		return {
			Widgets.CreateText(
				content,
				Private.IsTwelveDotOne and L.AurasEvokerOnly or L.AurasRequiresTwelveOne
			),
		}
	end

	local widgets = {
		Widgets.CreateSubTabs(content, {
			{ value = "prescience", label = L.Prescience },
			{ value = "sensePower", label = L.SensePower },
		}, function()
			return activeFeature
		end, function(value)
			activeFeature = value

			-- Both, and in this order. `Refresh` re-reads every widget, which decides whether the spell
			-- pool below is shown; `Relayout` then closes or opens the gap it left. Refreshing alone
			-- would switch the controls over and leave several hundred pixels of blank scroll behind.
			Private.Settings.Refresh()
			Private.Settings.Relayout()
		end),

		-- Under the sub-tabs so it is plainly scoped to the selected feature, and above the first
		-- heading so it never scrolls out of reach. Confirmed rather than immediate: a reset discards a
		-- layout the user may have spent a while on, and a stray click on a top-of-tab button is the
		-- accident a confirmation exists to catch.
		Widgets.CreateButton(content, L.AuraReset, function()
			-- Registered at click time rather than at load: the localisation table is filled by now,
			-- and the feature name is read from whichever sub-tab is active at the click rather than
			-- baked in when the tab was built.
			StaticPopupDialogs[RESET_POPUP] = {
				text = string.format(
					L.AuraResetPrompt,
					activeFeature == SENSE_POWER and L.SensePower or L.Prescience
				),
				button1 = L.AuraResetConfirm,
				button2 = CANCEL,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,

				OnAccept = function()
					Private.Auras.ResetFeature(activeFeature)

					-- Re-read the visible widgets so sliders, dropdowns and checkboxes show the
					-- just-written values, and restyle the preview so the change is visible now rather
					-- than after the live displays wait out their rebuild debounce.
					Private.Settings.Refresh()
					Private.AuraPreview.Restyle()
				end,
			}

			StaticPopup_Show(RESET_POPUP)
		end),

		Widgets.CreateHeading(content, L.AuraBar),

		Widgets.CreateCheckbox(content, L.AuraEnabled, function()
			return Bar() and Bar().enabled or false
		end, function(value)
			SetAura("bar", "enabled", value)
		end),

		Widgets.CreateDropdown(content, L.BarTexture, function()
			return TextureChoices(Bar() and Bar().texture)
		end, function()
			return Bar() and Bar().texture
		end, function(value)
			SetAura("bar", "texture", value)
		end),

		Widgets.CreateColorPicker(content, L.AuraColor, function()
			local bar = Bar()

			if not bar then
				return 1, 1, 1
			end

			return bar.r, bar.g, bar.b
		end, function(r, g, b)
			-- Three writes rather than one, which costs nothing extra. Each may queue a rebuild, but
			-- all three name the same display, so they collapse into one entry and one timer.
			SetAura("bar", "r", r)
			SetAura("bar", "g", g)
			SetAura("bar", "b", b)
		end),

		Widgets.CreateSlider(content, L.AuraAlpha, 0.05, 1, 0.05, function()
			return Bar() and Bar().alpha or 0.5
		end, function(value)
			SetAura("bar", "alpha", value)
		end),

		Widgets.CreateSlider(content, L.AuraWidthPct, 0.05, 1, 0.05, function()
			return Bar() and Bar().widthPct or 1
		end, function(value)
			SetAura("bar", "widthPct", value)
		end),

		Widgets.CreateSlider(content, L.AuraHeightPct, 0.05, 1, 0.05, function()
			return Bar() and Bar().heightPct or 0.5
		end, function(value)
			SetAura("bar", "heightPct", value)
		end),

		Widgets.CreateDropdown(content, L.AuraAnchor, AnchorChoices, function()
			return Bar() and Bar().point
		end, function(value)
			SetAura("bar", "point", value)
		end),

		Widgets.CreateSlider(content, L.AuraOffsetX, -200, 200, 1, function()
			return Bar() and Bar().x or 0
		end, function(value)
			SetAura("bar", "x", value)
		end),

		Widgets.CreateSlider(content, L.AuraOffsetY, -200, 200, 1, function()
			return Bar() and Bar().y or 0
		end, function(value)
			SetAura("bar", "y", value)
		end),

		Widgets.CreateCheckbox(content, L.AuraShowIcon, function()
			return Bar() and Bar().showIcon or false
		end, function(value)
			SetAura("bar", "showIcon", value)
		end),

		Widgets.CreateDropdown(content, L.AuraIconSide, {
			{ value = "LEFT",  label = L.AuraIconLeft },
			{ value = "RIGHT", label = L.AuraIconRight },
		}, function()
			return Bar() and Bar().iconSide
		end, function(value)
			SetAura("bar", "iconSide", value)
		end),
	}

	Append(widgets, BorderWidgets(content, "bar", Bar))

	Append(widgets, {
		Widgets.CreateHeading(content, L.AuraIcon),

		Widgets.CreateCheckbox(content, L.AuraEnabled, function()
			return Icon() and Icon().enabled or false
		end, function(value)
			SetAura("icon", "enabled", value)
		end),

		Widgets.CreateSlider(content, L.AuraIconWidth, 16, 128, 1, function()
			return Icon() and Icon().width or 50
		end, function(value)
			SetAura("icon", "width", value)
		end),

		Widgets.CreateSlider(content, L.AuraIconHeight, 16, 128, 1, function()
			return Icon() and Icon().height or 50
		end, function(value)
			SetAura("icon", "height", value)
		end),

		Widgets.CreateSlider(content, L.AuraAlpha, 0.05, 1, 0.05, function()
			return Icon() and Icon().alpha or 1
		end, function(value)
			SetAura("icon", "alpha", value)
		end),

		Widgets.CreateCheckbox(content, L.AuraShowSwipe, function()
			return Icon() and Icon().showSwipe or false
		end, function(value)
			SetAura("icon", "showSwipe", value)
		end),

		Widgets.CreateCheckbox(content, L.AuraShowText, function()
			return Icon() and Icon().showText or false
		end, function(value)
			SetAura("icon", "showText", value)
		end),

		Widgets.CreateDropdown(content, L.AuraFont, function()
			local config = Icon()

			return FontChoices(config and config.font)
		end, function()
			local config = Icon()

			return config and config.font
		end, function(value)
			SetAura("icon", "font", value)
		end),

		Widgets.CreateSlider(content, L.AuraFontSize, 6, 32, 1, function()
			return Icon() and Icon().fontSize or 16
		end, function(value)
			SetAura("icon", "fontSize", value)
		end),

		Widgets.CreateDropdown(content, L.AuraAnchor, AnchorChoices, function()
			return Icon() and Icon().point
		end, function(value)
			SetAura("icon", "point", value)
		end),

		Widgets.CreateSlider(content, L.AuraOffsetX, -200, 200, 1, function()
			return Icon() and Icon().x or 0
		end, function(value)
			SetAura("icon", "x", value)
		end),

		Widgets.CreateSlider(content, L.AuraOffsetY, -200, 200, 1, function()
			return Icon() and Icon().y or 0
		end, function(value)
			SetAura("icon", "y", value)
		end),
	})

	Append(widgets, BorderWidgets(content, "icon", Icon))

	-- Last of the customisation controls, the explanation of everything above it.
	Append(widgets, { Widgets.CreateText(content, L.AurasRebuildHelp) })

	--- The spell pool, which belongs to Sense Power alone.
	---
	--- Below everything else and in that order — shipped list, then the user's own — because the second
	--- only makes sense once the first has shown what a tracked cooldown looks like.
	---
	--- Every one of these is wrapped: the aura tab is one set of widgets serving both sub-tabs, so a
	--- section belonging to one has to hide itself rather than exist twice.
	Append(widgets, {
		SensePowerOnly(Widgets.CreateHeading(content, L.AuraBuiltinCooldowns)),
		SensePowerOnly(Widgets.CreateText(content, L.AuraBuiltinCooldownsNote)),

		-- Both accessors passed straight through, no wrapper. Their `custom` parameter is the third and
		-- the widget only ever passes two, so omitting it *is* saying "a shipped cooldown" -- which is
		-- why the custom list below wraps them and this one does not.
		SensePowerOnly(
			Widgets.CreateSpellList(
				content,
				CooldownEntries,
				Private.Auras.IsCooldownEnabled,
				Private.Auras.SetCooldownEnabled
			)
		),

		SensePowerOnly(Widgets.CreateHeading(content, L.AuraCustomCooldowns)),
		SensePowerOnly(Widgets.CreateText(content, L.AuraCustomCooldownsNote)),
	})

	--- Declared before the list so the input's Add can refresh it, and appended after so it draws above.
	---
	--- The two have to know about each other: adding an ID changes the list's row count, and only the
	--- list can turn that into a height. Nothing else on the tab needs this, hence a local here.
	---@type SpotlightsWidget
	local customList

	customList = SensePowerOnly(
		Widgets.CreateSpellList(content, CustomEntries, function(spellID)
			return Private.Auras.IsCooldownEnabled(spellID, true)
		end, function(spellID, enabled)
			Private.Auras.SetCooldownEnabled(spellID, enabled, true)
		end, function(spellID)
			Private.Auras.RemoveCustomCooldown(spellID)

			-- Refresh before relayout, because the row count is what the new height is derived from.
			customList:Refresh()
			Private.Settings.Relayout()
		end)
	)

	Append(widgets, {
		customList,

		SensePowerOnly(
			Widgets.CreateSpellInput(content, L.AuraCustomSpellID, L.AuraCustomAdd, function(spellID)
				if not Private.Auras.AddCustomCooldown(spellID) then
					return false
				end

				customList:Refresh()
				Private.Settings.Relayout()

				return true
			end)
		),
	})

	return widgets
end

local RELOAD_POPUP = "SPOTLIGHTS_AURA_RELOAD"

--- Offers a reload if aura frames have been abandoned, and asks at most once per abandonment.
---
--- **An aura display cannot be restyled, only replaced**, and WoW cannot destroy the one it replaces —
--- so a texture or colour change leaves a container and a button behind on every assigned spotlight,
--- for the session. A reload is the only thing that reclaims them, and the only honest moment to
--- mention it is when the user has finished editing.
---
--- On `OnHide` rather than from `SetShown`, because the panel closes three ways and only one goes
--- through `SetShown`: it is in `UISpecialFrames` so Escape hides it directly, and the
--- `PLAYER_REGEN_DISABLED` handler calls `panel:Hide()`. `OnHide` catches all three, and catching the
--- combat one is deliberate — a fight starting is not a reason to silently drop the offer.
---
--- `Private.Auras` owns the "has anything been abandoned" question rather than this file counting its
--- own writes, because the answer includes rebuilds still inside the debounce window.
local function MaybePromptReload()
	if not Private.Auras.NeedsReload() then
		return
	end

	local L = Private.L.Settings

	-- Registered at show time rather than at load, so the localisation table is filled by now.
	StaticPopupDialogs[RELOAD_POPUP] = {
		text = L.ReloadPrompt,
		button1 = L.ReloadNow,
		button2 = L.ReloadLater,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,

		-- Above Blizzard's own dialogs rather than under them, since this can appear as combat
		-- starts and something else may already be on screen.
		preferredIndex = 3,

		OnAccept = function()
			Private.Auras.AcknowledgeReload()
			ReloadUI()
		end,

		-- Both answers acknowledge. Escape routes here too, and a dismissal that left the prompt armed
		-- would re-ask on every subsequent close without anything having changed.
		OnCancel = function()
			Private.Auras.AcknowledgeReload()
		end,
	}

	StaticPopup_Show(RELOAD_POPUP)
end

--- Everything the panel owes the rest of the addon when it goes away, by whichever route it went.
---
--- The previews come down first. A reload prompt is a modal the user may sit on for a while, and
--- leaving fake aura displays on the grid behind it — possibly through a pull, since combat is one of
--- the three routes — would read as the addon having stuck.
local function OnPanelHidden()
	Private.AuraPreview.SetShown(false)
	MaybePromptReload()
end

---@type table<integer, fun(content: Frame): SpotlightsWidget[]>
local builders = {}

--- Re-reads every widget on the visible tab.
---
--- Only the visible one: the others are hidden and will be refreshed when shown. Not just a saving — a
--- slider's Refresh writes a value, and refreshing a hidden tab would do it for controls the user
--- cannot see having changed.
local function RefreshActive()
	local tab = tabs[activeTab]

	if not tab then
		return
	end

	for i = 1, #tab.widgets do
		tab.widgets[i]:Refresh()
	end
end

---@return Frame
local function Get()
	if panel then
		return panel
	end

	local L = Private.L.Settings

	--- `PortraitFrameTemplate`, which is what `PlayerSpellsFrame` and the rest of the modern panels use.
	---
	--- Over `BasicFrameTemplateWithInset`, whose inner inset border is the older look: this is a
	--- `NineSlicePanelTemplate` with a `layoutType` the game resolves itself, so the borders follow
	--- Blizzard's current panel art rather than being pinned to the build we were written against. It
	--- also brings a `TitleContainer` and a `PortraitContainer`, which is why the title is set through
	--- the mixin below rather than by writing to a font string.
	panel = CreateFrame("Frame", "SpotlightsSettings", UIParent, "PortraitFrameTemplate")
	panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:Hide()
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

	-- StartMoving is fine here and wrong for the container: its scaled-frame position jump does not
	-- matter for a panel whose position is never persisted, and this frame is nowhere near a protected
	-- one.
	panel:SetClampedToScreen(true)

	-- `SetTitle` rather than `TitleText:SetText`, because the font string moved: `TitledPanelMixin`
	-- (which `PortraitFrameMixin` is built from) keeps it at `TitleContainer.TitleText`, and reaching
	-- through to it would depend on where it happens to live today.
	panel:SetTitle(L.Title)

	--- The portrait, filled from the icon the addon already declares.
	---
	--- Read from the TOC rather than repeated here. `## IconTexture` is what the addon list and the
	--- compartment already show, so taking the same value means the panel cannot wear a different face
	--- than the addon does -- and changing it stays a one-line edit in the TOC.
	---
	--- The container's circular mask crops the icon's square border, which is why there is no
	--- `SetPortraitTexCoord` here: full coords are what Blizzard passes for icon assets.
	local icon = C_AddOns.GetAddOnMetadata(addonName, "IconTexture")

	if icon then
		panel:SetPortraitToAsset(icon)
	end

	-- UISpecialFrames closes the panel on Escape, the behaviour every other options frame has.
	table.insert(UISpecialFrames, "SpotlightsSettings")

	panel:SetScript("OnHide", OnPanelHidden)

	-- The tab system owns selection, visibility and keyboard/tooltip behaviour for the six tabs.
	-- `TabSystemOwnerMixin` is mixed in here rather than inherited, because the mixin's `OnLoad` is not
	-- run for a frame we create ourselves.
	Mixin(panel, TabSystemOwnerMixin)
	TabSystemOwnerMixin.OnLoad(panel)

	local tabSystem = CreateFrame("Frame", nil, panel, "SpotlightsSettingsTabSystemTemplate")

	-- Right of the portrait, the way SpellBook clears its own icon. This is what makes the change
	-- reclaim space instead of costing it: the tab strip no longer sits below the 62px portrait, so no
	-- header height is reserved above the scroll area -- each scroll frame anchors its top to the tab
	-- system's bottom instead.
	--
	-- Nudged down seven from the plain 19: the *selected* tab is drawn emphasised, with its on-top art
	-- reaching above the strip's rectangle, so the strip has to sit low enough that the emphasis clears
	-- the title rather than leaking into it.
	tabSystem:SetPoint("TOPLEFT", panel, "TOPLEFT", TAB_STRIP_X, -26)

	panel:SetTabSystem(tabSystem)

	local names = {
		L.TabGeneral,
		L.TabAppearance,
		L.TabGrid,
		L.TabAuras,
		L.TabRoster,
	}

	builders = {
		BuildGeneralTab,
		BuildAppearanceTab,
		BuildGridTab,
		BuildAurasTab,
		BuildRosterTab,
	}

	for i = 1, #names do
		--- A bare `ScrollFrame` rather than `UIPanelScrollFrameTemplate`, whose whole contribution was
		--- the old chunky scrollbar and its wheel handling. `ScrollUtil.InitScrollFrameWithScrollBar`
		--- below replaces both.
		local scroll = CreateFrame("ScrollFrame", nil, panel)

		-- Explicit, where the old template did it for us. `InitScrollFrameWithScrollBar` sets an
		-- `OnMouseWheel` script, and a script alone does nothing on a frame that is not listening.
		scroll:EnableMouseWheel(true)

		-- The top follows the tab system's bottom rather than restating the strip's height, so a change
		-- to the tab art cannot leave the scroll area in the wrong place. Anchored to the strip's
		-- bottom-left and offset back out to `CONTENT_INSET`, which lands the content where it always
		-- sat while the top edge tracks the strip.
		scroll:SetPoint("TOPLEFT", tabSystem, "BOTTOMLEFT", CONTENT_INSET - TAB_STRIP_X, -8)
		scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_INSET - 22, CONTENT_INSET + 8)

		--- The same scrollbar the Friends list uses, `MinimalScrollBar`.
		---
		--- Eight pixels wide against the 22 this panel reserves right of every scroll frame, so it drops
		--- into the existing gutter -- the content width, and the row arithmetic in `Widgets.lua` that
		--- depends on it, are unchanged.
		---
		--- A sibling of the scroll frame rather than a child: a `ScrollFrame` clips, and a bar anchored
		--- past its right edge would be clipped away.
		local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")

		scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -3)
		scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 3)

		-- Teaches the pair about each other: the bar drives `SetVerticalScroll`, the frame reports its
		-- range and offset back, and the wheel is routed through the bar so it steps in the thumb's
		-- increments.
		ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

		local content = CreateFrame("Frame", nil, scroll)

		content:SetWidth(PANEL_WIDTH - CONTENT_INSET * 2 - 22)
		content:SetHeight(1)
		scroll:SetScrollChild(content)

		-- The tab system's tracker shows and hides the scroll frame and its bar together. The bar hangs
		-- off the panel rather than the scroll frame, so it does not inherit the scroll's visibility --
		-- which is why both are registered with the tab, not only the scroll.
		local tabID = panel:AddNamedTab(names[i], scroll, scrollBar)

		panel:SetTabCallback(tabID, function()
			activeTab = i

			-- Compared against the builder rather than against a tab number, so adding or reordering
			-- a tab cannot silently point this at the wrong one.
			Private.AuraPreview.SetShown(builders[i] == BuildAurasTab)

			-- Built on first show rather than at panel creation. The texture dropdown reads
			-- LibSharedMedia's list, so deferring it to the first open means a media pack that loads
			-- after us is still listed.
			local tab = tabs[i]

			if #tab.widgets == 0 then
				tab.widgets = builders[i](tab.content)
			end

			-- Refresh before laying out, and lay out on every selection rather than only the first.
			-- Both follow from widgets that can hide themselves: `Refresh` sets a widget's visibility,
			-- and `Stack` needs that answer current. Doing it every time also fixes a tab built, left in
			-- one state, and returned to in another -- the aura tab's sub-tab, and the roster list whose
			-- height changed while the tab was not being looked at.
			RefreshActive()
			Private.Settings.Relayout()
		end)

		tabs[i] = {
			name = names[i],
			content = content,
			widgets = {},
		}
	end

	return panel
end

--- Opens or closes the panel.
---
--- Refuses to open in combat rather than opening masked. A panel whose every control is disabled is
--- worse than no panel: it invites the user to conclude the settings are broken, and there is no way to
--- tell "masked because combat" from "masked because bug" by looking at it.
---@param shown boolean?
function Private.Settings.SetShown(shown)
	local frame = Get()

	if shown == nil then
		shown = not frame:IsShown()
	end

	if shown and InCombatLockdown() then
		Private.Utils.Print(Private.L.Settings.CombatRefused)

		return
	end

	frame:SetShown(shown)

	if shown then
		panel:SetTab(activeTab)
	end
end

--- Re-stacks the active tab and resizes its scroll child.
---
--- For a widget whose height is not fixed at build time, or whose *visibility* is not: the roster list,
--- the aura tab's two spell lists, and the spell input whose preview line comes and goes. None can set
--- the scroll child's height itself, because that height is the sum of every widget on the tab and each
--- knows only its own.
---
--- Callers must `Refresh` first when visibility is what changed, since `Stack` skips hidden widgets and
--- `Refresh` is what hides them.
---
--- `Stack` is idempotent and runs over a handful of widgets, so re-running it whole is cheaper than
--- tracking which offsets a height change invalidated.
function Private.Settings.Relayout()
	local tab = tabs[activeTab]

	if not tab or #tab.widgets == 0 then
		return
	end

	tab.content:SetHeight(Widgets.Stack(tab.widgets, tab.content))
end

--- Whether the cursor is anywhere over the panel.
---
--- For the drag path, which has two kinds of drop target — a slot row in this panel, and a cell on the
--- grid — and no way to tell them apart by geometry alone. The panel is at DIALOG strata and the grid
--- is not, so a panel over the grid hides it; without this, releasing on a dead part of the panel that
--- overlaps a cell would assign to the cell underneath.
---@return boolean
function Private.Settings.IsCursorOver()
	return panel ~= nil and Private.Utils.IsCursorOver(panel)
end

--- Re-reads the visible tab. For a setting changed behind the panel's back — by a slash command,
--- or by the mover's own combat lock.
function Private.Settings.Refresh()
	if panel and panel:IsShown() then
		RefreshActive()
	end
end

Private.Events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	-- Before the panel, so the picker is gone whether or not the panel opened it. It is a separate
	-- top-level frame and outlives its opener, so closing only the panel leaves a colour wheel floating
	-- over the fight with nothing behind it.
	ColorPickerFrame:Hide()

	if panel and panel:IsShown() then
		panel:Hide()
		Private.Utils.Print(Private.L.Settings.ClosedByCombat)
	end
end)

Private.SlashCommands.Register("options", "Options", function()
	Private.Settings.SetShown()
end)
