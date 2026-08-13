---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraTracked
Private.AuraTracked = {}

--- The Auras tab's Tracked sub-tab: which spells the selected category watches.
---
--- Two panes. The rail on the left lists the category's spells by class, with a count of how many of each
--- are switched on; the pane beside it is that group -- its spells, one row each, with the bulk switches
--- for the whole of what is showing.
---
--- Which category all of this is about lives in `Options/Auras.lua`, on the strip along the bottom of
--- the window, and reaches this file as an accessor rather than a copy -- exactly as it reaches the
--- Appearance sub-tab beside this one. What that category *contains* is `Options/AuraSpells.lua`'s
--- answer: this file draws groups and counts without knowing that two of the five categories share one
--- pool and two others have no spells at all.

--- The rail's width, as the design specifies it: 196 of the content rectangle's 748.
local RAIL_WIDTH = 196

--- One class row. Shorter than a control row: fourteen rows at the kit's 26 read as a ladder rather
--- than as a list.
local ROW_HEIGHT = 22

--- What a row keeps clear at each end, and between a long class name and the count it must not reach.
local ROW_INSET = 4
local COUNT_GAP = 6

--- The selected row's fill, and the hover tint over it.
---
--- Both `SetColorTexture`, since the design's accent is a colour rather than art, and the selected one
--- is roughly twice the hover so that hovering the selected row still reads as hovering something.
local ACCENT_ALPHA = 0.12
local HIGHLIGHT_ALPHA = Private.Controls.HighlightAlpha

--- `InputBoxVisualTemplate`'s own height, and how far its left cap is drawn outside the box
--- (`InputBoxTemplates.xml`). The box is inset by the overhang rather than sized to it, so the art
--- lands on the rail's edge instead of five pixels past it.
local SEARCH_HEIGHT = 20
local SEARCH_INSET = 5

--- Between the search box, the list and the reset button under them, and between the pane's own three
--- bands.
local RAIL_GAP = 6

--- A spell row, which is two lines: the name, and the spell ID under it. Taller than a rail row for
--- that reason, and the icon is sized to both lines rather than to either.
local SPELL_ROW_HEIGHT = 32
local SPELL_ICON_SIZE = 24
local SPELL_TEXT_GAP = 6

--- What a row keeps at its trailing edge for the toggle, and beyond it for the remove button a custom
--- entry gets. The remove width is reserved on every row rather than only where it is used, so the
--- toggles stay in one column as the rail moves between a class group and the user's own.
local CHECK_SIZE = 24
local REMOVE_WIDTH = 20

--- The exit atlas is drawn inside its button rather than filling it, so the target stays comfortable
--- while the glyph stays the size of the one in the roster's own lists.
local REMOVE_ICON_SIZE = 16
local REMOVE_HIGHLIGHT_ALPHA = 0.18

--- The buttons this pane builds for itself: the two bulk switches in its header, and Add under the
--- custom list. The height is `Controls`' own button height, which is not published -- these are the
--- only buttons in the panel not built by that kit, and matching it is what keeps the header from
--- sitting proud of the reset button across the split.
---
--- The bulk buttons are sized to their labels, since "Enable All" is a phrase of a different length in
--- every locale and a fixed width would either clip one or leave the English pair floating.
local BUTTON_HEIGHT = 22
local BULK_TEXT_PADDING = 20
local BULK_GAP = 4

--- The add-spell row: the box, the Add button, and the preview of what is currently typed. The box
--- holds at most nine digits, which is more than any spell ID has needed.
local INPUT_WIDTH = 70
local INPUT_GAP = 14
local ADD_WIDTH = 52
local ADD_GAP = 8
local PREVIEW_GAP = 10
local PREVIEW_ICON_SIZE = 20
local MAX_ID_DIGITS = 9

--- How long the typed ID is left alone before it is looked up.
---
--- A spell ID is typed a digit at a time and most prefixes name nothing, so the preview would otherwise
--- flicker through four wrong answers on the way to the right one.
local LOOKUP_DELAY = 0.35

--- What this sub-tab's chrome costs its own height: the gap under the Auras tab's sub-tab strip. Both
--- sides get everything else, so the reset button and the add-spell row end up on the window's bottom
--- edge rather than at a guess at how many rows there "usually" are.
local CHROME_RESERVE = 6

