---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraTracked
Private.AuraTracked = {}

--- The Auras tab's Tracked sub-tab: which spells the selected category watches. The rail on the left
--- lists the category's spells by class with a count of how many are on; the pane beside it is that
--- group.
---
--- Which category reaches this file as an accessor rather than a copy, as it does the Appearance sub-tab.
--- What that category *contains* is `Options/AuraSpells.lua`'s answer: this file draws groups and counts
--- without knowing that two categories share one pool, two have no spells at all, and one is the user's
--- own list with no classes to rail.

--- 196 of the content rectangle's 863.
local RAIL_WIDTH = 196

--- Shorter than a control row: fourteen rows at the kit's 26 read as a ladder rather than a list.
local ROW_HEIGHT = 22

--- What a row keeps clear at each end, and between a long class name and the count it must not reach.
local ROW_INSET = 4
local COUNT_GAP = 6

--- The selected row's fill is roughly twice the hover tint, so hovering the selected row still reads as
--- hovering something.
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

--- A spell row is two lines, the name and the spell ID under it, so it is taller than a rail row and the
--- icon is sized to both lines rather than either.
local SPELL_ROW_HEIGHT = 32
local SPELL_ICON_SIZE = 24
local SPELL_TEXT_GAP = 6

--- The remove width is reserved on every row rather than only where it is used, so the toggles stay in
--- one column as the rail moves between a class group and the user's own.
local CHECK_SIZE = 24
local REMOVE_WIDTH = 20

--- The exit atlas is drawn inside its button rather than filling it, so the target stays comfortable
--- while the glyph matches the roster's own lists.
local REMOVE_ICON_SIZE = 16
local REMOVE_HIGHLIGHT_ALPHA = 0.18

--- `Controls`' own button height, which is not published: these are the only buttons in the panel not
--- built by that kit, and matching it keeps the header from sitting proud of the reset button across the
--- split. The bulk buttons are sized to their labels, since a fixed width would clip one locale or leave
--- another floating.
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

--- How long the typed ID is left alone before it is looked up: an ID is typed a digit at a time and most
--- prefixes name nothing, so the preview would otherwise flicker through wrong answers on the way.
local LOOKUP_DELAY = 0.35

--- The gap under the Auras tab's sub-tab strip. Both sides get everything else, so the reset button and
--- the add-spell row end up on the window's bottom edge.
local CHROME_RESERVE = 6

--- Floors for the two sides and the list inside each, in case the window is shorter than this tab's
--- chrome costs: better a cramped list than a negative height Blizzard errors on.
local MIN_RAIL_HEIGHT = 120
local MIN_LIST_HEIGHT = 40

--- Shared with the Appearance sub-tab deliberately: the dialog is registered at click time by whichever
--- button was clicked, and a second key would stack a second identical prompt.
local RESET_POPUP = "SPOTLIGHTS_AURA_RESET"

--- Which category the strip has selected, and its localised name for the reset prompt. Both handed in by
--- `Build`, because the strip they come from is not this file's.
---@type fun(): SpotlightsAuraFeatureKey
local ActiveFeature

---@type fun(): string
local ActiveName

--- A key rather than a group, because the groups are rebuilt per category and a held table would belong
--- to one the user has since left. Deliberately not per category either: a key that exists in both pools
--- keeps the rail where the user left it when they switch between Cooldowns and Defensives.
---@type string?
local selectedKey

--- Held rather than looked up per node, because a lookup rebuilds the category's group list and the
--- header, rows, note and add row would each pay for one. Written by the sub-tab's own `Refresh`, ahead
--- of both sides: a category with no rail has nothing else to correct `selectedKey`.
---@type SpotlightsAuraSpellGroup?
local selectedGroup

--- What has been typed in the search box, lowercased once here rather than at every comparison.
---@type string
local query = ""

--- Kept so the sub-tab can empty them on the way out. Two, because the box moves into the pane for a
--- category with no rail to put it in -- one is visible at a time, and both share `query`.
---@type EditBox[]
local searchBoxes = {}

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

