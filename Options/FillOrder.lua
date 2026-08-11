---@type string, Spotlights
local _, Private = ...

---@class SpotlightsFillOrder
Private.FillOrder = {}

--- The Grid tab's fill-order preview: a schematic of where the next spotlight lands, drawn from the
--- same arithmetic the container itself places headers with (`Private.Layout.CellOf` /
--- `Private.Layout.Extent`), so the two can never disagree about what a given orientation, stride,
--- growX and growY combination produces.
---
--- A cell is one of three things: **filled** (a configured slot), **next** (where slot
--- `#slots + 1` would land, greyed), or **unused** (dashed). Every cell carries its own ordinal --
--- the pane's whole point is showing the *order* -- with kind read off opacity rather than off
--- whether a number is there at all. The rectangle shown is exactly big enough to hold the next
--- slot -- no padding row added purely to have something to dash, so a config that fills a rectangle
--- exactly shows no unused cells at all.

local Orientation = Private.Enum.Orientation
local GrowX = Private.Enum.GrowX
local GrowY = Private.Enum.GrowY

local CELL_GAP = 3
local CELL_MIN = 16
local CELL_MAX = 40

local BORDER_THICKNESS = 1
local DASH_COUNT = 3
local DASH_GAP = 2

local NUMBER_FONT = "GameFontHighlightSmall"

---@return SpotlightsLayoutConfig?
local function Config()
	return Private.Layout.GetConfig()
end

---@class FillOrderCellState
---@field kind "filled" | "next" | "unused"
---@field row integer 1-based, top-left origin of the drawn rectangle
---@field column integer

--- A cell acquired from the pool below. The extra regions are stashed directly on the frame --
--- `postCreate` builds them once, the pool only ever hides and repositions the frame itself.
---@class FillOrderCellFrame : Frame
---@field fill Texture
---@field solid Texture[] four continuous edges, shown for filled/next cells
---@field dashes Texture[] segments along all four edges, shown for unused cells
---@field number FontString

---@param parent Frame
---@return Texture
local function CreateEdge(parent)
	local edge = parent:CreateTexture(nil, "BORDER")

	edge:SetColorTexture(1, 1, 1, 1)

	return edge
end

--- Builds a cell's regions once, the first time the pool hands out a frame it has not seen before.
---@param cell FillOrderCellFrame
local function PostCreateCell(cell)
	local fill = cell:CreateTexture(nil, "ARTWORK")

	fill:SetColorTexture(1, 1, 1, 1)

	local solid = {}
	local dashes = {}

	for _ = 1, 4 do
		solid[#solid + 1] = CreateEdge(cell)
	end

	for _ = 1, DASH_COUNT * 4 do
		dashes[#dashes + 1] = CreateEdge(cell)
	end

	local number = cell:CreateFontString(nil, "OVERLAY", NUMBER_FONT)

	number:SetPoint("CENTER", cell, "CENTER", 0, 0)

	cell.fill, cell.solid, cell.dashes, cell.number = fill, solid, dashes, number
end

--- Positions the four continuous edges and the dashed segments for the current cell size. Both sets
--- exist on every cell regardless of state -- only their `Show`/`Hide` differs -- so a cell that
--- changes kind between passes never has to build geometry it lacked.
---@param cell FillOrderCellFrame
---@param size number
local function LayoutEdges(cell, size)
	local top, bottom, left, right = cell.solid[1], cell.solid[2], cell.solid[3], cell.solid[4]

	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
	top:SetSize(size, BORDER_THICKNESS)

	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 0, 0)
	bottom:SetSize(size, BORDER_THICKNESS)

	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
	left:SetSize(BORDER_THICKNESS, size)

	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
	right:SetSize(BORDER_THICKNESS, size)

	local dashLength = math.max((size - (DASH_COUNT - 1) * DASH_GAP) / DASH_COUNT, 1)

	for i = 1, DASH_COUNT do
		local offset = (i - 1) * (dashLength + DASH_GAP)

		local dashTop = cell.dashes[i]

		dashTop:ClearAllPoints()
		dashTop:SetPoint("TOPLEFT", cell, "TOPLEFT", offset, 0)
		dashTop:SetSize(dashLength, BORDER_THICKNESS)

		local dashBottom = cell.dashes[DASH_COUNT + i]

		dashBottom:ClearAllPoints()
		dashBottom:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", offset, 0)
		dashBottom:SetSize(dashLength, BORDER_THICKNESS)

		local dashLeft = cell.dashes[DASH_COUNT * 2 + i]

		dashLeft:ClearAllPoints()
		dashLeft:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -offset)
		dashLeft:SetSize(BORDER_THICKNESS, dashLength)

		local dashRight = cell.dashes[DASH_COUNT * 3 + i]

		dashRight:ClearAllPoints()
		dashRight:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, -offset)
		dashRight:SetSize(BORDER_THICKNESS, dashLength)
	end

	cell.fill:ClearAllPoints()
	cell.fill:SetPoint("TOPLEFT", cell, "TOPLEFT", BORDER_THICKNESS, -BORDER_THICKNESS)
	cell.fill:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -BORDER_THICKNESS, BORDER_THICKNESS)