--- Floors for the two sides and for the scrolling list inside each, in case the window is ever shorter
--- than this tab's chrome costs -- better a cramped list than a negative height Blizzard errors on.
local MIN_RAIL_HEIGHT = 120
local MIN_LIST_HEIGHT = 40

--- Shared with the Appearance sub-tab deliberately: the dialog is registered at click time by whichever
--- button was clicked, and a second key would stack a second identical prompt.
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

--- The group that key names, resolved once per pass by the pane and read by everything inside it.
---
--- Held rather than looked up per node because a lookup rebuilds the category's group list, and the
--- header, the rows, the note and the add row would each pay for one. Written in the pane's own `Refresh`,
--- which runs after the rail's -- the rail is what corrects `selectedKey`, so resolving any earlier would
--- name a group the rail is about to move off.
---@type SpotlightsAuraSpellGroup?
local selectedGroup

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

	return Private.Node.OnlyWhen(Private.Node.Column(page, {
		BuildSearch(page),
		Private.Node.ScrollPane(page, BuildGroupList(page), listHeight),
		Private.Controls.ActionButton(page, Private.L.Settings.AuraReset, ConfirmReset, true),
	}, RAIL_GAP), function()
		return Private.AuraSpells.HasSpells(ActiveFeature())
	end)
end

--- The spells of the selected group the search box admits, which is what every part of the pane is about
--- -- the rows it draws and the set its bulk buttons act on, which is the same set by construction.
---@return integer[]
local function VisibleSpells()
	if not selectedGroup then
		return {}
	end

	return Private.AuraSpells.MatchingSpells(selectedGroup, query)
end

--- What a spell row shows, given an ID the client may not have cached yet.
---
--- A missing name is not an error and not a permanently unknown spell: `C_Spell.GetSpellName` answers nil
--- until the client has the data and fills it in afterwards, so the ID stands in for the name and the next
--- pass picks up the real one. An ID that is genuinely not a spell keeps showing as its own number.
---
--- The texture is a **file ID** when the spell has one and a path when it does not, which is why the
--- annotation admits both: `SetTexture` takes either.
---@param spellID integer
---@return string label, string meta, string|integer texture
local function SpellDisplay(spellID)
	local name = C_Spell.GetSpellName(spellID)

	return name or tostring(spellID),
		tostring(spellID),
		C_Spell.GetSpellTexture(spellID) or QUESTION_MARK_ICON
end

--- The client's own tooltip for a spell, anchored to whatever the cursor is actually on.
---
--- `ANCHOR_RIGHT` so the tooltip stands outside the list rather than over the rows under the cursor.
---
--- No `Show` and no guard against an ID the client has nothing for: `SetSpellByID` shows the tooltip
--- when there is data and hides it when there is not, which is the empty-frame case already answered.
---@param owner Frame
---@param spellID integer?
local function ShowSpellTooltip(owner, spellID)
	if not spellID then
		return
	end

	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(spellID)
end

--- Drops the tooltip when the frame it belongs to goes away under the cursor, which is the case
--- `OnLeave` does not answer: the pane scrolling, the group changing, the panel closing.
---
--- Owner-checked rather than unconditional, since by then something else may have taken the tooltip.
---@param self Frame
local function HideSpellTooltip(self)
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

--- One spell row. Its parts are named here rather than left implicit for the reason the rail's are: a
--- pooled frame stands for a different spell after every pass, and every one of them is re-pointed on
--- each.
---@class SpotlightsAuraSpellRow : Button
---@field icon Texture
---@field label FontString
---@field meta FontString
---@field check CheckButton
---@field remove Button
---@field spellID integer? which spell the row currently stands for

