---@type string, Spotlights
local _, Private = ...

--- The Roster tab: the grid's contents on the left, the people who could be in it on the right.
---
--- Two lists rather than the old panel's one interleaved column, which is the whole reason the tab was
--- worth redoing: those two lists are read against each other -- "who is in, who is left" -- and a
--- single column made that a scroll rather than a glance.
---
--- The presets block under the unrostered list is `Options/RosterPresets.lua`'s: it is a library with
--- its own storage and its own codec, and the only thing this file owes it is the height it takes.
---
--- Every row here is `RosterList.lua`'s pooled row, configured through the same two functions the old
--- panel configures its own with. What this file owns is the arrangement: which rows each pane holds,
--- what its buttons do, and how much height each list gets.
---
--- No model code, like every other front-end onto the slot list: each action calls the same
--- `Private.Registry` entry point the slash commands do.

--- The unrostered list's width, as the design specifies it: 250 of the content rectangle's 748.
local UNROSTERED_WIDTH = 250

--- What a checkbox spends on its caption. Both of these are sentences rather than nouns, and the kit's
--- 130 default would lose the half that says what the box does.
local CHECKBOX_LABEL_WIDTH = 280

--- Between one band of a column and the next. Tighter than the kit's control rhythm, because a heading,
--- a list and the buttons under it read as one pane rather than as three stacked things.
local PANE_GAP = 6

--- A floor for either list, in case the window is ever shorter than this tab's chrome costs -- better a
--- cramped list than a negative height Blizzard errors on.
local MIN_LIST_HEIGHT = 60

--- The icons the row buttons wear. The two arrows are file IDs rather than atlases because there is no
--- atlas pair for "up" and "down" at this size; scaled up because both files carry a wide transparent
--- margin and draw small at the row height.
local REMOVE_ATLAS = "RedButton-Exit"
local UP_TEXTURE = 136476
local DOWN_TEXTURE = 136472
local PLUS_TEXTURE = 130838
local ARROW_SCALE = 1.5

--- Shared with every other confirmation in the panel deliberately: the dialog is registered at click
--- time by whoever was clicked, and a second key would stack a second identical prompt.
local CLEAR_POPUP = "SPOTLIGHTS_ROSTER_CLEAR"

--- How often the tab may rebuild itself, in seconds.
---
--- A repaint is not what the user is waiting on -- they are reading a list that is still changing -- so
--- the interval is set by how long a stale list is tolerable rather than by what the rebuild costs.
local REFRESH_INTERVAL = 1

--- The three roles, in the order the game lists them. Both dropdowns on this tab pick from them: the
--- one narrowing the Unrostered list, and the one keeping roles out of the grid.
---
--- Labelled from the globals rather than from our own keys, which is how the default UI labels the same
--- three tokens (`LFGList.lua:3757` resolves `_G[role]`) -- eleven locales of "Tank" for free, and the
--- exact wording the rest of the interface uses. Built at load because `GlobalStrings` is filled long
--- before an addon runs.
local ROLE_CHOICES = {
	{ value = "TANK", label = TANK },
	{ value = "HEALER", label = HEALER },
	{ value = "DAMAGER", label = DAMAGER },
}

---@return SpotlightsLayoutConfig?
local function Layout()
	return Private.Layout.GetConfig()
end

--- Writes a layout field and schedules the geometry pass it invalidates.
---
--- Every layout write goes through here, including `clearOnLeave`, which invalidates nothing on screen:
--- the pass it requests is coalesced, so a redundant one costs a click.
---@param field string
---@param value any
local function SetLayoutField(field, value)
	local layout = Layout()

	if not layout then
		return
	end

	layout[field] = value

	Private.Layout.Request()
end

---@return boolean
local function GetAllowGaps()
	local layout = Layout()

	return layout and layout.allowGaps or false
end

