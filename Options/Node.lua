---@type string, Spotlights
local _, Private = ...

---@class SpotlightsNodeKit
Private.Node = {}

--- The layout kit the reworked options panel is built out of.
---
--- `Private.Widgets.Stack` can express one shape -- a single full-width column anchored to a scroll child
--- -- because the only thing a widget in that kit knows about its surroundings is that it is as wide as
--- everything else. A node is handed its width in `Layout` and answers with the height it took, so a
--- container divides and recurses while a leaf places itself inside what it was given.
---
--- **`Refresh` runs over the whole tree, then `Layout` does.** Always, and over the whole tree rather than
--- the part that changed: `Refresh` is what decides whether a node is shown, and a `Layout` pass against
--- stale visibility either leaves a hole the height of a section or anchors a node that is not there.
--- Every container skips hidden children, so the hole closes on its own once the order is right.

--- Rows in a column read as one list and want tight spacing; two columns of controls read as one list
--- each only if the gutter between them is wider than the gaps inside them. 26 is what the 780px panel's
--- two ~350 columns leave over.
local COLUMN_GAP = 6
local GRID_GAP = 26

local SPLIT_GAP = 12
local DIVIDER_WIDTH = 1
local SECTION_HEADER_HEIGHT = 28
local SECTION_BODY_GAP = 6

--- The title anchors to the arrow *texture* rather than to an inset from the header's left edge: the arrow
--- draws at its own atlas size, so any constant standing in for its width leaves the title either touching
--- the glyph or floating away from it.
local SECTION_ARROW_X = 2
local SECTION_TITLE_GAP = 10

--- What a `ScrollPane` reserves at its right edge for the scrollbar.
---
--- `MinimalScrollBar` is eight pixels wide; the rest is the gap either side of it, so a control laid out
--- against the child width never runs under the bar.
local SCROLL_GUTTER = 22

--- Anything the panel can lay out. Containers and leaves are the same type, which is what lets a `Grid`
--- hold a `Section` holding another `Grid`.
---
--- `span` is read by `Grid` only: a node that sets it takes a whole row instead of one cell. `labelWidth`
--- is written by containers on every pass and read by leaves -- how a grid tells the controls inside it
--- where their label column ends without the caller restating it on every one.
---@class SpotlightsNode : Frame
---@field Refresh fun(self: SpotlightsNode)
---@field Layout fun(self: SpotlightsNode, width: number): number
---@field span boolean?
---@field labelWidth number?

--- A section, which is a node that also remembers whether it is open.
---@class SpotlightsSectionNode : SpotlightsNode
---@field open boolean
---@field SetOpen fun(self: SpotlightsSectionNode, open: boolean)

---@type fun()?
local RelayoutHook

--- Registers what to do when a node changes height on its own.
---
--- A collapsed section knows its new height and knows nothing about the window it is in or which of several
--- panes owns it. One hook the panel installs beats threading a callback through every container between.
---@param callback fun()?
function Private.Node.SetRelayoutHook(callback)
	RelayoutHook = callback
end

--- Asks whoever owns the tree to run a `Refresh`/`Layout` pass. A no-op until a panel claims it, which is
--- what makes the kit runnable on its own.
function Private.Node.Relayout()
	if RelayoutHook then
		RelayoutHook()
	end
end

--- Lays a child out, having first told it what label column it is working against.
---
--- Stamped on every pass rather than at construction because it is inherited: a leaf moved from a grid into
--- a rail has to forget the grid's answer. A leaf given an explicit width of its own ignores this.
---@param container SpotlightsNode
---@param child SpotlightsNode
---@param width number
---@return number height
local function LayoutChild(container, child, width)
	child.labelWidth = container.labelWidth

	return child:Layout(width)
end

--- Adopts children built against some other frame.
---
--- A container cannot exist before its children -- `CreateFrame` needs a parent -- so callers build leaves
--- against the eventual page and nest them afterwards. Re-parenting drops the old anchors, which is why
--- nothing here relies on a child's points surviving; every `Layout` clears and re-sets them.
---@param container Frame
---@param children SpotlightsNode[]
local function Adopt(container, children)
	for i = 1, #children do
		children[i]:SetParent(container)
	end