--- One pooled spell row: the icon, the name over its ID, the toggle, and the remove button a custom entry
--- gets.
---
--- A `Button` rather than a frame, so the whole row is the toggle: the checkbox at its far end is a small
--- target beside a name that reads as the thing being switched on. The checkbox and the remove button sit
--- on top and keep their own clicks.
---@param list Frame
---@param rows SpotlightsAuraSpellRow[]
---@param index integer
---@return SpotlightsAuraSpellRow
local function AcquireSpellRow(list, rows, index)
	local row = rows[index]

	if row then
		return row
	end

	row = CreateFrame("Button", nil, list) --[[@as SpotlightsAuraSpellRow]]

	row:SetHeight(SPELL_ROW_HEIGHT)

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")

	highlight:SetAllPoints(row)
	highlight:SetColorTexture(1, 1, 1, HIGHLIGHT_ALPHA)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
	row.icon:SetPoint("LEFT", row, "LEFT", ROW_INSET, 0)

	-- The border every icon file ships with, cropped off, exactly as the aura displays crop theirs.
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(REMOVE_WIDTH, SPELL_ROW_HEIGHT - 2)
	row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	--- The same red exit atlas the roster's remove buttons use rather than an "X", so the gesture that
	--- means "remove this" looks the same in both lists. The icon carries the meaning, so no text is set;
	--- a hover tint sized to the icon stands in for the button template's own highlight.
	local removeIcon = row.remove:CreateTexture(nil, "ARTWORK")

	removeIcon:SetPoint("CENTER")
	removeIcon:SetSize(REMOVE_ICON_SIZE, REMOVE_ICON_SIZE)
	removeIcon:SetAtlas("RedButton-Exit")

	local removeHighlight = row.remove:CreateTexture(nil, "HIGHLIGHT")

	removeHighlight:SetPoint("CENTER")
	removeHighlight:SetSize(REMOVE_ICON_SIZE, REMOVE_ICON_SIZE)
	removeHighlight:SetColorTexture(1, 1, 1, REMOVE_HIGHLIGHT_ALPHA)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(CHECK_SIZE, CHECK_SIZE)
	row.check:SetPoint("RIGHT", row, "RIGHT", -REMOVE_WIDTH, 0)

	--- Both lines are anchored at each end, the right one against the toggle rather than the row: a spell
	--- name is as long as the client's translation made it, and one that ran under its own checkbox would
	--- read as a row that cannot be switched off.
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", SPELL_TEXT_GAP, 0)
	row.label:SetPoint("RIGHT", row.check, "LEFT", -SPELL_TEXT_GAP, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.meta = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.meta:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -1)
	row.meta:SetPoint("RIGHT", row.check, "LEFT", -SPELL_TEXT_GAP, 0)
	row.meta:SetJustifyH("LEFT")
	row.meta:SetWordWrap(false)

	--- Read off the row rather than closed over, which is what lets these be set once here while the
	--- click handlers are rebound every pass: a captured ID would be the previous spell's.
	local function ShowRowTooltip()
		ShowSpellTooltip(row, row.spellID)
	end

	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)

	--- The toggle and the remove button sit on top of the row, so the cursor crossing onto either one
	--- leaves the row. Both re-show the row's own tooltip, anchored to the row, so sliding across the
	--- row keeps one tooltip in one place instead of dropping it at the checkbox's edge.
	row.check:SetScript("OnEnter", ShowRowTooltip)
	row.check:SetScript("OnLeave", GameTooltip_Hide)
	row.remove:SetScript("OnEnter", ShowRowTooltip)
	row.remove:SetScript("OnLeave", GameTooltip_Hide)

	row:SetScript("OnHide", HideSpellTooltip)

	rows[index] = row

	return row
end

