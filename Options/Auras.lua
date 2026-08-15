---@type string, Spotlights
local _, Private = ...

--- The Auras tab: two axes over one page. *Which* feature is being configured is the strip along the bottom
--- of the window; *what* about it is being configured is the Appearance / Tracked strip at the top. The two
--- are independent, which is why the selected category lives here rather than inside either sub-tab.
---
--- The category strip is anchored to the *window*, because a bottom tab strip's art hangs below the frame
--- it belongs to. It is parented to the page all the same, so it follows the tab's own visibility.
---
--- Both sub-tabs live in `Options/AuraAppearance.lua` and `Options/AuraTracked.lua`, and each is handed the
--- selected category as an accessor rather than a copy.

--- Small enough that the strip reads as attached to the window rather than floating under it.
local STRIP_X = 6
local STRIP_Y = 2

--- The dot's space is reserved at **both** ends of the tab, because `TabSystemButtonMixin` re-centres its
--- label on every selection change and would snap a nudged label back. `DOT_INSET + DOT_SIZE` has to stay
--- inside `DOT_SPACE`, and the inset clears the button's own left cap art (`TabSystemTemplates.xml`).
local MAX_TAB_WIDTH = 130
local DOT_SPACE = 26
local DOT_SIZE = 16
local DOT_INSET = 8

--- Applied to the label's alpha rather than its colour, because the template owns the font object and swaps
--- it on every selection -- and because the disabled colour already means "not this specialisation's".
local OFF_ALPHA = 0.5

--- The categories in strip order. `augmentation` is the whole of the gating rule, restating the partition
--- `Private.Auras` splits its feature sets on, because a tab has to be *drawn* disabled for a feature that
--- list has already dropped. Nil is the third state: a feature in **both** sets, which no specialisation
--- gates.
---@type { key: SpotlightsAuraFeatureKey, augmentation: boolean? }[]
local CATEGORIES = {
	{ key = "prescience",     augmentation = true },
	{ key = "shiftingSands",  augmentation = true },
	{ key = "sensePower",     augmentation = true },
	{ key = "cooldownAuras",  augmentation = false },
	{ key = "defensiveAuras", augmentation = false },
	{ key = "customAuras" },
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

---@type SpotlightsTabSystemFrame?
local categoryStrip

---@type table<SpotlightsAuraFeatureKey, integer>
local categoryTabs = {}

---@type table<integer, SpotlightsAuraFeatureKey>
local categoryKeys = {}

---@type table<SpotlightsAuraFeatureKey, CheckButton>
local categoryDots = {}

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

--- Brings the strip in line with the specialisation and with the switches behind its dots.
---
--- Gating is `TabSystemButtonMixin`'s own `SetTabEnabled`, which greys the label, refuses the click,
--- carries the reason into the tooltip and preserves the disabled state across `SetTabSelected`.
local function RefreshCategories()
	if not categoryStrip then
		return
	end

	local L = Private.L.Settings
	local augmentation = Private.Utils.IsAugmentation()

	-- The selection is corrected before the tabs are painted, so the strip ends the pass selecting a
	-- tab it has just enabled rather than one it has just greyed out.
	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]

		if category.key == activeFeature and not Applies(category, augmentation) then
			activeFeature = FirstApplicable(augmentation)

			break
		end
	end

	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]
		local applies = Applies(category, augmentation)
		local enabled = Private.Auras.IsFeatureEnabled(category.key)

		-- A reason only where there is one to give: the three Evoker features say who they are for, and the
		-- rest are left unexplained.
		categoryStrip:SetTabEnabled(categoryTabs[category.key], applies,
			category.augmentation and L.AuraAugmentationOnly or nil)

		categoryStrip:GetTabButton(categoryTabs[category.key]).Text:SetAlpha(enabled and 1 or OFF_ALPHA)

		local dot = categoryDots[category.key]

		dot:SetChecked(enabled)

		-- A category this specialisation does not have is not a switch to offer: the feature would not
		-- render either way.
		dot:SetEnabled(applies)
	end

	-- Painted rather than selected: the selection has not changed here, and `SetTab` would run the
	-- callback, which refreshes the tree this is part of.
	categoryStrip:SetTabVisuallySelected(categoryTabs[activeFeature])
end

