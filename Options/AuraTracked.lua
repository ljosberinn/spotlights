---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraTracked
Private.AuraTracked = {}

--- The Auras tab's Tracked sub-tab: which spells the selected category watches.
---
--- Two panes. The rail on the left lists the categories' spells by class, with a count of how many of
--- each are switched on, and it is what the pane beside it is about. The pane itself is a stub here;
--- issue 10 fills it with the spell rows.
---
--- Which category all of this is about lives in `Options/Auras.lua`, on the strip along the bottom of
--- the window, and reaches this file as an accessor rather than a copy -- exactly as it reaches the
--- Appearance sub-tab beside this one. What that category *contains* is `Options/AuraSpells.lua`'s
--- answer: this file draws groups and counts without knowing that two of the five categories share one
--- pool and two others have no spells at all.

--- The rail's width, as the design specifies it: 196 of the content rectangle's 748.
local RAIL_WIDTH = 196

--- One class row. Shorter than a control row, as the old panel's spell rows are and for the same
--- reason: fourteen rows at the kit's 26 read as a ladder rather than as a list.
local ROW_HEIGHT = 22

--- What a row keeps clear at each end, and between a long class name and the count it must not reach.
local ROW_INSET = 4
local COUNT_GAP = 6

--- The selected row's fill, and the hover tint over it.
---
--- Both `SetColorTexture`, since the design's accent is a colour rather than art, and the selected one
--- is roughly twice the hover so that hovering the selected row still reads as hovering something.
local ACCENT_ALPHA = 0.12
local HIGHLIGHT_ALPHA = 0.06

--- `InputBoxVisualTemplate`'s own height, and how far its left cap is drawn outside the box
--- (`InputBoxTemplates.xml`). The box is inset by the overhang rather than sized to it, so the art
--- lands on the rail's edge instead of five pixels past it.
local SEARCH_HEIGHT = 20
local SEARCH_INSET = 5

--- Between the search box, the list and the reset button under them.
local RAIL_GAP = 6

--- What this sub-tab's chrome costs its own height: the gap under the Auras tab's sub-tab strip. The
--- rail gets everything else, so the reset button ends up on the window's bottom edge rather than at a
--- guess at how many classes there "usually" are.
local CHROME_RESERVE = 6

--- Floors for the rail and the list inside it, in case the window is ever shorter than this tab's
--- chrome costs -- better a cramped list than a negative height Blizzard errors on.
local MIN_RAIL_HEIGHT = 120
local MIN_LIST_HEIGHT = 40

--- Shared with the old panel and with the Appearance sub-tab deliberately: the dialog is registered at
--- click time by whoever was clicked, and a second key would stack a second identical prompt.
local RESET_POPUP = "SPOTLIGHTS_AURA_RESET"

--- Which category the strip has selected, and its localised name for the reset prompt. Both handed in
--- by `Build`, because the strip they come from is not this file's.
---@type fun(): SpotlightsAuraFeatureKey
local ActiveFeature

---@type fun(): string
local ActiveName

--- Which group the rail points at, as a key rather than a group: the groups themselves are rebuilt per
--- category, and a held table would be one belonging to a category the user has since left.
---
--- Deliberately not per category. A key that exists in both pools -- every class does -- keeps the rail
--- where the user left it when they switch between Cooldowns and Defensives, and one that does not is
--- corrected to the first row on the way in.
---@type string?
local selectedKey

--- What has been typed in the search box, lowercased once here rather than at every comparison.
---@type string
local query = ""

--- The box itself, kept so the sub-tab can empty it on the way out. One rail, one box, so a module
--- local rather than something threaded back out of the tree.
---@type EditBox?
local searchBox

--- A rail row. Its parts are named here rather than left implicit because a pooled frame is a
--- different group after every pass, and every one of them is re-pointed on each.
---@class SpotlightsAuraRailRow : Button
---@field accent Texture the selected row's fill
---@field label FontString
---@field count FontString

