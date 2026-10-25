---@type string, Spotlights
local _, Private = ...

--- The Auras tab: two axes over one page. *Which* feature is being configured is the icon tabs on the
--- window's right edge; *what* about it is being configured is the Appearance / Tracked strip at the top.
--- The two are independent, which is why the selected category lives here rather than inside either
--- sub-tab. The category's own on/off switch heads the column, above the strip.
---
--- The category tabs are anchored to the *window*, because side tabs hang off its edge. They are parented
--- to the page all the same, so they follow the tab's own visibility.
---
--- Both sub-tabs live in `Options/AuraAppearance.lua` and `Options/AuraTracked.lua`, and each is handed the
--- selected category as an accessor rather than a copy.

--- Copied from the Housing dashboard (`Blizzard_HousingDashboard.xml:25-54`), whose window is the same
--- `PortraitFrameTemplate` as ours.
local RAIL_X = 0
local RAIL_Y = -60
local RAIL_SPACING = 12

--- A spell texture has no size of its own, unlike the atlas icons beside it, so it is sized to match them.
--- The crop takes off the baked-in border every spell icon carries.
local SPELL_ICON_SIZE = 28
local SPELL_ICON_CROP = 0.08

--- Handed to the tab's column rather than left to its default, so the height both sub-tabs are given
--- cannot drift from the gaps actually laid out above them.
local CHROME_GAP = 6

--- Fits the longest translation, deDE "Benutzerdefinierte Auren überwachen"; anything longer still has the
--- truncation tooltip.
local TOGGLE_LABEL_WIDTH = 260

--- The categories in tab order. `augmentation` is the whole of the gating rule, restating the partition
--- `Private.Auras` splits its feature sets on, because a tab has to be taken off the rail for a feature that
--- list has already dropped. Nil is the third state: a feature in **both** sets, which no specialisation
--- gates.
---
--- Each names its icon by exactly one of `spellID` or `atlas`.
---@type { key: SpotlightsAuraFeatureKey, augmentation: boolean?, spellID: integer?, atlas: string? }[]
local CATEGORIES = {
	{ key = "prescience",     augmentation = true,  spellID = 410089 },
	{ key = "shiftingSands",  augmentation = true,  spellID = 413984 },
	{ key = "sensePower",     augmentation = true,  spellID = 361022 },
	{ key = "cooldownAuras",  augmentation = false, atlas = "icon_cooldownmanager" },
	{ key = "defensiveAuras", augmentation = false, spellID = 33206 },
	{ key = "customAuras",                          atlas = "icon_trackedbuffs" },
}

--- Whether a category is one the given specialisation configures.
---@param category { key: SpotlightsAuraFeatureKey, augmentation: boolean? }
---@param augmentation boolean
---@return boolean
local function Applies(category, augmentation)
	return category.augmentation == nil or category.augmentation == augmentation
end

--- Which feature both sub-tabs are about. Corrected against the specialisation by the first refresh, which
--- happens before anything is drawn.
---@type SpotlightsAuraFeatureKey
local activeFeature = "cooldownAuras"

---@type SpotlightsSideTabRailFrame?
local categoryRail

---@type table<SpotlightsAuraFeatureKey, SpotlightsSideTabFrame>
local categoryTabs = {}

--- The tab's page, kept because its visibility is the panel's answer to "is the user looking at this".
---@type Frame?
local auraPage

--- Read per call rather than held at file scope, as every other tab reads its strings.
---@return table<SpotlightsAuraFeatureKey, string>
local function CategoryNames()
	local L = Private.L.Settings

	return {
		prescience = L.Prescience,
		shiftingSands = L.ShiftingSands,
		sensePower = L.SensePower,
		cooldownAuras = L.Cooldowns,
		defensiveAuras = L.Defensives,
		customAuras = L.CustomAuras,
	}
end

--- Points the preview layer at the selected category, rebuilding it when that moved.
---
--- **Only while this tab is the one on screen**, since the preview layer is global and the panel's other
--- tabs do not want it repointed under them.
local function ApplyPreviewFeature()
	if not auraPage or not auraPage:IsVisible() then
		return
	end

	if Private.Auras.SetPreviewFeature(activeFeature) then
		Private.AuraPreview.Rebuild()
	end