---@param value boolean
local function SetAllowGaps(value)
	SetLayoutField("allowGaps", value)

	-- Gaps changes what each cell *holds* rather than where the cells are, so the registry has to
	-- re-resolve on top of the geometry pass. Geometry alone would leave the same names in the same
	-- cells.
	Private.Events.Request(Private.Enum.DeferralKey.Registry)
end

---@return boolean
local function GetClearOnLeave()
	local layout = Layout()

	return layout and layout.clearOnLeave or false
end

---@param value boolean
local function SetClearOnLeave(value)
	SetLayoutField("clearOnLeave", value)
end

---@param role string
---@return boolean
local function GetRoleOffered(role)
	local layout = Layout()
	local roles = layout and layout.unrosteredRoles

	return roles ~= nil and roles[role] == true
end

--- Ticks or unticks a role in the Unrostered list's filter.
---
--- Not through `SetLayoutField`, which writes a whole field: this one mutates a table inside the block,
--- and there is no geometry to invalidate either -- what the *options list* offers changes nothing about
--- where a spotlight sits or what it holds.
---
--- Stored `false` rather than removed, because the default is not empty: see `Migration.DefaultLayout`.
---
--- The tab rather than the pane, because rows come and go -- that is a height, not a repaint. The menu
--- survives it: a checkbox click responds `MenuResponse.Refresh`, and the kit's multiselect declines to
--- regenerate while its list is down.
---@param role string
---@param offered boolean
local function SetRoleOffered(role, offered)
	local layout = Layout()

	if not layout or not layout.unrosteredRoles then
		return
	end

	layout.unrosteredRoles[role] = offered

	Private.Options.Refresh()
end

---@param role string
---@return boolean
local function GetRoleRemoved(role)
	local layout = Layout()
	local roles = layout and layout.autoRemoveRoles

	return roles ~= nil and roles[role] == true
end

--- Ticks or unticks a role in the set kept out of the grid, and acts on the grid at once, so a tick
--- takes the healers already on screen out rather than waiting for the next roster event.
---
--- The removal is the registry's rather than this file's, like every other action on this tab: it is
--- a model mutation with an apply behind it, and the panel is a front-end onto the same entry points
--- the slash commands use.
---@param role string
---@param removed boolean
local function SetRoleRemoved(role, removed)
	local layout = Layout()

	if not layout or not layout.autoRemoveRoles then
		return
	end

	layout.autoRemoveRoles[role] = removed

	Private.Registry.EnforceAutoRemoveRoles()

	-- The tab: slots leave the left list and their players come back to the right one.
	Private.Options.Refresh()
end

--- Appends a spacer, which is the one slot the grid can hold that nobody is in.
local function AddSpacer()
	Private.Registry.SetBlank(nil)
	Private.Options.Refresh()
end

--- Empties the grid, after asking.
---
--- Confirmed rather than immediate, for the reason the aura resets are: it discards a list the user may
--- have spent a raid night arranging, and a stray click on a button under the list is exactly the
--- accident a confirmation exists to catch. The prompt names what goes, because "clear" alone does not
--- say that the spacers go with the players.
local function ConfirmClear()
	local L = Private.L.Settings

	-- Registered at click time rather than at load, so the localisation table is filled by now.
	StaticPopupDialogs[CLEAR_POPUP] = {
		text = L.ClearSlotsPrompt,
		button1 = L.ClearSlotsConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,

		-- Above Blizzard's own dialogs rather than under them, as every other prompt this panel raises.
		preferredIndex = 3,

		OnAccept = function()
			Private.Registry.Clear()
			Private.Options.Refresh()
		end,
	}

	StaticPopup_Show(CLEAR_POPUP)
end