--- The groups the rail is currently listing: every group in the category, or the ones the query
--- admits.
---@return SpotlightsAuraSpellGroup[]
local function VisibleGroups()
	local groups = Private.AuraSpells.Groups(ActiveFeature())

	if query == "" then
		return groups
	end

	local matches = {}

	for i = 1, #groups do
		if Private.AuraSpells.GroupMatches(groups[i], query) then
			matches[#matches + 1] = groups[i]
		end
	end

	return matches
end

--- Corrects the selection against what the rail is actually listing, and answers with it.
---
--- Two things move it without the user having clicked anything: a category change, whose pool may not
--- have the selected class at all, and a search that filters it out. Both leave the pane beside the
--- rail describing a group with no row to point at it, so the first visible group takes over.
---@param visible SpotlightsAuraSpellGroup[]
---@return SpotlightsAuraSpellGroup?
local function ResolveSelection(visible)
	for i = 1, #visible do
		if visible[i].key == selectedKey then
			return visible[i]
		end
	end

	local first = visible[1]

	selectedKey = first and first.key or nil

	return first
end

--- One pooled rail row: a class name, the count of what is on inside it, and the accent saying it is
--- the selected one.
---
--- Pooled for the reason every list in this addon is: fourteen frames rebuilt whenever a letter is
--- typed into the search box would be fourteen new frames per keystroke, and frames cannot be
--- destroyed.
---@param list Frame
---@param rows SpotlightsAuraRailRow[]
---@param index integer
---@return SpotlightsAuraRailRow
local function AcquireRow(list, rows, index)
	local row = rows[index]

	if row then
		return row
	end

	row = CreateFrame("Button", nil, list) --[[@as SpotlightsAuraRailRow]]

	row:SetHeight(ROW_HEIGHT)

	row.accent = row:CreateTexture(nil, "BACKGROUND")
	row.accent:SetAllPoints(row)
	row.accent:SetColorTexture(1, 1, 1, ACCENT_ALPHA)
	row.accent:Hide()

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")

	highlight:SetAllPoints(row)
	highlight:SetColorTexture(1, 1, 1, HIGHLIGHT_ALPHA)

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.count:SetPoint("RIGHT", row, "RIGHT", -ROW_INSET, 0)
	row.count:SetJustifyH("RIGHT")

	--- Anchored at both ends, the right one against the count rather than the row: a class name is as
	--- long as its translation made it, and one that ran under its own count would read as a wrong
	--- number. Truncated instead, which the count opposite it makes recoverable.
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row, "LEFT", ROW_INSET, 0)
	row.label:SetPoint("RIGHT", row.count, "LEFT", -COUNT_GAP, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	rows[index] = row

	return row
end

--- The scrolling list of groups.
---
--- Rows are configured in `Refresh` and anchored in `Layout`, which is the kit's own split: what a row
--- says depends on the database, and where it sits depends on a width this node is not handed until
--- afterwards.
---@param page Frame
---@return SpotlightsNode
local function BuildGroupList(page)
	local list = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	---@type SpotlightsAuraRailRow[]
	local rows = {}

	---@type SpotlightsAuraSpellGroup[]
	local visible = {}

	function list:Refresh()
		local L = Private.L.Settings
		local featureKey = ActiveFeature()

		visible = VisibleGroups()

		local selected = ResolveSelection(visible)

		for i = 1, #visible do
			local group = visible[i]
			local row = AcquireRow(list, rows, i)
			local enabled, total = Private.AuraSpells.Counts(featureKey, group)

			row.label:SetText(group.heading)
			row.label:SetTextColor(group.r, group.g, group.b)
			row.count:SetText(string.format(L.AuraGroupCount, enabled, total))
			row.accent:SetShown(selected ~= nil and group.key == selected.key)

			-- Rebound on every pass rather than captured once, because the rows are pooled: a handler
			-- closed over the group this frame stood for last time would select the wrong one.
			row:SetScript("OnClick", function()
				if selectedKey == group.key then
					return
				end

				selectedKey = group.key

				-- The pane beside the rail is about the selected group, so the click is a re-read of the
				-- sub-tab rather than anything of its own. The accent rides along with it.
				Private.Options.Refresh()
			end)

			row:Show()
		end

		for i = #visible + 1, #rows do
			rows[i]:Hide()
		end
	end

	function list:Layout(width)
		self:SetWidth(width)

		local offset = 0

		for i = 1, #visible do
			local row = rows[i]

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)

			offset = offset + ROW_HEIGHT
		end

		-- The scroll pane above this reads the returned height as its extent, so a filtered list shortens
		-- the bar rather than leaving empty space under the last row.
		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return list
end

--- The search box over the rail.
---
--- `SearchBoxTemplate` ships the magnifier, the clear button and the instruction text, and its own
--- `OnTextChanged` is what keeps those in step -- so this hooks that script rather than replacing it.
---@param page Frame
---@return SpotlightsNode
local function BuildSearch(page)
	local node = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local box = CreateFrame("EditBox", nil, node, "SearchBoxTemplate")

	box:SetPoint("LEFT", node, "LEFT", SEARCH_INSET, 0)
	box:SetHeight(SEARCH_HEIGHT)

	searchBox = box

	box:HookScript("OnTextChanged", function(self)
		local text = self:GetText():lower()

		-- Compared against what is stored rather than acted on unconditionally: the script fires for a
		-- `SetText` as well as for a keystroke, and re-typing a letter in a different case is the same
		-- filter.
		if text == query then
			return
		end

		query = text

		-- The whole sub-tab, not just the list: the filter can take the selected group off the rail, and
		-- what the pane beside it describes follows the selection.
		Private.Options.Refresh()
	end)

	function node:Refresh() end

	function node:Layout(width)
		self:SetSize(width, SEARCH_HEIGHT)
		box:SetWidth(math.max(width - SEARCH_INSET, 1))

		return SEARCH_HEIGHT
	end

	return node
