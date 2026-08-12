---@type string, Spotlights
local _, Private = ...

--- The Auras tab: two axes over one page.
---
--- *Which* feature is being configured is the strip along the bottom of the window; *what* about it is
--- being configured is the Appearance / Tracked strip at the top. The two are independent -- switching
--- category leaves the sub-tab where it was, and the other way round -- which is why the selected
--- category lives in this file rather than inside either sub-tab: both are about it, neither owns it.
---
--- The category strip is anchored to the *window* rather than laid out inside the content rectangle,
--- because a bottom tab strip's art hangs below the frame it belongs to. It is parented to the page all
--- the same: the shell shows and hides that per tab, which is exactly when the strip should come and
--- go, so it follows the Auras tab without the shell being told about it.
---
--- The Appearance sub-tab lives in `Options/AuraAppearance.lua`, which is handed the selected category
--- as an accessor rather than a copy. The Tracked one is still a stub; issue 09 fills it in.

--- Where the strip starts along the window's bottom edge, and how far its art hangs below it. Both as
--- the old panel already places its own.
local STRIP_X = 6
local STRIP_Y = 2

--- What a tab's label may grow to before it is truncated, and the room reserved beside it for the dot.
---
--- Reserved at **both** ends of the tab: `TabSystemButtonMixin` re-centres its label whenever the
--- selection changes, so a label nudged right to clear the dot would snap back on the next click.
--- Padding the tab evenly leaves the label centred where it already was, which is the one arrangement
--- nothing resets -- at the price of the same gap doing nothing on the right.
---
--- `DOT_INSET + DOT_SIZE` has to stay inside `DOT_SPACE`, or the dot reaches into the label.
---
--- The inset clears the tab's own left cap rather than being a round number: `uiframe-tab-left` is
--- anchored flush to the button's corner (`TabSystemTemplates.xml`), so a dot nearer than its bevel sits
--- on the frame's edge art instead of inside the tab.
---
--- Five labels at the cap would total more than the window is wide, but only one is ever near it -- the
--- Cooldowns category, whose name is a phrase in every locale -- and the four short ones leave it room.
local MAX_TAB_WIDTH = 130
local DOT_SPACE = 26
local DOT_SIZE = 16
local DOT_INSET = 8

--- What a switched-off category's label fades to.
---
--- Applied to the label's alpha rather than its colour, because the tab template owns the font object
--- and swaps it on every selection -- and because the disabled *colour* is already spoken for by a
--- category this specialisation cannot use at all. Off and unavailable have to look different: one is
--- the user's decision and one is not theirs to make.
local OFF_ALPHA = 0.5

--- The categories in strip order, each with the specialisation that has it.
---
--- `augmentation` is the whole of the gating rule: an Augmentation Evoker configures the three Evoker
--- features and nobody else does, and everybody else configures the two pooled ones. It restates the
--- partition `Private.Auras` splits its own feature sets on, because a tab has to be *drawn* disabled
--- for a feature that list has already dropped.
---@type { key: SpotlightsAuraFeatureKey, augmentation: boolean }[]
local CATEGORIES = {
	{ key = "prescience",     augmentation = true },
	{ key = "shiftingSands",  augmentation = true },
	{ key = "sensePower",     augmentation = true },
	{ key = "cooldownAuras",  augmentation = false },
	{ key = "defensiveAuras", augmentation = false },
}

--- Which feature both sub-tabs are about. Starts where the old panel starts, and is corrected against
--- the specialisation by the first refresh -- which happens before anything is drawn.
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

--- The category names, read where they are used rather than held at file scope, as every other tab
--- reads its strings: five table entries per call is nothing, and a cached table is one more thing that
--- can be stale.
---@return table<SpotlightsAuraFeatureKey, string>
local function CategoryNames()
	local L = Private.L.Settings

	return {
		prescience = L.Prescience,
		shiftingSands = L.ShiftingSands,
		sensePower = L.SensePower,
		cooldownAuras = L.Cooldowns,
		defensiveAuras = L.Defensives,
	}
end

--- Points the preview layer at the selected category, rebuilding it when that moved.
---
--- **Only while this tab is the one on screen.** The preview layer is global, and the old panel drives
--- it from its own strip until the cutover deletes it -- so pushing from a panel the user is not looking
--- at would repoint the previews the other one is showing.
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

		if category.augmentation == augmentation then
			return category.key
		end
	end

	return activeFeature
end