--- The configured slots, one row each.
---
--- Rows are configured in `Refresh` and anchored in `Layout`, which is the kit's own split: what a row
--- says depends on the database, and where it sits depends on a width this node is not handed until
--- afterwards.
---
--- The list is rebuilt wholesale rather than diffed, as the old panel's is: it is at most twenty rows,
--- it runs only when the panel is open and something changed, and a diff would have to track identity
--- across a reorder -- the one operation this pane exists to perform.
---@param page Frame
---@param rows SpotlightsRosterRow[] the pool, owned by the caller so it can be registered for drops
---@return SpotlightsNode
local function BuildSlotList(page, rows)
	local L = Private.L.Settings
	local list = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local used = 0

	function list:Refresh()
		local slots = Private.Registry.GetSlots()

		used = #slots

		for i = 1, used do
			local index = i
			local label, guid = Private.RosterList.SlotDisplay(slots[i])
			local row = Private.RosterList.AcquireRow(list, rows, i)

			Private.RosterList.ConfigureRow(row, {
				text = label,
				position = index,
				guid = guid,
				numbered = true,
				player = true,

				-- Rightmost first. Remove, then down, then up.
				actions = {
					{
						label = L.RemoveShort,
						atlas = REMOVE_ATLAS,
						onClick = function()
							Private.Registry.Unassign(index)

							-- A row has gone, which is a height as well as a repaint, and the list
							-- beside this one has gained the player back. So the tab rather than the pane.
							Private.Options.Refresh()
						end,
					},
					{
						label = L.DownShort,
						texture = DOWN_TEXTURE,
						scale = ARROW_SCALE,
						onClick = function()
							Private.Registry.Move(index, index + 1)
							Private.Options.Refresh()
						end,
					},
					{
						label = L.UpShort,
						texture = UP_TEXTURE,
						scale = ARROW_SCALE,
						onClick = function()
							Private.Registry.Move(index, index - 1)
							Private.Options.Refresh()
						end,
					},
				},

				target = { slot = index, section = "slots" },
			})

			row:Show()
		end

		for i = used + 1, #rows do
			rows[i]:Hide()
		end
	end

	function list:Layout(width)
		self:SetWidth(width)

		local stride = Private.RosterList.RowHeight
		local offset = 0

		for i = 1, used do
			local row = rows[i]

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)

			offset = offset + stride
		end

		-- The scroll pane above this reads the returned height as its extent, so a shortened list
		-- shortens the bar rather than leaving empty space under the last row.
		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return list
end

--- The group members not already in the grid, one row each.
---
--- `+` appends, which is the fast path when the cell does not matter; dragging a row is what puts
--- someone in a *particular* cell.
---@param page Frame
---@param rows SpotlightsRosterRow[]
---@return SpotlightsNode
local function BuildMemberList(page, rows)
	local L = Private.L.Settings
	local list = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	local used = 0

	function list:Refresh()
		local available = Private.RosterList.Available()

		used = #available

		for i = 1, used do
			local member = available[i]
			local row = Private.RosterList.AcquireRow(list, rows, i)

			Private.RosterList.ConfigureRow(row, {
				text = member.name,
				guid = member.guid,
				player = true,

				actions = {
					{
						label = L.PlusShort,
						texture = PLUS_TEXTURE,
						onClick = function()
							local ok, reason = Private.Registry.AssignByGuid(member.guid)

							-- Said out loud, as the drop path says it: the button can be refused now that a
							-- role can be set to be kept out of the grid, and a `+` that does nothing at all
							-- reads as a broken button.
							if not ok and reason then
								Private.Utils.Print(reason)
							end

							-- This row goes and a slot row appears, so the tab rather than the pane.
							Private.Options.Refresh()
						end,
					},
				},

				target = { guid = member.guid, section = "members" },
			})

			row:Show()
		end

		for i = used + 1, #rows do
			rows[i]:Hide()
		end
	end

	function list:Layout(width)
		self:SetWidth(width)

		local stride = Private.RosterList.RowHeight
		local offset = 0

		for i = 1, used do
			local row = rows[i]

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)

			offset = offset + stride
		end

		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return list
end