--- Corrects the selection against what the rail is actually listing. Two things move it without a click:
--- a category change whose pool may not have the selected class, and a search that filters it out. Both
--- would leave the pane describing a group with no row, so the first visible one takes over.
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

--- One pooled rail row: a class name, the count of what is on inside it, and the accent marking the
--- selection. Pooled because frames cannot be destroyed, and a rebuild per keystroke in the search box
--- would be fourteen new frames per letter.
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

	-- Anchored at both ends, the right one against the count rather than the row: a class name that ran
	-- under its own count would read as a wrong number.
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row, "LEFT", ROW_INSET, 0)
	row.label:SetPoint("RIGHT", row.count, "LEFT", -COUNT_GAP, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	rows[index] = row

	return row
end

--- The scrolling list of groups. Rows are configured in `Refresh` and anchored in `Layout`, which is the
--- kit's own split: what a row says depends on the database, where it sits depends on a width this node
--- is not handed until afterwards.
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

		for i = 1, #visible do
			local group = visible[i]
			local row = AcquireRow(list, rows, i)
			local enabled, total = Private.AuraSpells.Counts(featureKey, group)

			row.label:SetText(group.heading)
			row.label:SetTextColor(group.r, group.g, group.b)
			row.count:SetText(string.format(L.AuraGroupCount, enabled, total))
			row.accent:SetShown(selectedGroup ~= nil and group.key == selectedGroup.key)

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

--- `SearchBoxTemplate`'s own `OnTextChanged` keeps its magnifier, clear button and instruction text in
--- step, so this hooks that script rather than replacing it.
---@param page Frame
---@return SpotlightsNode
local function BuildSearch(page)
	local node = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local box = CreateFrame("EditBox", nil, node, "SearchBoxTemplate")

	box:SetPoint("LEFT", node, "LEFT", SEARCH_INSET, 0)
	box:SetHeight(SEARCH_HEIGHT)

	searchBoxes[#searchBoxes + 1] = box

	box:HookScript("OnTextChanged", function(self)
		local text = self:GetText():lower()

		-- The script fires for a `SetText` as well as a keystroke, and re-typing a letter in a different
		-- case is the same filter.
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

--- Restores the category's tracked list, after asking: it discards a set of toggles the user may have
--- spent a while on, and a stray click on the button under the rail is what the confirmation catches.
local function ConfirmReset()
	local L = Private.L.Settings

	-- Registered at click time rather than at load: the localisation table is filled by now, and the
	-- category named in the prompt is whichever the strip has selected at the click.
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

--- Whether the selected category is drawn with a rail beside its pane. The reset button and the search
--- box ride along with it: the one restores shipped defaults a custom pool has none of, the other moves
--- into the pane.
---@return boolean
local function HasRail()
	return Private.AuraSpells.HasRail(ActiveFeature())
end

--- The rail: the search box, the groups, and the reset under them. Hidden whole for a category with no
--- rail, where `Split` gives the pane the rail's width back rather than leaving it beside an empty
--- column.
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
	}, RAIL_GAP), HasRail)
end

--- The spells of the selected group the search box admits: the rows the pane draws and the set its bulk
--- buttons act on, which is the same set by construction.
---@return integer[]
local function VisibleSpells()
	if not selectedGroup then
		return {}
	end

	return Private.AuraSpells.MatchingSpells(selectedGroup, query)
end

--- What a spell row shows, given an ID the client may not have cached yet. A missing name is not an
--- error: `C_Spell.GetSpellName` answers nil until the client has the data, so the ID stands in and the
--- next pass picks up the real one.
---
--- The texture is a **file ID** when the spell has one and a path when it does not, which is why the
--- annotation admits both.
---@param spellID integer
---@return string label, string meta, string|integer texture
local function SpellDisplay(spellID)
	local name = C_Spell.GetSpellName(spellID)

	return name or tostring(spellID),
		tostring(spellID),
		C_Spell.GetSpellTexture(spellID) or QUESTION_MARK_ICON
end