--- Brings the strip in line with the specialisation and with the switches behind its dots.
---
--- Gating is `TabSystemButtonMixin`'s own `SetTabEnabled`, which greys the label, refuses the click and
--- carries the reason into the tooltip. Unlike the old panel there is therefore no click handler to
--- swap out and nothing to re-apply after a selection: the mixin preserves the disabled state across
--- `SetTabSelected`, which is where the old panel had to put it back.
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

		if category.key == activeFeature and category.augmentation ~= augmentation then
			activeFeature = FirstApplicable(augmentation)

			break
		end
	end

	for i = 1, #CATEGORIES do
		local category = CATEGORIES[i]
		local applies = category.augmentation == augmentation
		local enabled = Private.Auras.IsFeatureEnabled(category.key)

		-- A reason only where there is one to give. The three Evoker features say who they are for;
		-- the two pooled ones are simply not an Augmentation Evoker's, which the old panel also leaves
		-- unexplained -- a sentence about a category that specialisation does not have would be one
		-- more thing to read than to act on.
		categoryStrip:SetTabEnabled(categoryTabs[category.key], applies,
			category.augmentation and L.AuraAugmentationOnly or nil)

		categoryStrip:GetTabButton(categoryTabs[category.key]).Text:SetAlpha(enabled and 1 or OFF_ALPHA)

		local dot = categoryDots[category.key]

		dot:SetChecked(enabled)

		-- A category this specialisation does not have is not a switch to offer: the feature would not
		-- render either way, so a tickable dot would promise something turning it on cannot deliver.
		dot:SetEnabled(applies)
	end

	-- Painted rather than selected, since the selection has not changed as far as this file is
	-- concerned -- and `SetTab` would run the callback, which refreshes the tree this is part of.
	categoryStrip:SetTabVisuallySelected(categoryTabs[activeFeature])
end

--- The enable dot on one category's tab.
---
--- A checkbox rather than an indicator, because it is the control as well as the state: the design puts
--- the switch on the tab so a feature can be turned off without first navigating into it.
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

		-- The live displays are the write's own business; these two are this panel's. The previews
		-- follow the switch immediately, and the strip repaints the label beside the dot just clicked.
		Private.AuraPreview.Restyle()
		RefreshCategories()
	end)

	-- Its own tooltip, naming the category: the dot carries no label, and the one on the tab behind it
	-- names the category without saying what ticking the box does.
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

		--- Widened after the template has sized the tab to its label, which is the one moment the two
		--- can be separated: the label keeps the width it measured and stays centred, so the tab gains
		--- `DOT_SPACE` of clear space at each end and the dot goes in the left one. The strip is already
		--- dirty from `AddTab` and lays itself out next frame, so this is the width it reads.
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

		ApplyPreviewFeature()

		-- Both sub-tabs are about the selected category, so the switch is a re-read of the tab rather
		-- than anything of its own. The strip's own repaint rides along with it.
		Private.Options.Refresh()
	end)
end

--- What a sub-tab shows until the issue that fills it lands: the category it is about, so that a
--- change on either strip is visible in what the other one draws.
---@param page Frame
---@return SpotlightsNode
local function BuildStub(page)
	return Private.Controls.SubHeading(page, function()
		return CategoryNames()[activeFeature]
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
end

local function OnPageHidden()
	Private.AuraPreview.SetShown(false)

	-- A section's open state belongs to the visit rather than to the panel, and this is the moment the
	-- visit ends -- on a tab switch as well as on a close, which is the same answer either way.
	Private.AuraAppearance.ResetSections()
end

---@param page Frame
---@return SpotlightsNode
local function BuildAuras(page)
	local L = Private.L.Settings

	--- Nothing but a line of text on a client that cannot have the feature, as the old panel answers it
	--- too: a strip whose every tab is disabled invites the reading that the settings are broken.
	if not Private.Auras.IsSupported then
		return Private.Controls.Paragraph(page, L.AurasRequiresTwelveOne)
	end

	auraPage = page

	CreateCategoryStrip(page)

	local subTabs, pages = Private.Node.SubTabs(page, {
		{ name = L.TabAppearance, node = Private.AuraAppearance.Build(page, ActiveFeature, ActiveName) },
		{ name = L.AuraTracked,   node = BuildStub(page) },
	}, Private.Options.Refresh)

	local root = Private.Node.Column(page, { subTabs, pages })
	local Refresh = root.Refresh

	--- The strip is not in the tree -- it hangs off the window rather than sitting in the content
	--- rectangle -- so the pass that re-reads the tab has to reach it explicitly. Before the children,
	--- because it is what corrects the category they are about to draw. This is also what carries an
	--- imported profile's switches onto the dots: the import replaces the database behind the panel's
	--- back, and the tab is re-read on the way back into it.
	function root:Refresh()
		RefreshCategories()
		Refresh(self)
	end

	page:SetScript("OnShow", OnPageShown)
	page:SetScript("OnHide", OnPageHidden)

	--- The page was shown before this builder ran -- the shell shows it, then selects the tab that
	--- builds it -- so the first `OnShow` has already been and gone. Refreshed first, since what the
	--- preview layer is pointed at is whatever the gating leaves selected rather than what this file
	--- was loaded with.
	RefreshCategories()
	OnPageShown()

	return root
end

--- A specialisation change is the one thing that moves the strip on its own: three categories become
--- unavailable and two become available, and the selected one may be among those leaving.
---
--- Registered here rather than called from `Private.Auras`' own handler, and therefore running after it
--- -- this file is loaded later -- which is what it needs: the feature set has already been swapped by
--- the time the strip is repainted against it.
---
--- A closed panel needs nothing. The refresh below is what corrects the selection, and a tab that is
--- not on screen is refreshed on the way back into it.
Private.Events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(unit)
	if unit ~= "player" or not categoryStrip then
		return
	end

	Private.Options.Refresh()
	ApplyPreviewFeature()
end)

Private.Options.Builders.auras = BuildAuras