--- The enable dot on one category's tab. A checkbox rather than an indicator, so a feature can be turned
--- off without first navigating into it.
---@param button TabSystemButtonFrame
---@param key SpotlightsAuraFeatureKey
---@param name string
---@return CheckButton
local function CreateDot(button, key, name)
	local dot = CreateFrame("CheckButton", nil, button, "UICheckButtonTemplate")

	dot:SetSize(DOT_SIZE, DOT_SIZE)
	dot:SetPoint("LEFT", button, "LEFT", DOT_INSET, 0)

	dot:SetScript("OnClick", function(self)
		Private.Auras.SetFeatureEnabled(key, self:GetChecked() and true or false)

		-- The live displays are the write's own business; these three are this panel's.
		Private.AuraPreview.Restyle()
		RefreshCategories()

		--- The Appearance sub-tab's panes take the feature's switch as an argument to `ApplyAnchor`, so a
		--- refresh rather than a relayout. Done here rather than inside `SetFeatureEnabled`, so the write
		--- path keeps knowing nothing about the panel.
		Private.Options.Refresh()
	end)

	-- Its own tooltip: the tab's label names the category without saying what ticking the box does.
	dot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, string.format(Private.L.Settings.AuraFeatureToggle, name))
		GameTooltip:Show()
	end)

	dot:SetScript("OnLeave", GameTooltip_Hide)

	return dot
end

---@param page Frame
local function CreateCategoryStrip(page)
	local names = CategoryNames()

	categoryStrip = Private.Node.TabSystem(page, "TabSystemButtonTemplate", {
		maxTabWidth = MAX_TAB_WIDTH,
		spacing = 1,
	})

	categoryStrip:SetPoint("TOPLEFT", Private.Options.GetFrame(), "BOTTOMLEFT", STRIP_X, STRIP_Y)

	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]
		local tabID = categoryStrip:AddTab(names[category.key])
		local button = categoryStrip:GetTabButton(tabID)

		--- Widened after the template has sized the tab to its label, the one moment the two can be
		--- separated: the label keeps its measured width and stays centred, so the tab gains `DOT_SPACE` of
		--- clear space at each end. The strip is already dirty from `AddTab`, so this is the width it reads.
		button:SetTabWidth(button:GetWidth() + DOT_SPACE * 2)

		categoryTabs[category.key] = tabID
		categoryKeys[tabID] = category.key
		categoryDots[category.key] = CreateDot(button, category.key, names[category.key])
	end

	categoryStrip:SetTabSelectedCallback(function(tabID)
		local key = categoryKeys[tabID]

		if not key or key == activeFeature then
			return
		end

		activeFeature = key

		-- The Tracked search box moves between the rail and the pane depending on the category, so a query
		-- left behind would filter the incoming list from a box that is no longer on screen.
		Private.AuraTracked.ResetSearch()

		ApplyPreviewFeature()

		-- Before the refresh: the categories do not agree on which displays are on, so the incoming one has
		-- to decide the open states the pass below lays out.
		Private.AuraAppearance.SyncSections()

		-- Both sub-tabs are about the selected category, so the switch is a re-read of the whole tab.
		Private.Options.Refresh()
	end)
end

---@return SpotlightsAuraFeatureKey
local function ActiveFeature()
	return activeFeature
end

---@return string
local function ActiveName()
	return CategoryNames()[activeFeature]
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

	CreateCategoryStrip(page)

	--- Tracked is a tab only where there is a list behind it: Prescience and Shifting Sands watch one spell
	--- each, so the pane would be its own chrome and nothing else.
	local subTabs, pages = Private.Node.SubTabs(page, {
		{ name = L.TabAppearance, node = Private.AuraAppearance.Build(page, ActiveFeature, ActiveName) },
		{
			name = L.AuraTracked,
			node = Private.AuraTracked.Build(page, ActiveFeature, ActiveName),
			Applies = function()
				return Private.AuraSpells.HasSpells(ActiveFeature())
			end,
		},
	}, Private.Options.Refresh)

	local root = Private.Node.Column(page, { subTabs, pages })
	local Refresh = root.Refresh

	--- The strip is not in the tree, so the pass that re-reads the tab has to reach it explicitly -- before
	--- the children, since it is what corrects the category they are about to draw. This is also what
	--- carries an imported profile's switches onto the dots.
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

--- A specialisation change is the one thing that moves the strip on its own, and the selected category may
--- be among those leaving.
---
--- Registered here rather than called from `Private.Auras`' own handler, so it runs after it -- this file
--- is loaded later -- and repaints against a feature set that has already been swapped.
Private.Events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(unit)
	if unit ~= "player" or not categoryStrip then
		return
	end

	Private.Options.Refresh()
	ApplyPreviewFeature()
end)

Private.Options.Builders.auras = BuildAuras
