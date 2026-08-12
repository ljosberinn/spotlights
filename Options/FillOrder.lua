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

--- What the heading above the pane and the caption below it cost the page's height between them --
--- the two gaps `Column` adds plus a two-line allowance for the caption, which wraps in most
--- locales at 280px. The scroll pane gets whatever is left, so it fills the tab rather than a guess
--- at how tall the grid "usually" is.
local HEADING_RESERVE = Private.Controls.HeadingHeight + 6
local CAPTION_RESERVE = 28 + 6

--- Floor for the scroll pane itself, in case a future tab makes `page` shorter than this pane's
--- chrome costs -- better a cramped pane than a negative height Blizzard errors on.
local MIN_SCROLL_HEIGHT = 80

---@param page Frame
---@return SpotlightsNode
function Private.FillOrder.Build(page)
	local L = Private.L.Settings

	local canvas = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	-- Every cell is the same kind of frame with the same regions, reused rather than rebuilt: the
	-- pool hides and clears the anchor of whatever it takes back, and `PostCreateCell` runs once per
	-- frame the pool has never handed out before.
	local pool = CreateFramePool("Frame", canvas, nil, nil, nil, PostCreateCell)

	---@type FillOrderCellFrame[]
	local active = {}

	function canvas:Refresh()
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

	function canvas:Layout(width)
		self:SetWidth(width)

		if computed.total == 0 or computed.columns == 0 then
			self:SetHeight(1)

			return 0
		end

		-- Shrunk to fit first, floored at `CELL_MIN` -- a config that still does not fit at the floor
		-- is left for the scroll pane to clip rather than the grid to shrink past legibility.
		local size = math.min(math.max((width - (computed.columns - 1) * CELL_GAP) / computed.columns,
			CELL_MIN), CELL_MAX)

		for i = 1, computed.total do
			local cell = active[i]
			local state = computed.cells[i]

			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", self, "TOPLEFT", (state.column - 1) * (size + CELL_GAP),
				-(state.row - 1) * (size + CELL_GAP))
			cell:SetSize(size, size)

			LayoutEdges(cell, size)
		end

		local height = computed.rows * size + (computed.rows - 1) * CELL_GAP

		self:SetHeight(math.max(height, 1))

		return height
	end

	-- `ScrollPane` rather than a scrollbar of this pane's own: one scrollbar style across the whole
	-- panel, and this is the same fixed-viewport-plus-`MinimalScrollBar` pattern every other pane uses.
	local scrollHeight = math.max(page:GetHeight() - HEADING_RESERVE - CAPTION_RESERVE, MIN_SCROLL_HEIGHT)
	local scrollPane = Private.Node.ScrollPane(page, canvas, scrollHeight)

	return Private.Node.Column(page, {
		Private.Controls.SubHeading(page, L.FillOrderHeading),
		scrollPane,
		Private.Controls.Paragraph(page, Caption),
	})
end

--- The pane reads the *configured* slot count, which can shrink on its own -- `ClearOnLeave` wipes
--- it when the raid disbands -- so this is the second tab (after the roster list) that goes stale
--- without the user touching anything.
Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	Private.Options.Refresh()
end)