end

--- Applies a cell's kind to its regions. Colour and text are not size-dependent, so this runs from
--- `Refresh` -- geometry runs from `Layout`, once the width (and so the cell size) is known.
---@param cell FillOrderCellFrame
---@param state FillOrderCellState
---@param index integer
local function ApplyCellState(cell, state, index)
	local dashed = state.kind == "unused"

	for i = 1, #cell.solid do
		cell.solid[i]:SetShown(not dashed)
	end

	for i = 1, #cell.dashes do
		cell.dashes[i]:SetShown(dashed)
	end

	cell.number:SetText(tostring(index))
	cell.number:Show()

	if state.kind == "filled" then
		cell.fill:Show()
		cell.fill:SetColorTexture(1, 1, 1, 0.18)

		for i = 1, #cell.solid do
			cell.solid[i]:SetAlpha(0.5)
		end

		cell.number:SetAlpha(1)
	elseif state.kind == "next" then
		cell.fill:Show()
		cell.fill:SetColorTexture(1, 1, 1, 0.06)

		for i = 1, #cell.solid do
			cell.solid[i]:SetAlpha(0.25)
		end

		cell.number:SetAlpha(0.6)
	else
		cell.fill:Hide()

		for i = 1, #cell.dashes do
			cell.dashes[i]:SetAlpha(0.15)
		end

		cell.number:SetAlpha(0.35)
	end
end

--- What the pane is showing right now: every cell's kind and grid position, plus the bounding
--- rectangle they were laid out against. Computed once per `Refresh` and read back by both
--- `Refresh` (to paint state) and `Layout` (to place it), so the two never compute a different
--- answer for the same pass.
---@type { total: integer, rows: integer, columns: integer, cells: FillOrderCellState[] }
local computed = { total = 0, rows = 0, columns = 0, cells = {} }

local function Recompute()
	local config = Config()

	table.wipe(computed.cells)
	computed.total, computed.rows, computed.columns = 0, 0, 0

	if not config then
		return
	end

	local count = #Private.Registry.GetSlots()
	local nextIndex = count + 1
	local stride = math.max(config.stride, 1)

	-- The rectangle is exactly what `Extent` says `nextIndex` cells need -- rounded up to a full
	-- rectangle by construction, since `Extent` always returns a whole number of major lines. Any
	-- leftover cells in the final line are the unused ones; no line is added purely to have some.
	local total = math.ceil(nextIndex / stride) * stride
	local rows, columns = Private.Layout.Extent(total, config)

	computed.total, computed.rows, computed.columns = total, rows, columns

	for i = 1, total do
		local row, column = Private.Layout.CellOf(i, config)

		-- Mirrors the axis whose growth points away from reading order, so the drawn rectangle's
		-- corner matches the screen corner the real grid grows from.
		local guiRow = config.growY == GrowY.Up and (rows - row + 1) or row
		local guiColumn = config.growX == GrowX.Left and (columns - column + 1) or column

		local kind

		if i <= count then
			kind = "filled"
		elseif i == nextIndex and count > 0 then
			kind = "next"
		else
			kind = "unused"
		end

		computed.cells[i] = { kind = kind, row = guiRow, column = guiColumn }
	end
end

---@return string
local function Caption()
	local config = Config()
	local L = Private.L.Settings

	if not config then
		return ""
	end

	local orientationLabel = config.orientation == Orientation.Horizontal and L.Horizontal or L.Vertical
	local growXLabel = config.growX == GrowX.Right and L.GrowRight or L.GrowLeft
	local growYLabel = config.growY == GrowY.Down and L.GrowDown or L.GrowUp

	return string.format(L.FillOrderCaption, orientationLabel, config.stride, growXLabel, growYLabel)
end

--- The viewport's height caps here rather than fixing here: a config that fits in fewer rows gets a
--- shorter pane instead of empty space below it, and only a config tall enough to hit the cap asks
--- to scroll vertically. Width is not capped at all -- it takes whatever the `Split` beside the Fill
--- column gives it, 280 in practice -- and scrolls horizontally the moment it does not fit.
local VIEWPORT_MAX_HEIGHT = 150