--- `ANCHOR_RIGHT` so the tooltip stands outside the list rather than over the rows under the cursor. No
--- `Show` and no guard against an uncached ID: `SetSpellByID` shows the tooltip when there is data and
--- hides it when there is not.
---@param owner Frame
---@param spellID integer?
local function ShowSpellTooltip(owner, spellID)
	if not spellID then
		return
	end

	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(spellID)
end

--- Drops the tooltip when the frame it belongs to goes away under the cursor, which `OnLeave` does not
--- answer: the pane scrolling, the group changing, the panel closing. Owner-checked, since by then
--- something else may have taken the tooltip.
---@param self Frame
local function HideSpellTooltip(self)
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

---@class SpotlightsAuraSpellRow : Button
---@field icon Texture
---@field label FontString
---@field meta FontString
---@field check CheckButton
---@field remove Button
---@field spellID integer? which spell the row currently stands for

--- One pooled spell row. A `Button` rather than a frame, so the whole row is the toggle: the checkbox at
--- its far end is a small target beside a name that reads as the thing being switched on. The checkbox
--- and the remove button sit on top and keep their own clicks.
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

	-- The same red exit atlas the roster's remove buttons use, so the gesture looks the same in both
	-- lists. A hover tint sized to the icon stands in for the button template's own highlight.
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

	-- Both lines anchored at each end, the right one against the toggle rather than the row: a spell name
	-- running under its own checkbox would read as a row that cannot be switched off.
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

	-- Read off the row rather than closed over, which lets these be set once while the click handlers are
	-- rebound every pass: a captured ID would be the previous spell's.
	local function ShowRowTooltip()
		ShowSpellTooltip(row, row.spellID)
	end

	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)

	-- The toggle and the remove button sit on top of the row, so crossing onto either leaves it. Both
	-- re-show the row's own tooltip, so sliding across keeps one tooltip in one place.
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
			row.check:SetChecked(Private.AuraSpells.IsEnabled(featureKey, spellID))
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
				Private.AuraSpells.SetEnabled(featureKey, spellID, enabled)

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

--- The pane's header. The count is the whole group's, as the rail's is, rather than the filtered set's:
--- two counts disagreeing across a divider would read as one of them being wrong. What the *buttons* act
--- on is the filtered set, which is what the rows under them show.
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

		Private.AuraSpells.SetSpellsEnabled(ActiveFeature(), VisibleSpells(), enabled)
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

		-- Sized to the name it holds so the count sits against it, capped at what the buttons leave. One
		-- pixel over the measured width: a font string set to exactly its own rounds down to an ellipsis.
		local room = math.max(width - enableAll:GetWidth() - disableAll:GetWidth() - BULK_GAP
			- count:GetStringWidth() - COUNT_GAP, 1)

		title:SetWidth(math.max(math.min(title:GetStringWidth() + 1, room), 1))

		return Private.Controls.RowHeight
	end

	return node
end

