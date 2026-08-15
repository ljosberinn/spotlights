---@type string, Spotlights
local _, Private = ...

---@class SpotlightsDragAssign
Private.DragAssign = {}

--- Pick a row up out of the Roster tab and drop it on a grid cell: a raid member is added there, a
--- configured slot is reordered.
---
--- The direction is forced, not chosen. `OnDragStart` must be set on the frame the drag begins on, and
--- the frames a player is visible on belong to Blizzard or other addons, so the source has to be
--- something of ours. See docs/notes/DragAssignment.md.

--- Exactly one of `guid` and `slot` is set.
---@class SpotlightsDrag
---@field guid string? a raid member being added to the grid
---@field slot integer? a configured slot being reordered
---@field label string what the hint calls it

---@type SpotlightsDrag?
local dragging

---@class SpotlightsDragHint : Frame
---@field text FontString

---@type SpotlightsDragHint?
local hint

--- Matches the roster list's own labels, so a dragged slot reads the same as the row it came from.
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

--- The panel is checked first and exclusively: a cursor over its background must not act on a cell
--- underneath, whichever way the user's `position.strata` orders the two.
---@return integer? slot, SpotlightsRowSection? section
local function Target()
	if Private.Options.IsCursorOver() then
		return Private.RosterList.TargetUnderCursor()
	end

	local cell = Private.SlotHeader.CellUnderCursor()

	if cell then
		-- Cell index is not slot index: with `allowGaps` off, cells pack present players, so cell 2
		-- can be showing slot 5.
		return Private.Registry.SlotOfCell(cell), nil
	end

	-- A preview needs no such lookup: it is filled from `slots[i]`, so its index already is a slot.
	return Private.Preview.CellUnderCursor(), nil
end

--- Every branch names both subject and outcome, including the ones whose outcome is nothing -- a drag
--- that resolves to nothing is otherwise indistinguishable from one that worked.
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

	-- Redundant today, since no Unrostered row carries a position. Kept so a row that gains one cannot
	-- license an insert.
	if slot and section ~= "members" then
		return string.format(L.HintAdd, drag.label, slot)
	end

	if section == "slots" then
		return string.format(L.HintAppend, drag.label)
	end

	return string.format(L.HintDrag, drag.label)
end

--- On `UIParent` rather than anything of ours: it must draw over the options panel, the mover overlay
--- and the spotlights at once.
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

		-- Sized to the text; a box fixed to the longest string has a visible empty tail on the others.
		self:SetWidth(self.text:GetStringWidth() + 12)

		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()

		self:ClearAllPoints()
		PixelUtil.SetPoint(self, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale - 24)
	end)

	return hint
end

--- Out of combat only, even though `Registry` would queue the mutation safely: a drag that began
--- before a pull and ended after it applies seconds later with no visible connection to the drop.
---@return boolean acted
function Private.DragAssign.Drop()
	local drag = dragging

	dragging = nil
	GetHint():Hide()

	if not drag or InCombatLockdown() then
		return false
	end

	local slot, section = Target()

	-- A drop with no slot is still actionable inside a pane: that is how the first slot is added and
	-- the last one removed.
	if not slot and not section then
		return false
	end

	local ok, reason

	if drag.slot then
		if section == "members" then
			ok, reason = Private.Registry.Unassign(drag.slot)
		elseif not slot or slot == drag.slot then
			-- Dropped on itself is what a click that crossed the drag threshold looks like.
			return false
		else
			ok, reason = Private.Registry.Move(drag.slot, slot)
		end
	elseif Private.Registry.SlotOf(drag.guid) then
		-- Silent because the hint has been saying so.
		return false
	elseif section == "members" then
		-- `AssignByGuid` with no index appends, so without this a release back into the pane the player
		-- was dragged from would quietly add them to the end of the grid.
		return false
	else
		-- A nil slot appends, which is what a drop in the Spotlighted pane but not on a row means.
		ok, reason = Private.Registry.AssignByGuid(drag.guid, slot)
	end

	if not ok and reason then
		Private.Utils.Print(reason)
	end

	-- Unconditional: a rejected drop leaves the list correct already, but a repaint costs nothing.
	Private.Options.Refresh()

	return ok
end

--- Makes `frame` a drag source. `getDrag` is a function rather than a value because the roster list's
--- rows are pooled: capturing the payload would make a reordered list drag whatever used to be there.
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
			-- `Registry.AssignByGuid`'s own `fromRoster` test, run early: a player known only to the
			-- client's name cache cannot be assigned, so refuse to pick them up.
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