end

--- The first category this specialisation can actually configure, for when the selected one stops
--- being one of them.
---@param augmentation boolean
---@return SpotlightsAuraFeatureKey
local function FirstApplicable(augmentation)
	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]

		if Applies(category, augmentation) then
			return category.key
		end
	end

	return activeFeature
end

--- Brings the tabs in line with the specialisation and with each category's switch.
---
--- Gating hides the tab, which the layout frame then leaves out entirely -- a specialisation's own
--- categories read as the whole rail rather than as part of a longer one.
local function RefreshCategories()
	if not categoryRail then
		return
	end

	local augmentation = Private.Utils.IsAugmentation()

	-- The selection is corrected before the tabs are painted, so the rail ends the pass selecting a
	-- tab it has just shown rather than one it has just removed.
	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]

		if category.key == activeFeature and not Applies(category, augmentation) then
			activeFeature = FirstApplicable(augmentation)

			break
		end
	end

	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]
		local tab = categoryTabs[category.key]

		tab:SetShown(Applies(category, augmentation))
		tab.Icon:SetDesaturated(not Private.Auras.IsFeatureEnabled(category.key))
		tab.SelectedTexture:SetShown(category.key == activeFeature)
	end

	-- Now rather than through `MarkDirty`, which waits a frame and would draw that frame with a gap.
	categoryRail:Layout()
end

---@param key SpotlightsAuraFeatureKey
local function SelectCategory(key)
	if key == activeFeature then
		return
	end

	activeFeature = key

	-- The search box moves between the Tracked rail and its pane depending on the category, so a query
	-- left behind would filter the incoming list from a box that is no longer on screen.
	Private.AuraTracked.ResetSearch()

	ApplyPreviewFeature()

	-- Before the refresh: the categories do not agree on which displays are on, so the incoming one has
	-- to decide the open states the pass below lays out.
	Private.AuraAppearance.SyncSections()

	-- Both sub-tabs are about the selected category, so the switch is a re-read of the whole tab.
	Private.Options.Refresh()
end

--- One category's tab.
---
--- **The mixin's `SetChecked` is never called**: on live it repaints `Icon` from `activeAtlas`, which a
--- spell tab does not have, so it would wipe the texture. The selection is `SelectedTexture` alone, which the
--- template shows by default and `RefreshCategories` paints on every tab.
---@param category { key: SpotlightsAuraFeatureKey, spellID: integer?, atlas: string? }
---@param name string
---@param index integer
---@return SpotlightsSideTabFrame
local function CreateCategoryTab(category, name, index)
	local tab = CreateFrame("Frame", nil, categoryRail, "LargeSideTabButtonTemplate") --[[@as SpotlightsSideTabFrame]]

	tab.layoutIndex = index

	-- Always set: the mixin's `OnEnter` passes it to the tooltip unchecked.
	tab.tooltipText = name

	if category.atlas then
		tab.Icon:SetAtlas(category.atlas, true)
	else
		tab.Icon:SetTexture(C_Spell.GetSpellTexture(category.spellID))
		tab.Icon:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
		tab.Icon:SetTexCoord(SPELL_ICON_CROP, 1 - SPELL_ICON_CROP, SPELL_ICON_CROP, 1 - SPELL_ICON_CROP)
	end

	-- The mixin plays the click sound itself, before this runs.
	tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
		if button == "LeftButton" and upInside then
			SelectCategory(category.key)
		end
	end)

	return tab
end

---@param page Frame
local function CreateCategoryRail(page)
	local names = CategoryNames()

	categoryRail = CreateFrame("Frame", nil, page, "VerticalLayoutFrame") --[[@as SpotlightsSideTabRailFrame]]
	categoryRail.spacing = RAIL_SPACING
	categoryRail:SetPoint("TOPLEFT", Private.Options.GetFrame(), "TOPRIGHT", RAIL_X, RAIL_Y)

	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]

		categoryTabs[category.key] = CreateCategoryTab(category, names[category.key], i)
	end
