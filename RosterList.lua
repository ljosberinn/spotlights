---@type string, Spotlights
local _, Private = ...

---@class SpotlightsRosterList
Private.RosterList = {}

local ROW_HEIGHT = 22
local BUTTON_WIDTH = 24

--- Base icon size. `scale` grows the texture from its centre without touching the button's size or
--- hit area.
local ICON_SIZE = 18

--- Headings are taller than their rows to give prominence via spacing in a flat same-height list.
local HEADING_HEIGHT = 30

local FONTS = {
	heading = "GameFontNormal",
}

local HEIGHTS = {
	heading = HEADING_HEIGHT,
}

--- Assignment path (c): the current raid with toggles, plus configured slots with reordering and
--- spacer controls.
---
--- Unlike other tabs, this one's contents are not a fixed set of controls -- the raid changes
--- underneath it. So it is a *single* widget that rebuilds its own rows on `Refresh`, keeping the
--- panel's build-once/refresh-many contract intact.
---
--- No model code of its own: every action calls the same `Private.Registry` API the slash commands
--- do, so all three assignment front-ends produce identical database state.

--- One pooled action button: a `Button` frame with text, icon and highlight children built in
--- `AcquireRow`. Named rather than a bare `Button` so those children carry their own types.
---@class SpotlightsRosterButton : Button
---@field text FontString the label, shown only when the action has no icon
---@field icon Texture the atlas or file icon, hidden on a text-only action
---@field highlight Texture the hover tint, sized to the icon

---@class SpotlightsRosterRow : Frame
---@field label FontString
---@field divider Texture a rule above a heading, hidden on every other row
---@field buttons SpotlightsRosterButton[]
---@field slotIndex integer? which slot this row currently stands for, nil unless it is a slot row
---@field dragGuid string? the player this row can be dragged as, nil unless it is a raid member row
---@field dropSection SpotlightsRowSection? which block a drop here lands in

--- Which block of the list a row belongs to, for the drag path. `"slots"` accepts a player;
--- `"members"` accepts a slot, which removes it.
---@alias SpotlightsRowSection "slots" | "members"

--- What a row is for the drag path. Named rather than inlined because it is threaded through three
--- functions and every field is optional.
---@class SpotlightsRowTarget
---@field slot integer? a specific configured slot: draggable, and a position to insert at
---@field guid string? a raid member who can be dragged onto the grid
---@field section SpotlightsRowSection? the block this row sits in

---@alias SpotlightsRowStyle "heading" | nil

--- Class colour for `text`, or `text` unchanged when there is no class to colour it with.
---@param guid string?
---@param text string
---@return string
local function ClassColored(guid, text)
	local class = guid and Private.Roster.GetClass(guid)
	local color = class and C_ClassColor.GetClassColor(class)

	return color and color:WrapTextInColorCode(text) or text
end

---@type SpotlightsRosterRow[]
local rows = {}

--- Rows are pooled and reused. A raid of forty rebuilt on every roster event would otherwise create
--- forty frames per event, and frames cannot be destroyed.
---@param parent Frame
---@param index integer
---@return SpotlightsRosterRow
local function AcquireRow(parent, index)
	local row = rows[index]

	if row then
		return row
	end

	row = CreateFrame("Frame", nil, parent)

	-- A row must accept mouse input to be draggable; its buttons sit on top, so this does not steal
	-- their clicks.
	row:EnableMouse(true)

	-- Assignment path (b): a raid member row drags a player onto the grid; a slot row drags itself
	-- to a new position. Resolved by the getter, because a pooled frame is a different row after each
	-- rebuild.
	Private.DragAssign.Enable(row, function()
		if row.dragGuid then
			return { guid = row.dragGuid }
		end

		if row.slotIndex then
			return { slot = row.slotIndex }
		end

		return nil
	end)

	-- A rule along the top edge, shown only on headings, to make the list look sectioned.
	row.divider = row:CreateTexture(nil, "ARTWORK")
	row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.divider:SetHeight(1)
	row.divider:SetColorTexture(1, 1, 1, 0.2)
	row.divider:Hide()

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
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
		-- Anchored to the base icon size rather than tracking the icon, so a scaled icon does not
		-- drag the hover tint out to its enlarged bounds.
		button.highlight:SetPoint("CENTER")
		button.highlight:SetSize(ICON_SIZE, ICON_SIZE)
		button.highlight:SetColorTexture(1, 1, 1, 0.18)
		button:Hide()

		row.buttons[i] = button
	end

	rows[index] = row

	return row
