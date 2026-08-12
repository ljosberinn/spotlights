---@type string, Spotlights
local _, Private = ...

---@class SpotlightsDragAssign
Private.DragAssign = {}

--- Assignment path (b): drag out of the options roster and drop on a grid cell.
---
--- **Two gestures, one mechanism.** Dragging a *raid member* adds them to the grid at the drop cell;
--- dragging a *configured slot* reorders it. Both are picked up from the Roster tab, both land on a
--- cell, and the payload decides which happened.
---
--- **The direction is forced, not chosen.** Picking a player up off a unit frame is not implementable:
--- `OnDragStart` must be set on the frame the drag begins on, and the frames a player is visible on
--- belong to Blizzard or other addons. So the source is something of ours that stands for a player,
--- and the target is the cell -- both ends frames we created.
---
--- **Where a player can be dropped** is three things:
---
--- - A live spotlight (`Private.SlotHeader.CellUnderCursor`).
--- - A preview (`Private.Preview.CellUnderCursor`), which out of a raid is the only thing on screen
---   and is what makes the grid assignable before there is a raid. It can never answer at the same
---   time as a live cell: a preview is shown exactly where a live spotlight is not.
--- - The configured-slots block (`Private.RosterList.TargetUnderCursor`) -- on a row to insert at that
---   position, anywhere else in the block to append.
---
--- **Where a slot can be dropped** is a cell or another slot row, which reorders -- or the *raid
--- members* block, which removes it. The member list is where players come from, so dragging one back
--- into it is the one place a removal gesture can point at without meaning something else.
---
--- Neither block being a target only through its rows is deliberate. With nothing configured there are
--- no cells and no slot rows, so without the *block* the add gesture could not create the first slot;
--- with no raid there are no member rows, so without the block the remove gesture would stop working.

--- What is being dragged, or nil when nothing is. Exactly one of `guid` and `slot` is set.
---@class SpotlightsDrag
---@field guid string? a raid member being added to the grid
---@field slot integer? a configured slot being reordered
---@field label string what the hint calls it

---@type SpotlightsDrag?
local dragging

--- The cursor-following label. `text` is ours, so it needs declaring.
---@class SpotlightsDragHint : Frame
---@field text FontString

---@type SpotlightsDragHint?
local hint

--- What to call a slot in the hint. Matches the roster list's own labels, so the thing being dragged
--- reads the same as the row it came from.
---@param index integer
---@return string
local function SlotLabel(index)
	local L = Private.L.Settings
	local slot = Private.Registry.GetSlots()[index]

	if not slot then
		return L.UnknownSlot
	end

	if slot.kind == "blank" then
		return L.BlankSlot
	end

	return slot.name or L.UnknownSlot
end

--- Which options window the cursor is over, or nil.
---
--- **Two panels exist until the cutover** -- the old one and the rework's -- and either can be open,
--- or both. Both are `PortraitFrameTemplate` frames at DIALOG strata created in whichever order the
--- user opened them, so where they overlap the higher frame level is the one drawn on top and the one
--- the user is pointing at. Anything else would resolve a drop to a panel the cursor is visibly not
--- over.
---@return Frame?
local function PanelUnderCursor()
	local settings = Private.Settings.IsCursorOver() and Private.Settings.GetFrame() or nil
	local options = Private.Options.IsCursorOver() and Private.Options.GetFrame() or nil

	if settings and options then
		return options:GetFrameLevel() >= settings:GetFrameLevel() and options or settings
	end

	return settings or options
end

--- Where a release here would land: a specific position, and/or a block of the roster list.
---
--- Either half can be the useful one. A `section` with no `slot` is still actionable -- appending to
--- or removing from the configured slots -- which lets both gestures work against a block with no rows
--- yet. A `slot` with no section is a cell out on the grid.
---
--- The panel is checked first and exclusively. It sits at DIALOG strata while the grid does not, so a
--- panel overlapping the grid hides it, and a cursor over the panel's background must not act on
--- whichever cell is underneath.
---@return integer? slot, SpotlightsRowSection? section
local function Target()
	local panel = PanelUnderCursor()

	if panel then
		return Private.RosterList.TargetUnderCursor(panel)
	end

	local cell = Private.SlotHeader.CellUnderCursor()

	if cell then
		-- A live cell is not necessarily its own slot. With `allowGaps` off, cells hold present
		-- players in slot order, so cell 2 can be showing slot 5 -- acting on the cell index would
		-- insert next to whoever the user did not point at.
		return Private.Registry.SlotOfCell(cell), nil
	end

	-- A preview needs no such lookup: it is filled from `slots[i]`, so its index already is a slot.
	return Private.Preview.CellUnderCursor(), nil
end

--- What the hint should say right now.
---
--- Every branch names both subject and outcome, including the ones where the outcome is nothing. A
--- drag that resolves to nothing is otherwise indistinguishable from one that worked until you look at
--- the grid, and "released an inch outside the cell" and "that player is already spotlighted" are
--- failures with completely different fixes.
---@param drag SpotlightsDrag
---@return string
local function HintText(drag)
	local L = Private.L.DragAssign
	local slot, section = Target()

	if drag.slot then
		if section == "members" then
			return string.format(L.HintRemove, drag.label)
		end

		if slot and slot ~= drag.slot then
			return string.format(L.HintMove, drag.label, slot)
		end

		return string.format(L.HintReorder, drag.label)
	end

	local occupied = Private.Registry.SlotOf(drag.guid)

	if occupied then
		return string.format(L.HintAlready, drag.label, occupied)
	end

	-- No member row carries a position, so the section test is redundant today. Written anyway,
	-- because "a slot came back" and "that slot is somewhere a player may be added" are two claims and
	-- only the second licenses an insert.
	if slot and section ~= "members" then
		return string.format(L.HintAdd, drag.label, slot)
	end

	if section == "slots" then
		return string.format(L.HintAppend, drag.label)
	end

	return string.format(L.HintDrag, drag.label)