--- What each custom scrollbar (see below) costs the viewport's own content area.
local SCROLLBAR_THICKNESS = 6
local SCROLLBAR_GAP = 3
local SCROLLBAR_RESERVE = SCROLLBAR_THICKNESS + SCROLLBAR_GAP

--- Screen pixels of scroll per wheel notch. Blizzard's own scroll frames default to the same
--- distance (`ScrollUtil.lua`'s `SetPanExtent(30)`), which is why sliders and lists across the game
--- feel the same under the wheel regardless of what is inside them.
local WHEEL_STEP = 30

--- One axis's worth of a scrollbar: a track that jumps to wherever it is clicked, and a thumb sized
--- and positioned from the scroll frame's own range. Both drawn with `SetColorTexture`, matching
--- every other region in this pane -- a real `MinimalScrollBar` only ships vertical art, and this
--- pane needs both axes to agree in style as much as in behaviour.
---@param viewport Frame
---@param scrollFrame ScrollFrame
---@param horizontal boolean
---@return Frame track, Frame thumb, fun() Update
local function CreateScrollbar(viewport, scrollFrame, horizontal)
	local track = CreateFrame("Frame", nil, viewport)

	track:EnableMouse(true)

	local trackTexture = track:CreateTexture(nil, "BACKGROUND")

	trackTexture:SetAllPoints(track)
	trackTexture:SetColorTexture(1, 1, 1, 0.05)

	local thumb = CreateFrame("Frame", nil, track)

	local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")

	thumbTexture:SetAllPoints(thumb)
	thumbTexture:SetColorTexture(1, 1, 1, 0.35)

	local function Range()
		return horizontal and scrollFrame:GetHorizontalScrollRange() or scrollFrame:GetVerticalScrollRange()
	end

	local function Scroll()
		return horizontal and scrollFrame:GetHorizontalScroll() or scrollFrame:GetVerticalScroll()
	end

	local function SetScroll(value)
		if horizontal then
			scrollFrame:SetHorizontalScroll(value)
		else
			scrollFrame:SetVerticalScroll(value)
		end
	end

	--- Sizes and places the thumb from the current range -- called after every wheel step and
	--- whenever the content's own size changes the range in the first place.
	local function Update()
		local range = Range()

		-- Hidden outright rather than left empty: a bar nobody can move reads as broken, not as
		-- "nothing to scroll".
		if range <= 0 then
			track:Hide()

			return
		end

		track:Show()
		thumb:Show()

		local extent = horizontal and track:GetWidth() or track:GetHeight()

		if extent <= 0 then
			return
		end

		local viewExtent = horizontal and scrollFrame:GetWidth() or scrollFrame:GetHeight()
		local contentExtent = viewExtent + range

		-- Ten floors the thumb the way `minThumbExtent` does on the real templates: below it there
		-- is nothing left to grab.
		local thumbExtent = math.max(extent * (viewExtent / contentExtent), 10)
		local travel = extent - thumbExtent
		local fraction = Scroll() / range

		if horizontal then
			thumb:SetWidth(thumbExtent)
			thumb:ClearAllPoints()
			thumb:SetPoint("LEFT", track, "LEFT", fraction * travel, 0)
		else
			thumb:SetHeight(thumbExtent)
			thumb:ClearAllPoints()
			thumb:SetPoint("TOP", track, "TOP", 0, -fraction * travel)
		end
	end

	--- Clicking anywhere on the track jumps to that fraction of the range, rather than paging by one
	--- screenful -- the pane is a diagram a few hundred pixels wide, not a document.
	track:SetScript("OnMouseDown", function(self)
		local scale = self:GetEffectiveScale()
		local range = Range()

		if range <= 0 then
			return
		end

		local fraction

		if horizontal then
			local left, width = self:GetLeft(), self:GetWidth()
			local cursorX = GetCursorPosition()

			fraction = width > 0 and Clamp((cursorX / scale - left) / width, 0, 1) or 0
		else
			local top, height = self:GetTop(), self:GetHeight()
			local _, cursorY = GetCursorPosition()

			fraction = height > 0 and Clamp((top - cursorY / scale) / height, 0, 1) or 0
		end

		SetScroll(fraction * range)
		Update()
	end)

	return track, thumb, Update
end

---@param page Frame
---@return SpotlightsNode
function Private.FillOrder.Build(page)
	local L = Private.L.Settings

	local viewport = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]
	local scrollFrame = CreateFrame("ScrollFrame", nil, viewport)

	scrollFrame:EnableMouseWheel(true)

	local canvas = CreateFrame("Frame", nil, scrollFrame)

	canvas:SetSize(1, 1)
	scrollFrame:SetScrollChild(canvas)

	-- Every cell is the same kind of frame with the same regions, reused rather than rebuilt: the
	-- pool hides and clears the anchor of whatever it takes back, and `PostCreateCell` runs once per
	-- frame the pool has never handed out before.
	local pool = CreateFramePool("Frame", canvas, nil, nil, nil, PostCreateCell)

	---@type FillOrderCellFrame[]
	local active = {}

	local vTrack, _, UpdateVertical = CreateScrollbar(viewport, scrollFrame, false)
	local hTrack, _, UpdateHorizontal = CreateScrollbar(viewport, scrollFrame, true)

	local function UpdateBars()
		UpdateVertical()
		UpdateHorizontal()
	end

	scrollFrame:SetScript("OnScrollRangeChanged", UpdateBars)

	--- Shift turns the wheel sideways, the same convention the game's own horizontal lists use (the
	--- Auction House's browse results among them) -- there is no second wheel to dedicate to the
	--- second axis.
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown() then
			local range = self:GetHorizontalScrollRange()

			self:SetHorizontalScroll(Clamp(self:GetHorizontalScroll() - delta * WHEEL_STEP, 0, range))
		else
			local range = self:GetVerticalScrollRange()

			self:SetVerticalScroll(Clamp(self:GetVerticalScroll() - delta * WHEEL_STEP, 0, range))
		end

		UpdateBars()
	end)

	function viewport:Refresh()
		Recompute()

		pool:ReleaseAll()

		for i = 1, computed.total do
			local cell = pool:Acquire() --[[@as FillOrderCellFrame]]

			cell:Show()
			ApplyCellState(cell, computed.cells[i], i)
			active[i] = cell
		end

		for i = computed.total + 1, #active do
			active[i] = nil
		end
	end

	function viewport:Layout(width)
		-- Cell size depends only on width, so it -- and the content rectangle it implies -- can be
		-- worked out before this frame's own height is decided.
		local scrollWidth = math.max(width - SCROLLBAR_RESERVE, 1)
		local size = CELL_MAX
		local contentWidth, contentHeight = 1, 1
		local hasCells = computed.total > 0 and computed.columns > 0

		if hasCells then
			-- Shrunk to fit first, floored at `CELL_MIN` -- only a config that still does not fit at
			-- the floor asks the viewport to scroll horizontally rather than the cells to shrink
			-- further.
			size = math.min(math.max((scrollWidth - (computed.columns - 1) * CELL_GAP) / computed.columns,
				CELL_MIN), CELL_MAX)

			contentWidth = math.max(computed.columns * size + (computed.columns - 1) * CELL_GAP, 1)
			contentHeight = math.max(computed.rows * size + (computed.rows - 1) * CELL_GAP, 1)
		end

		local height = math.min(contentHeight, VIEWPORT_MAX_HEIGHT)

		self:SetSize(width, height)

		scrollFrame:ClearAllPoints()
		scrollFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		scrollFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -SCROLLBAR_RESERVE, SCROLLBAR_RESERVE)

		vTrack:ClearAllPoints()
		vTrack:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
		vTrack:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, SCROLLBAR_RESERVE)
		vTrack:SetWidth(SCROLLBAR_THICKNESS)

		hTrack:ClearAllPoints()
		hTrack:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
		hTrack:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -SCROLLBAR_RESERVE, 0)
		hTrack:SetHeight(SCROLLBAR_THICKNESS)

		if hasCells then
			for i = 1, computed.total do
				local cell = active[i]
				local state = computed.cells[i]

				cell:ClearAllPoints()
				cell:SetPoint("TOPLEFT", canvas, "TOPLEFT", (state.column - 1) * (size + CELL_GAP),
					-(state.row - 1) * (size + CELL_GAP))
				cell:SetSize(size, size)

				LayoutEdges(cell, size)
			end
		end

		canvas:SetSize(contentWidth, contentHeight)

		UpdateBars()

		return height
	end

	return Private.Node.Column(page, {
		Private.Controls.SubHeading(page, L.FillOrderHeading),
		viewport,
		Private.Controls.Paragraph(page, Caption),
	})
end

--- The pane reads the *configured* slot count, which can shrink on its own -- `ClearOnLeave` wipes
--- it when the raid disbands -- so this is the second tab (after the roster list) that goes stale
--- without the user touching anything.
Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	Private.Options.Refresh()
end)
