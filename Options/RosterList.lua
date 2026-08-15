---@type string, Spotlights
local _, Private = ...

---@class SpotlightsRosterList
Private.RosterList = {}

local ROW_HEIGHT = 22
local BUTTON_WIDTH = 24

--- Base size. `scale` grows the texture from its centre without touching the button's size or hit area.
local ICON_SIZE = 18

--- Headings are taller than their rows to give prominence via spacing in a flat same-height list.
local HEADING_HEIGHT = 30

local ROW_INSET = 4
local LEAD_GAP = 4

--- Two digits and the dot after them, at this row height.
local POSITION_WIDTH = 20

--- The dot is a plain square because the class accent in this panel is a colour, not art; the role icon is
--- Blizzard's tiny atlas, drawn at 14 in their own lists.
local DOT_SIZE = 8
local ROLE_SIZE = 14

--- The three `UnitGroupRolesAssigned` can answer with, as Blizzard's party frames pick them
--- (`PartyMemberFrame.lua`'s `UpdateAssignedRoles`).
local ROLE_ATLASES = {
	TANK = "roleicon-tiny-tank",
	HEALER = "roleicon-tiny-healer",
	DAMAGER = "roleicon-tiny-dps",
}

local FONTS = {
	heading = "GameFontNormal",
}

local HEIGHTS = {
	heading = HEADING_HEIGHT,
}

--- The pooled rows the Roster tab's two lists are built from, and the drag path that lands on them.
---
--- Its own file rather than part of `Options/Roster.lua`, because `Private.DragAssign` asks what is under
--- the cursor without knowing which list answered, and both lists share one row frame so a reorder and an
--- assignment are the same gesture.

--- One pooled action button, with text, icon and highlight children built in `AcquireRow`.
---@class SpotlightsRosterButton : Button
---@field text FontString the label, shown only when the action has no icon
---@field icon Texture the atlas or file icon, hidden on a text-only action
---@field highlight Texture the hover tint, sized to the icon

---@class SpotlightsRosterRow : Frame
---@field label FontString
---@field position FontString the slot number, hidden on a row that does not stand for one
---@field dot Texture the class colour, hidden where there is no class to show
---@field role Texture the assigned role, hidden for anyone not currently in the group
---@field divider Texture a rule above a heading, hidden on every other row
---@field highlight Texture the hover wash, hidden on a heading
---@field buttons SpotlightsRosterButton[]
---@field slotIndex integer? which slot this row currently stands for, nil unless it is a slot row
---@field dragGuid string? the player this row can be dragged as, nil unless it is a raid member row
---@field dropSection SpotlightsRowSection? which block a drop here lands in

--- Which block of the list a row belongs to, for the drag path. `"slots"` accepts a player;
--- `"members"` accepts a slot, which removes it.
---@alias SpotlightsRowSection "slots" | "members"

--- What a row is for the drag path.
---@class SpotlightsRowTarget
---@field slot integer? a specific configured slot: draggable, and a position to insert at
---@field guid string? a raid member who can be dragged onto the grid
---@field section SpotlightsRowSection? the block this row sits in

---@alias SpotlightsRowStyle "heading" | nil

--- Everything a row draws for one pass.
---
--- `numbered` and `player` are the list's shape rather than the row's contents: they reserve the leading
--- columns whether or not *this* row fills them, so a spacer's label starts where a player's does.
---@class SpotlightsRosterRowSpec
---@field text string
---@field actions { label: string, atlas: string?, texture: integer?, scale: number?, onClick: fun() }[]
---@field position integer? the number this row shows at its leading edge
---@field guid string? whose class dot and role icon it wears
---@field numbered boolean? this list reserves the leading number column
---@field player boolean? this list reserves the class dot and the role icon
---@field target SpotlightsRowTarget? this row's role in the drag path
---@field style SpotlightsRowStyle

--- Published so a list laying its own rows out does not restate the stride.
Private.RosterList.RowHeight = ROW_HEIGHT

--- The class colour for a GUID, or nil when there is no class behind it to colour with.
---@param guid string?
---@return colorRGB?
local function ClassColor(guid)
	local class = guid and Private.Roster.GetClass(guid)

	return class and C_ClassColor.GetClassColor(class) or nil
end

--- Class colour for `text`, or `text` unchanged when there is no class to colour it with.
---@param guid string?
---@param text string
---@return string
local function ClassColored(guid, text)
	local color = ClassColor(guid)

	return color and color:WrapTextInColorCode(text) or text
end

--- Rows are pooled because frames cannot be destroyed and a raid of forty is rebuilt on every roster event.
--- The pool is the caller's, so the drag path's scan of one list cannot cross into the other.
---@param parent Frame
---@param rows SpotlightsRosterRow[]
---@param index integer
---@return SpotlightsRosterRow
function Private.RosterList.AcquireRow(parent, rows, index)
	local row = rows[index]

	if row then
		return row
	end

	row = CreateFrame("Frame", nil, parent)

	-- A row must accept mouse input to be draggable; its buttons sit on top, so this does not steal their
	-- clicks.
	row:EnableMouse(true)

	-- An Unrostered row drags a player onto the grid; a Spotlighted row drags itself to a new position.
	-- Resolved by the getter, because a pooled frame is a different row after each rebuild.
	Private.DragAssign.Enable(row, function()
		if row.dragGuid then
			return { guid = row.dragGuid }
		end

		if row.slotIndex then
			return { slot = row.slotIndex }
		end

		return nil
	end)

	--- A `HIGHLIGHT` texture is drawn only while the frame is under the cursor, so the row stays a `Frame`:
	--- as a `Button` it would take clicks its own buttons sit on top of.
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, Private.Controls.HighlightAlpha)

	-- A rule along the top edge, shown only on headings, to make the list look sectioned.
	row.divider = row:CreateTexture(nil, "ARTWORK")
	row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.divider:SetHeight(1)
	row.divider:SetColorTexture(1, 1, 1, 0.2)
	row.divider:Hide()

	--- Right-aligned inside its column, so a one- and a two-digit row agree on where the dot begins.
	row.position = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.position:SetPoint("LEFT", row, "LEFT", ROW_INSET, 0)
	row.position:SetWidth(POSITION_WIDTH - LEAD_GAP)
	row.position:SetJustifyH("RIGHT")
	row.position:Hide()

	--- A fixed column rather than the colour of the name, so the class can be scanned down the list.
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(DOT_SIZE, DOT_SIZE)
	row.dot:Hide()

	row.role = row:CreateTexture(nil, "ARTWORK")
	row.role:SetSize(ROLE_SIZE, ROLE_SIZE)
	row.role:Hide()

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetJustifyH("LEFT")

	---@type SpotlightsRosterButton[]
	row.buttons = {}

	for i = 1, 3 do
		local button = CreateFrame("Button", nil, row) --[[@as SpotlightsRosterButton]]

		button:SetSize(BUTTON_WIDTH, ROW_HEIGHT - 4)
		button:SetPoint("RIGHT", row, "RIGHT", -((i - 1) * (BUTTON_WIDTH + 2)), 0)

		button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		button.text:SetPoint("CENTER")

		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetPoint("CENTER")
		button.icon:SetSize(ICON_SIZE, ICON_SIZE)
		button.icon:Hide()

		button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
		-- The base icon size rather than the icon's, so a scaled icon does not drag the tint out with it.
		button.highlight:SetPoint("CENTER")
		button.highlight:SetSize(ICON_SIZE, ICON_SIZE)
		button.highlight:SetColorTexture(1, 1, 1, 0.18)
		button:Hide()

		row.buttons[i] = button
	end

	rows[index] = row

	return row