--- One pane: a heading, then a scrolling list with a note where the list would be when it is empty.
---
--- The note is inside the scroll pane rather than pinned above it, for the reason the tracked-spells
--- note is: it is a line or three depending on the locale, and a band whose height is a translation's
--- business cannot be reserved without guessing.
---
--- The pane's rows are registered for drops here rather than by their list, because the viewport that
--- clips them belongs to the scroll pane and the block a drop lands in belongs to the pane as a whole.
---
--- A `filter` sits between the heading and the list, on the list it filters: a pane that looks short is
--- explained by the control directly above it, and the heading is the caption a labelless control would
--- otherwise need. The caller pays for its height, since only the caller knows what the column has left.
---@param page Frame
---@param heading string
---@param height number | fun(): number what the column has to spend on the list
---@param section SpotlightsRowSection what a drop in this pane but not on one of its rows means
---@param Note fun(): string what to say instead of an empty list
---@param IsEmpty fun(): boolean
---@param BuildList fun(page: Frame, rows: SpotlightsRosterRow[]): SpotlightsNode
---@param filter SpotlightsNode? a control over what the list shows, under the heading
---@return SpotlightsNode
local function BuildPane(page, heading, height, section, Note, IsEmpty, BuildList, filter)
	---@type SpotlightsRosterRow[]
	local rows = {}

	local pane = Private.Node.ScrollPane(page, Private.Node.Column(page, {
		Private.Node.OnlyWhen(Private.Controls.Paragraph(page, Note), IsEmpty),
		BuildList(page, rows),
	}), height)

	Private.RosterList.RegisterRowSet({
		viewport = pane.viewport,
		section = section,
		rows = rows,
	})

	local children = { Private.Controls.SubHeading(page, heading) }

	if filter then
		children[#children + 1] = filter
	end

	children[#children + 1] = pane

	return Private.Node.Column(page, children, PANE_GAP)
end

--- The trailing column: the unrostered list with the presets block pinned under it.
---
--- A `Column` would do this if the list could be sized last, and it cannot: a `ScrollPane` is a
--- *window*, so the list has to be told its height, and what is left for it is whatever the block
--- under it took -- a section's open state and which of its two boxes is showing, neither of which is
--- a constant this file could subtract. So the block is measured first and anchored afterwards.
--- Heights and anchors are set independently, so the order they are decided in is free.
---@param page Frame
---@param members SpotlightsNode
---@param presets SpotlightsNode
---@param SetReserved fun(height: number) hands the measured height to the list's own height function
---@return SpotlightsNode
local function BuildRightColumn(page, members, presets, SetReserved)
	local column = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	members:SetParent(column)
	presets:SetParent(column)

	function column:Refresh()
		members:Refresh()
		presets:Refresh()
	end

	function column:Layout(width)
		self:SetWidth(width)

		local reserved = presets:Layout(width)

		SetReserved(reserved)

		members:ClearAllPoints()
		members:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)

		local top = members:Layout(width) + PANE_GAP

		presets:ClearAllPoints()
		presets:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)

		local height = top + reserved

		self:SetHeight(height)

		return height
	end

	return column
end