end

--- A label that follows the cursor, reporting what releasing here would do.
---
--- On `UIParent` and parented to nothing of ours, because it must draw over the options panel, the
--- mover overlay and the spotlights at once.
---@return SpotlightsDragHint
local function GetHint()
	if hint then
		return hint
	end

	hint = CreateFrame("Frame", nil, UIParent) --[[@as SpotlightsDragHint]]
	hint:SetFrameStrata("TOOLTIP")
	hint:SetHeight(20)
	hint:Hide()

	local background = hint:CreateTexture(nil, "BACKGROUND")

	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.7)

	hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint.text:SetPoint("LEFT", hint, "LEFT", 6, 0)
	hint.text:SetJustifyH("LEFT")

	hint:SetScript("OnUpdate", function(self)
		if not dragging then
			return
		end

		self.text:SetText(HintText(dragging))

		-- Width follows the text rather than being fixed. The strings differ in length a lot, and a
		-- box sized for the longest has a visible empty tail on the others.
		self:SetWidth(self.text:GetStringWidth() + 12)

		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()

		self:ClearAllPoints()
		PixelUtil.SetPoint(self, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale - 24)
	end)

	return hint
end

--- Ends a drag, acting on the cell under the cursor if there is one.
---
--- Out of combat only. The mutation itself is combat-safe (`Registry` queues it), but a drag that
--- began before a pull and ended after it would apply a change the user made in a different situation,
--- seconds later, with no visible connection to the drop.
---@return boolean acted
function Private.DragAssign.Drop()
	local drag = dragging

	dragging = nil
	GetHint():Hide()

	if not drag or InCombatLockdown() then
		return false
	end

	local slot, section = Target()

	-- A drop with no slot is still actionable inside either block: appending to the configured slots,
	-- or removing from them. That is how the first slot gets added and the last one gets removed.
	if not slot and not section then
		return false
	end

	local ok, reason

	if drag.slot then
		if section == "members" then
			-- Dragged out of the grid and into the list of people who could be in it, the one place a
			-- removal gesture can point at without meaning anything else.
			ok, reason = Private.Registry.Unassign(drag.slot)
		elseif not slot or slot == drag.slot then
			-- Reordering needs a position, so the section alone is not enough. Dropped on itself is
			-- what a click that crossed the drag threshold looks like.
			return false
		else
			ok, reason = Private.Registry.Move(drag.slot, slot)
		end
	elseif Private.Registry.SlotOf(drag.guid) then
		-- Already in the grid, so nothing to add. Reordering is the slot row's job; doing it here too
		-- would give one outcome two gestures. The hint has been saying so, which is why this is silent.
		return false
	elseif section == "members" then
		-- The member list is where players are dragged *from*. Released back into it, a player has not
		-- been pointed at a position -- and `AssignByGuid` with no index appends, so without this the
		-- gesture would quietly add them to the end of the grid.
		return false
	else
		-- Everything left is a cell or the configured-slots block. A nil slot appends, which is what a
		-- drop in that block but not on one of its rows means.
		ok, reason = Private.Registry.AssignByGuid(drag.guid, slot)
	end

	if not ok and reason then
		Private.Utils.Print(reason)
	end

	-- The list now shows stale slot numbers, a stale available/assigned split, or both. Refreshed
	-- unconditionally: a rejected drop leaves it correct, but a repaint costs nothing. Both panels,
	-- because both can be open and each guards on being shown -- and a drop resolved against one of
	-- them changes what the other is listing.
	Private.Settings.Refresh()
	Private.Options.Refresh()

	return ok
end

--- Makes `frame` a drag source.
---
--- `getDrag` returns `{ guid = ... }` for a raid member, `{ slot = ... }` for a configured slot, or
--- nil when not draggable right now. A function rather than a value because the roster list's rows are
--- pooled: a frame stands for a given player or slot only until the list is rebuilt, and capturing it
--- would make a reordered list drag whatever used to be there.
---@param frame Frame
---@param getDrag fun(): { guid: string?, slot: integer? }?
function Private.DragAssign.Enable(frame, getDrag)
	frame:RegisterForDrag("LeftButton")

	frame:SetScript("OnDragStart", function()
		if InCombatLockdown() then
			return
		end

		local drag = getDrag()

		if not drag then
			return
		end

		if drag.slot then
			dragging = { slot = drag.slot, label = SlotLabel(drag.slot) }
		elseif drag.guid then
			-- The same `fromRoster` test `Registry.AssignByGuid` applies, run before the drag starts.
			-- A player whose name only the client's cache knows cannot be assigned at all, so the
			-- honest behaviour is to refuse to pick them up.
			local name, fromRoster = Private.Roster.GetName(drag.guid)

			if not name or not fromRoster then
				return
			end

			dragging = { guid = drag.guid, label = name }
		else
			return
		end

		GetHint():Show()
	end)

	frame:SetScript("OnDragStop", function()
		Private.DragAssign.Drop()
	end)
end