end

--- Restores the category's tracked list, after asking.
---
--- Confirmed rather than immediate, as both other resets on this tab are: it discards a set of toggles
--- the user may have spent a while on, and a stray click on the button under the rail is the accident a
--- confirmation exists to catch.
local function ConfirmReset()
	local L = Private.L.Settings

	-- Registered at click time rather than at load: the localisation table is filled by now, and the
	-- category named in the prompt is whichever the strip has selected at the click rather than
	-- whichever it had when this tab was built.
	StaticPopupDialogs[RESET_POPUP] = {
		text = string.format(L.AuraResetSpellsPrompt, ActiveName()),
		button1 = L.AuraResetConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Private.AuraSpells.Reset(ActiveFeature())

			-- Every count on the rail has just changed, and the pane lists the spells behind them.
			Private.Options.Refresh()
		end,
	}

	StaticPopup_Show(RESET_POPUP)
end

--- The rail: the search box, the groups, and the reset under them.
---
--- Hidden whole for a category with no tracked list. Prescience and Shifting Sands watch one spell
--- each, so there is nothing to list and nothing to search -- and `Split` gives the pane the rail's
--- width back rather than leaving it beside an empty column.
---@param page Frame
---@param height number what the sub-tab has to spend on it
---@return SpotlightsNode
local function BuildRail(page, height)
	local listHeight = math.max(height - SEARCH_HEIGHT - Private.Controls.RowHeight - RAIL_GAP * 2,
		MIN_LIST_HEIGHT)

	local rail = Private.Node.Column(page, {
		BuildSearch(page),
		Private.Node.ScrollPane(page, BuildGroupList(page), listHeight),
		Private.Controls.ActionButton(page, Private.L.Settings.AuraReset, ConfirmReset, true),
	}, RAIL_GAP)

	local Refresh = rail.Refresh

	function rail:Refresh()
		local shown = Private.AuraSpells.HasSpells(ActiveFeature())

		self:SetShown(shown)

		if shown then
			Refresh(self)
		end
	end

	return rail
end

--- What the pane shows until issue 10 fills it: the group the rail has selected, so that a click on a
--- row is visible in something other than the accent.
---@param page Frame
---@return SpotlightsNode
local function BuildPane(page)
	return Private.Node.Column(page, {
		Private.Controls.SubHeading(page, function()
			local group = Private.AuraSpells.Group(ActiveFeature(), selectedKey)

			-- The category's own name where there is no group to name: a category with no tracked list
			-- has no rail beside this, and "nothing selected" would be a stranger answer than the one
			-- thing that is true.
			return group and group.heading or ActiveName()
		end),
	})
end

--- Empties the search box, which is what makes the filter belong to the visit rather than to the panel.
---
--- Called when the tab goes off screen, on the same grounds the Appearance sub-tab resets its sections:
--- a query left behind hides most of the rail, and a user returning to a tab they left unfiltered would
--- have to work out why before they could work out anything else.
---
--- The box drives the filter through its own `OnTextChanged`, so emptying the text is the whole of it:
--- nothing has to remember to reset the query beside it.
function Private.AuraTracked.ResetSearch()
	if searchBox then
		searchBox:SetText("")
	end
end

--- The sub-tab.
---@param page Frame
---@param GetFeature fun(): SpotlightsAuraFeatureKey which category the strip has selected
---@param GetName fun(): string its localised name, for the reset prompt
---@return SpotlightsNode
function Private.AuraTracked.Build(page, GetFeature, GetName)
	ActiveFeature = GetFeature
	ActiveName = GetName

	local height = math.max(page:GetHeight() - Private.Node.SubTabHeight - CHROME_RESERVE,
		MIN_RAIL_HEIGHT)

	local rail = BuildRail(page, height)

	--- The rail is the leading side, which is what `Split`'s `leftWidth` is for -- and it refreshes
	--- first, which the pane relies on: the rail is what corrects the selection the pane then names.
	return Private.Node.Split(page, rail, BuildPane(page), { leftWidth = RAIL_WIDTH })
end