end

---@param children SpotlightsNode[]
local function RefreshAll(children)
	for i = 1, #children do
		children[i]:Refresh()
	end
end

--- Stacks children down a column, which is `Widgets.Stack` with the width handed in instead of assumed.
---
--- A hidden child is skipped entirely: no anchor, no height, no gap. A child that is shown but lays out
--- to nothing -- an empty column, a grid whose every row hid itself -- gets its anchor but still costs no
--- gap, so a wrapper around nothing is invisible rather than a 6px band.
---@param parent Frame
---@param children SpotlightsNode[]
---@param gap number? defaults to the kit's row rhythm
---@return SpotlightsNode
function Private.Node.Column(parent, children, gap)
	local column = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	gap = gap or COLUMN_GAP
	Adopt(column, children)

	function column:Refresh()
		RefreshAll(children)
	end

	function column:Layout(width)
		self:SetWidth(width)

		local offset = 0
		local placed = 0

		for i = 1, #children do
			local child = children[i]

			if child:IsShown() then
				local top = offset + (placed > 0 and gap or 0)

				child:ClearAllPoints()
				child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)

				local height = LayoutChild(self, child, width)

				if height > 0 then
					offset = top + height
					placed = placed + 1
				end
			end
		end

		-- Floored at 1 because a frame may not be zero tall, while the number handed back is the real one --
		-- so a container of nothing takes no space in its parent even though its rectangle is a pixel tall.
		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return column
end

--- Lays children out in a fixed number of equal columns, wrapping left to right. A row is as tall as the
--- tallest thing in it, so a wrapped label beside a plain checkbox cannot overlap the row beneath.
---
--- A child that sets `node.span = true` takes a whole row on its own, and closes whatever row was being
--- filled -- the controls after it start a fresh one rather than pairing with something above.
---
--- `labelWidth` is inherited by everything below, including through nested containers.
---@param parent Frame
---@param children SpotlightsNode[]
---@param columns integer? defaults to the design's two
---@param labelWidth number? the label column every leaf below should use
---@param gap number? gutter between columns
---@param rowGap number? spacing between rows
---@return SpotlightsNode
function Private.Node.Grid(parent, children, columns, labelWidth, gap, rowGap)
	local grid = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	columns = math.max(columns or 2, 1)
	gap = gap or GRID_GAP
	rowGap = rowGap or COLUMN_GAP

	-- Kept beside `grid.labelWidth` rather than in it: the field is overwritten by whichever container
	-- holds this grid on every pass, and an explicit argument has to outlive that.
	local ownLabelWidth = labelWidth

	Adopt(grid, children)

	function grid:Refresh()
		RefreshAll(children)
	end

	function grid:Layout(width)
		self:SetWidth(width)
		self.labelWidth = ownLabelWidth or self.labelWidth

		local cellWidth = (width - gap * (columns - 1)) / columns
		local rowTop = 0
		local rowHeight = 0
		local filled = 0

		--- The trailing `rowGap` is added here and taken back off at the end, which is cheaper than asking at
		--- every child whether it is the last one that will be visible.
		local function EndRow()
			if rowHeight > 0 then
				rowTop = rowTop + rowHeight + rowGap
			end

			rowHeight = 0
			filled = 0
		end

		for i = 1, #children do
			local child = children[i]

			if child:IsShown() then
				if child.span then
					EndRow()

					child:ClearAllPoints()
					child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -rowTop)

					rowHeight = LayoutChild(self, child, width)

					EndRow()
				else
					if filled == columns then
						EndRow()
					end

					child:ClearAllPoints()
					child:SetPoint("TOPLEFT", self, "TOPLEFT", filled * (cellWidth + gap), -rowTop)

					rowHeight = math.max(rowHeight, LayoutChild(self, child, cellWidth))
					filled = filled + 1
				end
			end
		end

		EndRow()

		local height = math.max(rowTop - rowGap, 0)

		self:SetHeight(math.max(height, 1))

		return height
	end

	return grid