end

--- Configures one pooled row: a label and up to three right-aligned buttons.
---
--- Buttons are anchored to the right edge, so `actions[1]` is the rightmost. The list is passed whole
--- so a row that needs two buttons hides the third without the caller tracking which ones it used.
---@param row SpotlightsRosterRow
---@param text string
---@param actions { label: string, atlas: string?, texture: integer?, scale: number?, onClick: fun() }[]
---@param target SpotlightsRowTarget? this row's role in the drag path
---@param style SpotlightsRowStyle
local function Configure(row, text, actions, target, style)
	row.slotIndex = target and target.slot
	row.dragGuid = target and target.guid
	row.dropSection = target and target.section

	-- Set every time rather than only on change: rows are pooled, so a frame that is a heading now
	-- was a member row a rebuild ago and would keep that font.
	row.label:SetFontObject(FONTS[style] or "GameFontHighlightSmall")
	row.label:SetText(text)
	row.divider:SetShown(style == "heading")

	row:SetHeight(HEIGHTS[style] or ROW_HEIGHT)

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

			-- Set every time: buttons are pooled, so one that drew a scaled icon last rebuild would
			-- keep that size. Centre-anchored, so a scale overflows the button without changing its
			-- footprint.
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

	-- Stops a long cross-realm name running under the buttons.
	row.label:SetPoint("RIGHT", row, "RIGHT", -(#actions * (BUTTON_WIDTH + 2)) - 4, 0)
end

--- The scroll frame the rows are inside. Needed as a clipping test, not for layout — see below.
---@type Frame?
local viewport

--- What a release inside the panel would land on: a specific slot, and/or a block of the list.
---
--- **A whole block is a target, not only its rows.** With no slots configured there are no slot rows
--- to aim at, so a drop anywhere in that block -- heading, "add a spacer" row, or the space its rows
--- will occupy -- means append, the only thing it can mean.
---
--- **Clipped rows are excluded explicitly**, which `IsCursorOver` cannot do alone. A scroll frame
--- clips children when it *draws* them, but their rectangles are unchanged -- a row scrolled above
--- the viewport still reports a real position that can land under the tab strip. Without the viewport
--- test, dropping on a tab could assign to an off-screen row.
---
--- Rows past the end of the current list are hidden rather than destroyed, and `IsCursorOver` tests
--- visibility, so a stale row from a longer list cannot be dropped on either.
---@return integer? slot, SpotlightsRowSection? section
function Private.RosterList.TargetUnderCursor()
	if viewport and not Private.Utils.IsCursorOver(viewport) then
		return nil, nil
	end

	for i = 1, #rows do
		local row = rows[i]

		if row.dropSection and Private.Utils.IsCursorOver(row) then
			return row.slotIndex, row.dropSection
		end
	end

	return nil, nil
end

---@param content Frame
---@return SpotlightsWidget[]
function Private.RosterList.Build(content)
	local L = Private.L.Settings

	local list = CreateFrame("Frame", nil, content) --[[@as SpotlightsWidget]]

	-- `content` is the scroll child, so its parent is the frame that does the clipping. Captured here
	-- so the assumption is written down in one place.
	viewport = content:GetParent() --[[@as Frame]]

	--- The drag gesture help text.
	---
	--- A FontString on the list rather than a `CreateText` widget stacked above it, because this
	--- widget sets its own height from its row count and the panel's scroll range is that height. A
	--- sibling widget would leave the two disagreeing by however tall this wraps to.
	---
	--- Width taken from `content` (which has an explicit `SetWidth`) rather than `list` (whose width
	--- comes from anchors and is not resolved yet). `GetStringHeight` below needs a real width to
	--- wrap against.
	local help = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

	help:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -2)
	help:SetWidth(content:GetWidth() - 8)
	help:SetJustifyH("LEFT")
	help:SetSpacing(2)
	help:SetText(L.RosterHelp)

	--- Rebuilds every row from the current roster and slot list.
	---
	--- Rebuilt wholesale rather than diffed. The lists are at most forty and twenty rows, this runs
	--- only when the panel is open and something changed, and a diff would need to track identity
	--- across a reorder -- the one operation this tab exists to perform.
	function list:Refresh()
		local used = 0

		-- Rows start below the help text, which is inside this widget's own height.
		local offset = help:GetStringHeight() + 8

		---@param text string
		---@param actions { label: string, atlas: string?, texture: integer?, scale: number?, onClick: fun() }[]
		---@param target SpotlightsRowTarget?
		---@param style SpotlightsRowStyle
		local function AddRow(text, actions, target, style)
			used = used + 1

			local row = AcquireRow(list, used)

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -offset)
			row:Show()

			Configure(row, text, actions, target, style)

			-- Read back rather than recomputed, so a heading's height and the next row's offset cannot
			-- drift apart.
			offset = offset + row:GetHeight()
		end

		---@param text string
		---@param style SpotlightsRowStyle
		---@param section SpotlightsRowSection? which block a drop on this heading lands in
		local function AddHeading(text, style, section)
			AddRow(text, {}, section and { section = section } or nil, style)
		end

		local slots = Private.Registry.GetSlots()

		AddHeading(L.SlotsHeader, "heading", "slots")

		if slots then
			for i = 1, #slots do
				local slot = slots[i]
				local index = i

				local blank = slot.kind == "blank"
				local label = blank and L.BlankSlot or (slot.name or L.UnknownSlot)

				-- Coloured by the slot's own player: the GUID is the input because a slot holds the
				-- roster's exact spelling, and there is no name-to-class lookup that isn't a second
				-- guess at the same answer.
				label = blank and label or ClassColored(slot.guid, label)

				AddRow(string.format("%d. %s", i, label), {
					-- Rightmost first. Remove, then down, then up.
					{
						label = L.RemoveShort,
						atlas = "RedButton-Exit",
						onClick = function()
							Private.Registry.Unassign(index)
							list:Refresh()
						end,
					},
					{
						label = L.DownShort,
						texture = 136472,
						scale = 1.5,
						onClick = function()
							Private.Registry.Move(index, index + 1)
							list:Refresh()
						end,
					},
					{
						label = L.UpShort,
						texture = 136476,
						scale = 1.5,
						onClick = function()
							Private.Registry.Move(index, index - 1)
							list:Refresh()
						end,
					},
				}, { slot = index, section = "slots" })
			end
		end

		AddRow(L.AddSpacer, {
			{
				label = L.PlusShort,
				texture = 130838,
				onClick = function()
					Private.Registry.SetBlank(nil)
					list:Refresh()
				end,
			},
		}, { section = "slots" })

		AddHeading(L.RaidHeader, "heading", "members")

		local members = Private.Roster.List()

		-- Everyone not already in the grid, keeping the alphabetical order `Roster.List` produced.
		--
		-- Anyone spotlighted is left out rather than listed under a subheading: the configured slots
		-- above already are that list, with the same names, colour and a remove button. Listing them
		-- twice would make every assignment visibly change two places.
		---@type { guid: string, name: string }[]
		local available = {}

		for i = 1, #members do
			local member = members[i]

			if not Private.Registry.SlotOf(member.guid) then
				available[#available + 1] = member
			end
		end

		if #available == 0 then
			-- Still a drop target: dragging a slot here removes it, which must keep working when there
			-- is nobody left to list. The two empty states say which one this is.
			AddRow(#members == 0 and L.NotInRaid or L.AllSpotlighted, {}, { section = "members" })
		end

		--- One raid member row: the drag source for adding a player.
		---
		--- `+` still appends (the fast path when the cell does not matter); dragging is what puts
		--- someone in a *particular* cell.
		---@param member { guid: string, name: string }
		local function AddMember(member)
			-- Class colour and nothing else -- a second colour would compete with the class being
			-- scanned for.
			AddRow(ClassColored(member.guid, member.name), {
				{
					label = L.PlusShort,
					texture = 130838,
					onClick = function()
						Private.Registry.AssignByGuid(member.guid)
						list:Refresh()
					end,
				},
			}, { guid = member.guid, section = "members" })
		end

		for i = 1, #available do
			AddMember(available[i])
		end

		for i = used + 1, #rows do
			rows[i]:Hide()
		end

		-- This widget's height is not knowable until its rows exist, and the scroll child's height
		-- gives the scrollbar its range. Set here rather than by the panel's Stack pass, which runs
		-- once while this changes on every roster event.
		list:SetHeight(offset)

		-- The panel owns the scroll child's height: it is the sum of every widget on the tab and this
		-- is only one of them.
		Private.Settings.Relayout()
	end

	-- The roster list is the one tab that goes stale on its own; everything else changes only when
	-- the user changes it.
	Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
		if list:IsVisible() then
			list:Refresh()
		end
	end)

	return { list }
end