end

--- Configures one pooled row: its leading columns, a label, and up to three right-aligned buttons, with
--- `actions[1]` the rightmost.
---
--- Every field is written on every pass, because a frame that is a heading now was a member row a rebuild
--- ago and would otherwise keep that font, number and colour.
---@param row SpotlightsRosterRow
---@param spec SpotlightsRosterRowSpec
function Private.RosterList.ConfigureRow(row, spec)
	local target = spec.target
	local actions = spec.actions

	row.slotIndex = target and target.slot
	row.dragGuid = target and target.guid
	row.dropSection = target and target.section

	row.label:SetFontObject(FONTS[spec.style] or "GameFontHighlightSmall")
	row.label:SetText(spec.text)
	row.divider:SetShown(spec.style == "heading")

	-- A heading is nothing to drag, drop or click, so it does not answer the cursor.
	row.highlight:SetShown(spec.style ~= "heading")

	row:SetHeight(HEIGHTS[spec.style] or ROW_HEIGHT)

	local lead = ROW_INSET

	if spec.numbered then
		row.position:SetShown(spec.position ~= nil)
		row.position:SetText(spec.position and tostring(spec.position) or "")

		lead = lead + POSITION_WIDTH
	else
		row.position:Hide()
	end

	if spec.player then
		local color = ClassColor(spec.guid)
		local role = spec.guid and Private.Roster.GetRole(spec.guid)
		local atlas = role and ROLE_ATLASES[role]

		row.dot:ClearAllPoints()
		row.dot:SetPoint("LEFT", row, "LEFT", lead, 0)
		row.dot:SetShown(color ~= nil)

		if color then
			row.dot:SetColorTexture(color.r, color.g, color.b)
		end

		row.role:SetShown(atlas ~= nil)

		if atlas then
			row.role:SetAtlas(atlas)
		end

		lead = lead + DOT_SIZE + LEAD_GAP
	else
		row.dot:Hide()
		row.role:Hide()
	end

	for i = 1, #row.buttons do
		local button = row.buttons[i]
		local action = actions[i]

		if action then
			local hasIcon = action.atlas or action.texture

			button.text:SetText(hasIcon and "" or action.label)

			if action.atlas then
				button.icon:SetAtlas(action.atlas)
				button.icon:Show()
			elseif action.texture then
				button.icon:SetTexture(action.texture)
				button.icon:Show()
			else
				button.icon:Hide()
			end

			-- Set every time: a pooled button that drew a scaled icon last rebuild would keep that size.
			local size = ICON_SIZE * (action.scale or 1)
			button.icon:SetSize(size, size)

			button:SetScript("OnClick", action.onClick)
			button:Show()
		else
			button.text:SetText("")
			button.icon:Hide()
			button:SetScript("OnClick", nil)
			button:Hide()
		end
	end

	--- Where the label may run to, so a long cross-realm name stops short of the buttons and of the role
	--- icon, which sits inside that reserved edge rather than in the leading columns.
	local trail = #actions * (BUTTON_WIDTH + 2) + ROW_INSET

	if spec.player then
		row.role:ClearAllPoints()
		row.role:SetPoint("RIGHT", row, "RIGHT", -trail, 0)

		trail = trail + ROLE_SIZE + LEAD_GAP
	end

	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row, "LEFT", lead, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -trail, 0)