end

---@return SpotlightsAuraFeatureKey
local function ActiveFeature()
	return activeFeature
end

---@return string
local function ActiveName()
	return CategoryNames()[activeFeature]
end

---@return string
local function ToggleLabel()
	return string.format(Private.L.Settings.AuraFeatureToggle, ActiveName())
end

---@return boolean
local function ActiveEnabled()
	return Private.Auras.IsFeatureEnabled(activeFeature)
end

---@param value boolean
local function SetActiveEnabled(value)
	Private.Auras.SetFeatureEnabled(activeFeature, value)

	-- The live displays are the write's own business; the previews are this panel's.
	Private.AuraPreview.Restyle()

	--- The Appearance sub-tab's panes take the feature's switch as an argument to `ApplyAnchor`, so a
	--- refresh rather than a relayout. Done here rather than inside `SetFeatureEnabled`, so the write
	--- path keeps knowing nothing about the panel.
	Private.Options.Refresh()
end

local function OnPageShown()
	ApplyPreviewFeature()
	Private.AuraPreview.SetShown(true)

	-- The first visit of a session has no category switch in front of it, so the show path decides the open
	-- states too, and is their only other writer.
	Private.AuraAppearance.SyncSections()
end

local function OnPageHidden()
	Private.AuraPreview.SetShown(false)

	-- The Tracked rail's search belongs to the visit, which ends here on a tab switch as well as on a close.
	Private.AuraTracked.ResetSearch()
end

---@param page Frame
---@return SpotlightsNode
local function BuildAuras(page)
	local L = Private.L.Settings

	auraPage = page

	CreateCategoryRail(page)

	-- Above the sub-tab strip rather than inside either, since it switches the category both are about.
	local toggle = Private.Controls.Checkbox(page, ToggleLabel, ActiveEnabled, SetActiveEnabled, nil, nil,
		TOGGLE_LABEL_WIDTH)

	local height = page:GetHeight() - Private.Controls.RowHeight - Private.Node.SubTabHeight - CHROME_GAP * 2

	--- Tracked is a tab only where there is a list behind it: Prescience and Shifting Sands watch one spell
	--- each, so the pane would be its own chrome and nothing else.
	local subTabs, pages = Private.Node.SubTabs(page, {
		{
			name = L.TabAppearance,
			node = Private.AuraAppearance.Build(page, ActiveFeature, ActiveName, height),
		},
		{
			name = L.AuraTracked,
			node = Private.AuraTracked.Build(page, ActiveFeature, ActiveName, height),
			Applies = function()
				return Private.AuraSpells.HasSpells(ActiveFeature())
			end,
		},
	}, Private.Options.Refresh)

	local root = Private.Node.Column(page, { toggle, subTabs, pages }, CHROME_GAP)
	local Refresh = root.Refresh

	--- The rail is not in the tree, so the pass that re-reads the tab has to reach it explicitly -- before
	--- the children, since it is what corrects the category they are about to draw. This is also what
	--- carries an imported profile's switches onto the tabs.
	function root:Refresh()
		RefreshCategories()
		Refresh(self)
	end

	page:SetScript("OnShow", OnPageShown)
	page:SetScript("OnHide", OnPageHidden)

	--- The shell shows the page and then selects the tab that builds it, so the first `OnShow` has already
	--- been and gone. Refreshed first, so the preview layer follows whatever the gating leaves selected.
	RefreshCategories()
	OnPageShown()

	return root
end

--- A specialisation change is the one thing that moves the rail on its own, and the selected category may
--- be among those leaving.
---
--- Registered here rather than called from `Private.Auras`' own handler, so it runs after it -- this file
--- is loaded later -- and repaints against a feature set that has already been swapped.
Private.Events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(unit)
	if unit ~= "player" or not categoryRail then
		return
	end

	Private.Options.Refresh()
	ApplyPreviewFeature()
end)

Private.Options.Builders.auras = BuildAuras