end

--- Two nodes side by side, one of them a fixed width.
---
--- Which one is fixed is the difference between a preview pane and a navigation rail: `rightWidth` pins the
--- trailing pane (the 174px preview, the 250px raid list), `leftWidth` a leading one (the 196px class
--- rail). Neither given, the width is halved.
---
--- The divider is drawn only while both sides are visible -- either may hide itself, and a divider with
--- nothing beside it reads as a scratch on the panel.
---@param parent Frame
---@param left SpotlightsNode
---@param right SpotlightsNode
---@param options { leftWidth: number?, rightWidth: number?, gap: number?, divider: boolean? }?
---@return SpotlightsNode
function Private.Node.Split(parent, left, right, options)
	local split = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	options = options or {}

	local gap = options.gap or SPLIT_GAP
	local hasDivider = options.divider ~= false

	Adopt(split, { left, right })

	local divider = split:CreateTexture(nil, "ARTWORK")

	divider:SetColorTexture(1, 1, 1, 0.1)
	divider:Hide()

	function split:Refresh()
		left:Refresh()
		right:Refresh()
	end

	function split:Layout(width)
		self:SetWidth(width)

		local leftShown = left:IsShown()
		local rightShown = right:IsShown()

		-- One side alone is not a split: it gets the whole width, so a pane that hides itself gives its
		-- room back instead of leaving the other side in a column half the panel wide.
		if not leftShown or not rightShown then
			divider:Hide()

			local only = leftShown and left or rightShown and right

			if not only then
				self:SetHeight(1)

				return 0
			end

			only:ClearAllPoints()
			only:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)

			local height = LayoutChild(self, only, width)

			self:SetHeight(math.max(height, 1))

			return height
		end

		local spacing = gap * 2 + (hasDivider and DIVIDER_WIDTH or 0)
		local leftWidth

		if options.rightWidth then
			leftWidth = width - spacing - options.rightWidth
		elseif options.leftWidth then
			leftWidth = options.leftWidth
		else
			leftWidth = (width - spacing) / 2
		end

		leftWidth = math.max(leftWidth, 1)

		local rightWidth = math.max(width - spacing - leftWidth, 1)

		left:ClearAllPoints()
		left:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)

		right:ClearAllPoints()
		right:SetPoint("TOPLEFT", self, "TOPLEFT", leftWidth + spacing, 0)

		local height = math.max(LayoutChild(self, left, leftWidth), LayoutChild(self, right, rightWidth))

		divider:SetShown(hasDivider)

		if hasDivider then
			divider:ClearAllPoints()
			divider:SetPoint("TOPLEFT", self, "TOPLEFT", leftWidth + gap, 0)
			divider:SetSize(DIVIDER_WIDTH, math.max(height, 1))
		end

		self:SetHeight(math.max(height, 1))

		return height
	end

	return split
end