end

--- One list's rows, as the drag path sees them.
---
--- `section` is what a drop inside the viewport but *not* on a row means. **A whole block is a target,
--- not only its rows**: with no slots configured there are no slot rows to aim at, so a drop anywhere
--- in that pane means append, the only thing it can mean.
---@class SpotlightsRosterRowSet
---@field viewport Frame? what clips the rows, and the block-level target
---@field section SpotlightsRowSection?
---@field rows SpotlightsRosterRow[]

---@type SpotlightsRosterRowSet[]
local rowSets = {}

--- Makes a list's rows droppable. Registered once per list and never removed: the lists live as long as the
--- panel does, and a hidden set answers nothing because `IsCursorOver` tests visibility.
---@param set SpotlightsRosterRowSet
function Private.RosterList.RegisterRowSet(set)
	rowSets[#rowSets + 1] = set
end

--- What a release inside the panel would land on: a specific slot, and/or a block of one of its lists.
---
--- **Clipped rows are excluded by the viewport test**, which `IsCursorOver` cannot do alone: a scroll frame
--- clips children when it *draws* them, so a row scrolled out of view still reports a real position that
--- can land under the tab strip. Stale rows past the end of the list are hidden, which `IsCursorOver` does
--- catch.
---@return integer? slot, SpotlightsRowSection? section
function Private.RosterList.TargetUnderCursor()
	for i = 1, #rowSets do
		local set = rowSets[i]

		if not set.viewport or Private.Utils.IsCursorOver(set.viewport) then
			for j = 1, #set.rows do
				local row = set.rows[j]

				if row.dropSection and Private.Utils.IsCursorOver(row) then
					return row.slotIndex, row.dropSection
				end
			end

			-- No row, but inside the pane: whatever that pane as a whole accepts.
			if set.section then
				return nil, set.section
			end
		end
	end

	return nil, nil
end

--- The label a configured slot shows, and the GUID whose class and role go with it -- the GUID rather than
--- the name, since a name-to-class lookup is a second guess at an answer the slot already holds.
---@param slot SpotlightsSlot
---@return string label, string? guid
function Private.RosterList.SlotDisplay(slot)
	local L = Private.L.Settings

	if slot.kind == "blank" then
		return L.BlankSlot, nil
	end

	return slot.name or L.UnknownSlot, slot.guid
end

--- Whether the list offers a role, against the set the user picked.
---
--- **A member with no role is always offered**, because `GetRole` answers nil for a group that has had no
--- role check and hiding on that would empty the pane for a whole raid. Which is also why the dropdown has
--- no "no role" entry. A missing set offers everything, for a database older than the field.
---@param roles table<string, boolean>?
---@param role string?
---@return boolean
local function Offers(roles, role)
	if not role or not roles then
		return true
	end

	return roles[role] == true
end

--- Everyone in the group whose role the list offers and who is not already in the grid, keeping the
--- alphabetical order `Roster.List` produced.
---
--- The third return is how many members the *filter* leaves, spotlighted or not, which is what separates an
--- empty pane's three causes -- without it a group of tanks and healers reports that everyone is
--- spotlighted.
---@return { guid: string, name: string }[] available, integer members, integer offered
function Private.RosterList.Available()
	local members = Private.Roster.List()
	local layout = Private.Layout.GetConfig()
	local roles = layout and layout.unrosteredRoles
	local available = {}
	local offered = 0

	for i = 1, #members do
		local member = members[i]

		if Offers(roles, Private.Roster.GetRole(member.guid)) then
			offered = offered + 1

			if not Private.Registry.SlotOf(member.guid) then
				available[#available + 1] = member
			end
		end
	end

	return available, #members, offered
end