--- The scrolling list of the selected group's spells.
---@param page Frame
---@return SpotlightsNode
local function BuildSpellList(page)
	local list = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	---@type SpotlightsAuraSpellRow[]
	local rows = {}

	---@type integer[]
	local visible = {}

	function list:Refresh()
		local featureKey = ActiveFeature()
		local custom = selectedGroup ~= nil and selectedGroup.custom or false

		visible = VisibleSpells()

		for i = 1, #visible do
			local spellID = visible[i]
			local row = AcquireSpellRow(list, rows, i)
			local label, meta, texture = SpellDisplay(spellID)

			row.spellID = spellID
			row.label:SetText(label)
			row.meta:SetText(meta)
			row.icon:SetTexture(texture)
			row.check:SetChecked(Private.AuraSpells.IsEnabled(featureKey, spellID, custom))
			row.remove:SetShown(custom)

			-- The row can change spell under a cursor that never moved -- removing a custom entry pulls
			-- the next one up into the row being hovered -- and no `OnEnter` fires for a frame the cursor
			-- has not left. Re-shown here so the tooltip is never the previous spell's.
			if GameTooltip:IsShown() and GameTooltip:GetOwner() == row then
				ShowSpellTooltip(row, spellID)
			end

			-- Rebound on every pass rather than captured once, because the rows are pooled: a handler
			-- closed over the spell this frame stood for last time would toggle the wrong one.
			local function Toggle(enabled)
				Private.AuraSpells.SetEnabled(featureKey, spellID, enabled, custom)

				-- The rail's count for this group has just changed, so the pass belongs to the sub-tab
				-- rather than to the row.
				Private.Options.Refresh()
			end

			row:SetScript("OnClick", function()
				Toggle(not row.check:GetChecked())
			end)

			row.check:SetScript("OnClick", function(check)
				Toggle(check:GetChecked() and true or false)
			end)

			row.remove:SetScript("OnClick", function()
				Private.AuraSpells.RemoveCustom(featureKey, spellID)

				-- A row has gone, which is a height as well as a repaint -- and `Refresh` is what the new
				-- height is derived from, so the whole pass rather than a relayout.
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

			offset = offset + SPELL_ROW_HEIGHT
		end

		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return list
end

--- The pane's header: which group is being listed, how much of it is on, and the two bulk switches.
---
--- The count is the whole group's, as the rail's is, rather than the filtered set's -- it is the same
--- number about the same group, and two counts disagreeing across a divider would read as one of them
--- being wrong. What the *buttons* act on is the filtered set, which is what the rows under them show.
---@param page Frame
---@return SpotlightsNode
local function BuildPaneHeader(page)
	local L = Private.L.Settings
	local node = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local title = node:CreateFontString(nil, "ARTWORK", "GameFontNormal")

	title:SetPoint("LEFT", node, "LEFT", 0, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

	local count = node:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

	count:SetPoint("LEFT", title, "RIGHT", COUNT_GAP, 0)
	count:SetJustifyH("LEFT")

	---@param enabled boolean
	local function SetAll(enabled)
		if not selectedGroup then
			return
		end

		Private.AuraSpells.SetSpellsEnabled(ActiveFeature(), VisibleSpells(), enabled,
			selectedGroup.custom)
		Private.Options.Refresh()
	end

	local disableAll = CreateFrame("Button", nil, node, "UIPanelButtonTemplate")

	disableAll:SetHeight(BUTTON_HEIGHT)
	disableAll:SetPoint("RIGHT", node, "RIGHT", 0, 0)
	disableAll:SetText(L.AuraDisableAll)

	disableAll:SetScript("OnClick", function()
		SetAll(false)
	end)

	local enableAll = CreateFrame("Button", nil, node, "UIPanelButtonTemplate")

	enableAll:SetHeight(BUTTON_HEIGHT)
	enableAll:SetPoint("RIGHT", disableAll, "LEFT", -BULK_GAP, 0)
	enableAll:SetText(L.AuraEnableAll)

	enableAll:SetScript("OnClick", function()
		SetAll(true)
	end)

	function node:Refresh()
		if not selectedGroup then
			return
		end

		local enabled, total = Private.AuraSpells.Counts(ActiveFeature(), selectedGroup)

		title:SetText(selectedGroup.heading)
		title:SetTextColor(selectedGroup.r, selectedGroup.g, selectedGroup.b)
		count:SetText(string.format(Private.L.Settings.AuraGroupCount, enabled, total))
	end

	function node:Layout(width)
		self:SetSize(width, Private.Controls.RowHeight)

		enableAll:SetWidth(enableAll:GetTextWidth() + BULK_TEXT_PADDING)
		disableAll:SetWidth(disableAll:GetTextWidth() + BULK_TEXT_PADDING)

		--- Sized to the name it holds so the count sits against it, and capped at what the buttons leave
		--- so a long group name truncates instead of running under them. One pixel over the measured
		--- width: a font string set to exactly its own is rounded down into an ellipsis.
		local room = math.max(width - enableAll:GetWidth() - disableAll:GetWidth() - BULK_GAP
			- count:GetStringWidth() - COUNT_GAP, 1)

		title:SetWidth(math.max(math.min(title:GetStringWidth() + 1, room), 1))

		return Private.Controls.RowHeight
	end

	return node
end

--- The add-spell row under the custom group's list: a numeric box, an Add button, and a preview of
--- whatever is currently typed.
---
--- The preview is the point. A spell ID is not something anyone can proofread, so the only way to know
--- that 466772 is Doom Winds and not a typo is to be shown the icon and name before committing -- and to
--- be shown nothing when the number names no spell, which is the same signal.
---
--- A rejected ID leaves the box as it was. Clearing it would swallow the failure -- the box would empty,
--- the list would not change, and nothing would say why -- and the two ways to be rejected are both
--- visible from here: an ID that names nothing has no preview, and a duplicate is already in the list
--- above.
---@param page Frame
---@return SpotlightsNode
local function BuildAddSpell(page)
	local L = Private.L.Settings
	local node = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local caption = node:CreateFontString(nil, "ARTWORK", "GameFontNormal")

	caption:SetPoint("LEFT", node, "LEFT", 0, 0)
	caption:SetJustifyH("LEFT")
	caption:SetWordWrap(false)
	caption:SetText(L.AuraCustomSpellID)

	local input = CreateFrame("EditBox", nil, node, "InputBoxTemplate")

	input:SetSize(INPUT_WIDTH, Private.Controls.RowHeight - 6)
	input:SetAutoFocus(false)

	-- Digits only, the whole of the validation this needs: a spell ID is a positive integer, and refusing
	-- the keystroke is a clearer answer than accepting text and rejecting it on Add.
	input:SetNumeric(true)
	input:SetMaxLetters(MAX_ID_DIGITS)

	local add = CreateFrame("Button", nil, node, "UIPanelButtonTemplate")

	add:SetSize(ADD_WIDTH, BUTTON_HEIGHT)
	add:SetPoint("LEFT", input, "RIGHT", ADD_GAP, 0)
	add:SetText(L.AuraCustomAdd)

	--- Beside the box rather than under it, which is the difference between a preview and an interruption:
	--- a row that grew when a preview appeared would push the answer to what had just been typed down the
	--- pane. Filling space the row already occupies cannot move anything.
	local icon = node:CreateTexture(nil, "ARTWORK")

	icon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
	icon:SetPoint("LEFT", add, "RIGHT", PREVIEW_GAP, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local preview = node:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	preview:SetPoint("LEFT", icon, "RIGHT", SPELL_TEXT_GAP, 0)
	preview:SetPoint("RIGHT", node, "RIGHT", 0, 0)
	preview:SetJustifyH("LEFT")
	preview:SetWordWrap(false)

	--- What the preview currently shows, which is what its hover is a tooltip for. An upvalue rather
	--- than a field on the frame: there is one preview, not a pool of them.
	---@type integer?
	local previewSpellID

	--- What carries the preview's hover. The two regions above are a texture and a font string, neither
	--- of which takes a script, so the scripts ride on a frame over them.
	---
	--- Sized in `ShowPreview` to what is actually drawn rather than anchored to the row's trailing edge:
	--- the name runs to whatever length the client's translation made it, and the empty space past a short
	--- one is not part of what the cursor is pointing at.
	local hover = CreateFrame("Frame", nil, node)

	hover:SetPoint("LEFT", icon, "LEFT", 0, 0)
	hover:SetHeight(PREVIEW_ICON_SIZE)
	hover:Hide()

	-- Motion rather than mouse: the preview answers the cursor being over it and nothing else, so a
	-- click still reaches whatever is behind it.
	hover:SetMouseMotionEnabled(true)

	hover:SetScript("OnEnter", function()
		ShowSpellTooltip(hover, previewSpellID)
	end)

	hover:SetScript("OnLeave", GameTooltip_Hide)
	hover:SetScript("OnHide", HideSpellTooltip)

	---@type FunctionContainer?
	local timer

	--- Shows what the typed ID names, or nothing. Both regions are children of the row, so every route
	--- that hides the row -- the group changing, the tab changing, the panel closing -- hides these too.
	local function ShowPreview()
		local spellID = tonumber(input:GetText())
		local name = spellID and spellID > 0 and C_Spell.GetSpellName(spellID)
		local found = type(name) == "string"

		icon:SetShown(found)
		preview:SetShown(found)
		hover:SetShown(found)

		previewSpellID = found and spellID or nil

		if found and spellID then
			local label, _, texture = SpellDisplay(spellID)

			preview:SetText(label)
			icon:SetTexture(texture)

			-- After the text, since the width is the text's: the icon, the gap the name sits past, and
			-- the name itself.
			hover:SetWidth(PREVIEW_ICON_SIZE + SPELL_TEXT_GAP + preview:GetStringWidth())
		end
	end

	input:SetScript("OnTextChanged", function()
		if timer then
			timer:Cancel()
		end

		timer = C_Timer.NewTimer(LOOKUP_DELAY, ShowPreview)
	end)

	local function Commit()
		local spellID = tonumber(input:GetText())

		if not spellID or spellID <= 0 or not Private.AuraSpells.AddCustom(ActiveFeature(), spellID) then
			return
		end

		input:SetText("")
		input:ClearFocus()
		ShowPreview()

		-- The list above has gained a row and the rail's count with it, so the whole pass rather than a
		-- repaint of this one.
		Private.Options.Refresh()
	end

	add:SetScript("OnClick", Commit)
	input:SetScript("OnEnterPressed", Commit)

	-- Escape gives the box back rather than trapping the user in it, since the panel itself is in
	-- `UISpecialFrames` and Escape would otherwise be swallowed.
	input:SetScript("OnEscapePressed", function()
		input:ClearFocus()
	end)

	function node:Refresh()
		ShowPreview()
	end

	function node:Layout(width)
		self:SetSize(width, Private.Controls.RowHeight)

		--- Against the caption's *text* rather than at a label column, which is what every control row
		--- spends its width on so the controls below line up. This row has a preview to fit instead, and
		--- "Spell ID" is a third of that column. `InputBoxTemplate` insets its own left edge, hence the
		--- extra offset.
		input:ClearAllPoints()
		input:SetPoint("LEFT", caption, "LEFT", caption:GetStringWidth() + INPUT_GAP, 0)

		return Private.Controls.RowHeight
	end

	return node
end

--- The pane: the header, the spells under it, and -- for the user's own group -- what adds one.
---
--- There are two ways to have no group to be about: a category with no tracked list at all, and a search
--- that admitted none of the groups there are. Both put a note where the list would be rather than
--- leaving the pane blank, since a blank pane says only that something is missing.
---@param page Frame
---@param height number what the sub-tab has to spend on it
---@return SpotlightsNode
local function BuildPane(page, height)
	local L = Private.L.Settings

	--- The header and the add row are pinned; the list gets what is left. Reserved whether or not the add
	--- row is showing, so the list is the same height in every group and switching to the custom one does
	--- not resize what is under the cursor.
	local listHeight = math.max(height - Private.Controls.RowHeight * 2 - RAIL_GAP * 2, MIN_LIST_HEIGHT)

	local function HasGroup()
		return selectedGroup ~= nil
	end

	--- The note the custom group carries, in the scroll pane rather than pinned beside the box it is
	--- about: it is two or three lines of prose depending on the locale, and a band whose height is a
	--- translation's business cannot be reserved without guessing.
	local note = Private.Node.OnlyWhen(Private.Controls.Paragraph(page, function()
		return ActiveFeature() == "defensiveAuras" and L.AuraCustomDefensivesNote
			or L.AuraCustomCooldownsNote
	end), function()
		return selectedGroup ~= nil and selectedGroup.custom == true
	end)

	local pane = Private.Node.Column(page, {
		Private.Node.OnlyWhen(Private.Controls.Paragraph(page, function()
			return Private.AuraSpells.HasSpells(ActiveFeature())
				and L.AuraNoSpellMatches
				or string.format(L.AuraNoTrackedSpells, ActiveName())
		end), function()
			return selectedGroup == nil
		end),

		Private.Node.OnlyWhen(BuildPaneHeader(page), HasGroup),
		Private.Node.OnlyWhen(
			Private.Node.ScrollPane(page, Private.Node.Column(page, { note, BuildSpellList(page) }),
				listHeight), HasGroup),
		Private.Node.OnlyWhen(BuildAddSpell(page), function()
			return selectedGroup ~= nil and selectedGroup.custom == true
		end),
	}, RAIL_GAP)

	local Refresh = pane.Refresh

	--- Resolves the selection the rail has just corrected, before anything inside reads it. Everything in
	--- the pane is about that one group, so it is resolved once here rather than looked up per node.
	function pane:Refresh()
		selectedGroup = Private.AuraSpells.Group(ActiveFeature(), selectedKey)

		Refresh(self)
	end

	return pane
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

	--- The rail is the leading side, which is what `Split`'s `leftWidth` is for -- and it refreshes
	--- first, which the pane relies on: the rail is what corrects the selection the pane then resolves.
	return Private.Node.Split(page, BuildRail(page, height), BuildPane(page, height),
		{ leftWidth = RAIL_WIDTH })
end