--- A body under a header that can be clicked to collapse it.
---
--- The live summary beside the title -- `25 × 25 · bottom · swipe on · 4px border` -- is what makes a
--- collapsed section worth collapsing. Both title and summary are functions, re-read on every `Refresh`,
--- because the summary is a formatting of the very settings the body edits.
---
--- Open state is transient: persisting it would mean a saved-variable field per section and a migration,
--- to remember something the user changes by looking at the panel.
---@param parent Frame
---@param Title fun(): string
---@param Summary (fun(): string?)? omitted for a section whose name says everything
---@param body SpotlightsNode
---@param startOpen boolean? defaults to open
---@return SpotlightsSectionNode
function Private.Node.Section(parent, Title, Summary, body, startOpen)
	local section = CreateFrame("Frame", nil, parent) --[[@as SpotlightsSectionNode]]

	section.open = startOpen ~= false
	Adopt(section, { body })

	local header = CreateFrame("Button", nil, section)

	header:SetHeight(SECTION_HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)

	local highlight = header:CreateTexture(nil, "HIGHLIGHT")

	highlight:SetAllPoints(header)
	highlight:SetColorTexture(1, 1, 1, 0.06)

	local arrow = header:CreateTexture(nil, "ARTWORK")

	arrow:SetPoint("LEFT", header, "LEFT", SECTION_ARROW_X, 0)

	local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")

	title:SetPoint("LEFT", arrow, "RIGHT", SECTION_TITLE_GAP, 0)
	title:SetJustifyH("LEFT")

	--- Right-aligned rather than trailing the title, whose width is whatever the translation made it: a
	--- summary starting at a different x in every section reads as misaligned lines rather than a column of
	--- detail. Never wrapped -- the header is one line tall, and a long summary is better clipped than
	--- allowed to change the height of every section it appears in.
	local summary = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

	summary:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	summary:SetJustifyH("RIGHT")
	summary:SetWordWrap(false)

	local function UpdateHeader()
		arrow:SetAtlas(section.open and "Options_ListExpand_Right_Expanded" or "Options_ListExpand_Right",
			true)
		body:SetShown(section.open)
	end

	---@param open boolean
	function section:SetOpen(open)
		if self.open == open then
			return
		end

		self.open = open
		UpdateHeader()
		Private.Node.Relayout()
	end

	header:SetScript("OnClick", function()
		section:SetOpen(not section.open)
	end)

	function section:Refresh()
		title:SetText(Title())
		summary:SetText(Summary and Summary() or "")

		-- Refreshed whether or not it is open, so a section expanded between passes shows current values
		-- immediately rather than one frame late.
		body:Refresh()
		UpdateHeader()
	end

	function section:Layout(width)
		self:SetWidth(width)
		header:SetWidth(width)

		-- Half the header at most, so a long summary shortens itself instead of pushing into the title.
		summary:SetWidth(width / 2)

		if not self.open then
			self:SetHeight(SECTION_HEADER_HEIGHT)

			return SECTION_HEADER_HEIGHT
		end

		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(SECTION_HEADER_HEIGHT + SECTION_BODY_GAP))

		local height = SECTION_HEADER_HEIGHT + SECTION_BODY_GAP + LayoutChild(self, body, width)

		self:SetHeight(height)

		return height
	end

	return section
end

--- A fixed-height window onto a node that may be taller than it.
---
--- The tab as a whole does not scroll in the reworked panel -- panes do, independently, which is the only
--- way a rail stays put while the list beside it moves. So the viewport's height is given rather than
--- derived from its content.
---@param parent Frame
---@param node SpotlightsNode
---@param height number
---@return SpotlightsNode
function Private.Node.ScrollPane(parent, node, height)
	local pane = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	local scroll = CreateFrame("ScrollFrame", nil, pane)

	-- `InitScrollFrameWithScrollBar` installs an `OnMouseWheel` script, and a script alone does nothing on
	-- a frame that is not listening for the wheel.
	scroll:EnableMouseWheel(true)
	scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)

	--- A sibling of the scroll frame rather than a child, because a `ScrollFrame` clips: a bar anchored
	--- past its right edge would be clipped away.
	local scrollBar = CreateFrame("EventFrame", nil, pane, "MinimalScrollBar")

	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -3)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 3)

	ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

	local content = CreateFrame("Frame", nil, scroll)

	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	node:SetParent(content)
	node:ClearAllPoints()
	node:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

	function pane:Refresh()
		node:Refresh()
	end

	function pane:Layout(width)
		self:SetWidth(width)
		self:SetHeight(height)

		local childWidth = math.max(width - SCROLL_GUTTER, 1)

		content:SetWidth(childWidth)

		-- The scroll child's height is the scroll extent, so a node that hid half its rows shrinks the bar
		-- rather than leaving empty space under the last one.
		content:SetHeight(math.max(LayoutChild(self, node, childWidth), 1))

		return height
	end

	return pane
end

--- Vertical space. A node so that a gap can be conditional: hide it in a `Refresh` and it costs nothing.
---@param parent Frame
---@param height number
---@return SpotlightsNode
function Private.Node.Spacer(parent, height)
	local spacer = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	function spacer:Refresh() end

	function spacer:Layout(width)
		self:SetSize(width, height)

		return height
	end

	return spacer
end