---@param page Frame
---@return SpotlightsNode
local function BuildRoster(page)
	local L = Private.L.Settings

	--- What each column spends on something other than its list. The left one carries the two slot
	--- buttons and the three settings under its list; the right one carries its heading and the presets
	--- block, whose height is decided per pass rather than here.
	---
	--- Both are counted from the same page height, which is why the two lists do not end level: the
	--- design puts the controls under the slots, and an unrostered list cropped to match them would
	--- waste a quarter of the tab on nothing.
	local heading = Private.Controls.HeadingHeight
	local row = Private.Controls.RowHeight

	local slotsHeight = math.max(page:GetHeight() - heading - row * 5 - PANE_GAP * 6, MIN_LIST_HEIGHT)

	--- What the presets block took on this pass, written by the column below before it lays the list
	--- out. Zero until then, which is only ever the case before the first pass.
	local reserved = 0

	--- One row and one gap of this is the role filter's, which sits between the heading and the list.
	local function MembersHeight()
		return math.max(page:GetHeight() - heading - row - PANE_GAP * 3 - reserved, MIN_LIST_HEIGHT)
	end

	local slots = Private.Node.Column(page, {
		BuildPane(page, L.SpotlightedHeader, slotsHeight, "slots", function()
			return L.NoSlots
		end, function()
			return #Private.Registry.GetSlots() == 0
		end, BuildSlotList),

		Private.Controls.ActionButton(page, L.AddSpacer, AddSpacer),
		Private.Controls.ActionButton(page, L.ClearSlots, ConfirmClear, true),

		Private.Controls.Checkbox(page, L.AllowGaps, GetAllowGaps, SetAllowGaps, nil, true,
			CHECKBOX_LABEL_WIDTH),
		Private.Controls.Checkbox(page, L.ClearOnLeave, GetClearOnLeave, SetClearOnLeave, nil, true,
			CHECKBOX_LABEL_WIDTH),

		-- In the label column rather than captioned above a full-width dropdown, which the two
		-- checkboxes over it already establish: the caption reads as the third of three settings, and
		-- the column is wide enough that the dropdown still shows two role names at once.
		Private.Controls.MultiselectDropdown(page, L.AutoRemoveRoles, ROLE_CHOICES, GetRoleRemoved,
			SetRoleRemoved, CHECKBOX_LABEL_WIDTH),
	}, PANE_GAP)

	--- No label: the heading above says what the list holds, and a label column here would leave the
	--- dropdown a hundred pixels of the 250 -- the same reasoning the presets dropdown spans its column on.
	local roleFilter = Private.Controls.MultiselectDropdown(page, nil, ROLE_CHOICES, GetRoleOffered,
		SetRoleOffered)

	local members = BuildPane(page, L.UnrosteredHeader, MembersHeight, "members", function()
		local _, count, offered = Private.RosterList.Available()

		-- Three empty states, because the filter splits what used to be two: nobody to list, nobody the
		-- filter shows, or nobody left to list. Reporting the middle one as the last would tell a raid of
		-- tanks and healers that everyone is spotlighted.
		if count == 0 then
			return L.NotInGroup
		end

		return offered == 0 and L.NoOfferedRoles or L.AllSpotlighted
	end, function()
		local available = Private.RosterList.Available()

		return #available == 0
	end, BuildMemberList, roleFilter)

	--- The one tab that goes stale on its own; everything else changes only when the user changes it.
	---
	--- Two events, because a row states two things: who is in the group, and what they are. Only the
	--- first is a membership change; a role check finishing or a member picking a role fires
	--- PLAYER_ROLES_ASSIGNED and nothing else, so the role column stays blank without it.
	---
	--- Throttled rather than immediate because a raid forming fires one roster event per member, and each
	--- one rebuilds both lists whole -- the panes are deliberately not diffed.
	---
	--- Both events share one window, so a role check -- which fires both -- costs one rebuild rather than
	--- two. Two windows would allow two rebuilds a second, which is the thing being avoided.
	---
	--- Only this panel's repaint is throttled. The model scan, the grid's own enforcement and the aura
	--- side all still take the event itself, so nothing reads a roster a second stale.
	local Repaint = Private.Events.Throttled(REFRESH_INTERVAL, Private.Options.Refresh)

	--- Guarded on the page rather than on the panel, so a roster event while the user is on Appearance
	--- schedules nothing -- the tab is refreshed on selection anyway. The test wraps the throttle rather
	--- than sitting inside it for that reason; a trailing call can still land just after the page is
	--- hidden, which costs one refresh of a hidden panel.
	local function RefreshIfVisible()
		if page:IsVisible() then
			Repaint()
		end
	end

	Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", RefreshIfVisible)
	Private.Events.RegisterEvent("PLAYER_ROLES_ASSIGNED", RefreshIfVisible)

	local right = BuildRightColumn(page, members, Private.RosterPresets.Build(page), function(height)
		reserved = height
	end)

	return Private.Node.Split(page, slots, right, { rightWidth = UNROSTERED_WIDTH })
end

Private.Options.Builders.roster = BuildRoster