--- The add-spell row under the custom group's list. **The preview is the point**: a spell ID cannot be
--- proofread, so the only way to know a number is not a typo is to be shown the icon and name before
--- committing, and to be shown nothing when it names no spell.
---
--- A rejected ID leaves the box as it was. Clearing it would swallow the failure, and both ways to be
--- rejected are visible from here: an ID that names nothing has no preview, a duplicate is already in
--- the list above.
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

	-- Digits only, the whole of the validation this needs: refusing the keystroke is a clearer answer than
	-- accepting text and rejecting it on Add.
	input:SetNumeric(true)
	input:SetMaxLetters(MAX_ID_DIGITS)

	local add = CreateFrame("Button", nil, node, "UIPanelButtonTemplate")

	add:SetSize(ADD_WIDTH, BUTTON_HEIGHT)
	add:SetPoint("LEFT", input, "RIGHT", ADD_GAP, 0)
	add:SetText(L.AuraCustomAdd)

	-- Beside the box rather than under it: a row that grew when a preview appeared would push the answer
	-- to what had just been typed down the pane. Filling space the row already occupies cannot.
	local icon = node:CreateTexture(nil, "ARTWORK")

	icon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
	icon:SetPoint("LEFT", add, "RIGHT", PREVIEW_GAP, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local preview = node:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

	preview:SetPoint("LEFT", icon, "RIGHT", SPELL_TEXT_GAP, 0)
	preview:SetPoint("RIGHT", node, "RIGHT", 0, 0)
	preview:SetJustifyH("LEFT")
	preview:SetWordWrap(false)

	---@type integer?
	local previewSpellID

	-- What carries the preview's hover: the two regions above are a texture and a font string, neither of
	-- which takes a script. Sized in `ShowPreview` to what is actually drawn rather than to the row's
	-- trailing edge, since empty space past a short name is not what the cursor is pointing at.
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

	-- Shows what the typed ID names, or nothing. Both regions are children of the row, so every route that
	-- hides the row hides these too.
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

		-- Against the caption's *text* rather than at a label column, because this row has a preview to fit
		-- and "Spell ID" is a third of that column. `InputBoxTemplate` insets its own left edge, hence the
		-- extra offset.
		input:ClearAllPoints()
		input:SetPoint("LEFT", caption, "LEFT", caption:GetStringWidth() + INPUT_GAP, 0)

		return Private.Controls.RowHeight
	end

	return node
end

--- The pane: the header, the spells under it, and -- for the user's own group -- what adds one. The
--- search box joins it where there is no rail to hold one, since a custom list can grow long enough to
--- want filtering.
---
--- Two ways to have no group to be about: a category with no tracked list, and a search that admitted
--- none. Both put a note where the list would be, since a blank pane says only that something is missing.
---@param page Frame
---@param height number what the sub-tab has to spend on it
---@return SpotlightsNode
local function BuildPane(page, height)
	local L = Private.L.Settings

	-- The header and the add row are pinned; the list gets what is left. Reserved whether or not the add
	-- row is showing, so switching to the custom group does not resize what is under the cursor. Read per
	-- layout rather than once, because the search box is only the pane's for some categories.
	local function ListHeight()
		local reserved = Private.Controls.RowHeight * 2 + RAIL_GAP * 2

		if not HasRail() then
			reserved = reserved + SEARCH_HEIGHT + RAIL_GAP
		end

		return math.max(height - reserved, MIN_LIST_HEIGHT)
	end

	local function HasGroup()
		return selectedGroup ~= nil
	end

	local function IsCustomGroup()
		return selectedGroup ~= nil and selectedGroup.custom == true
	end

	-- In the scroll pane rather than pinned beside the box it is about: it is two or three lines depending
	-- on the locale, and a band whose height is a translation's business cannot be reserved.
	local note = Private.Node.OnlyWhen(Private.Controls.Paragraph(page, function()
		return L.AuraCustomNote
	end), IsCustomGroup)

	local pane = Private.Node.Column(page, {
		Private.Node.OnlyWhen(BuildSearch(page), function()
			return not HasRail()
		end),

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
				ListHeight), HasGroup),
		Private.Node.OnlyWhen(BuildAddSpell(page), IsCustomGroup),
	}, RAIL_GAP)

	return pane
end

--- Empties the search boxes, which is what makes the filter belong to the visit rather than the panel: a
--- query left behind hides most of the rail on the way back in, and one typed on the rail would otherwise
--- reach a category whose own box is empty.
---
--- A box drives the filter through its own `OnTextChanged`, so emptying the text is the whole of it.
function Private.AuraTracked.ResetSearch()
	for i = 1, #searchBoxes do
		searchBoxes[i]:SetText("")
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

	local split = Private.Node.Split(page, BuildRail(page, height), BuildPane(page, height),
		{ leftWidth = RAIL_WIDTH })

	local Refresh = split.Refresh

	-- Ahead of both sides rather than inside either, so neither depends on the other having run: the rail
	-- only paints the selection, and a category drawn without one still has it corrected.
	function split:Refresh()
		selectedGroup = ResolveSelection(VisibleGroups())

		Refresh(self)
	end

	return split
end
