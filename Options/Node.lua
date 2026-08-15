---@type string, Spotlights
local _, Private = ...

---@class SpotlightsNodeKit
Private.Node = {}

--- The layout kit the options panel is built out of. A node is handed its width in `Layout` and answers
--- with the height it took.
---
--- **`Refresh` runs over the whole tree, then `Layout` does.** `Refresh` decides whether a node is shown,
--- and a `Layout` pass against stale visibility leaves a hole or anchors a node that is not there.

--- The grid gutter has to beat the row gap for two columns to read as two lists rather than one.
local COLUMN_GAP = 6
local GRID_GAP = 26

local SPLIT_GAP = 12
local DIVIDER_WIDTH = 1
local SECTION_HEADER_HEIGHT = 28
local SECTION_BODY_GAP = 6

--- The title is anchored to the arrow texture, not to an inset, because the arrow draws at its own atlas
--- size.
local SECTION_ARROW_X = 2
local SECTION_TITLE_GAP = 10

--- `TabSystemTopButtonTemplate`'s height, plus room for the art the selected tab reaches above its
--- rectangle.
local SUBTAB_HEIGHT = 32
local SUBTAB_TOP_PAD = 3

--- Published so a tab fitting a `ScrollPane` into what a strip leaves does not restate the constant.
Private.Node.SubTabHeight = SUBTAB_TOP_PAD + SUBTAB_HEIGHT

local SUBTAB_INSET = 4
local SUBTAB_MIN_WIDTH = 90

--- `MinimalScrollBar` plus the gap either side, so a control laid out against the child width never runs
--- under the bar.
local SCROLL_GUTTER = 22

--- Anything the panel can lay out; containers and leaves share the type so they nest freely.
---
--- `span` is read by `Grid` only: a node that sets it takes a whole row instead of one cell. `labelWidth`
--- is written by containers on every pass and read by leaves.
---@class SpotlightsNode : Frame
---@field Refresh fun(self: SpotlightsNode)
---@field Layout fun(self: SpotlightsNode, width: number): number
---@field span boolean?
---@field labelWidth number?

--- A section, which is a node that also remembers whether it is open.
---
--- `RefreshHeader` exists so a summary can follow a control the same frame it moves without refreshing the
--- body, which would regenerate every dropdown menu inside it on every frame of a colour drag.
---@class SpotlightsSectionNode : SpotlightsNode
---@field open boolean
---@field SetOpen fun(self: SpotlightsSectionNode, open: boolean)
---@field RefreshHeader fun(self: SpotlightsSectionNode)

---@type fun()?
local RelayoutHook

--- Registers what to do when a node changes height on its own. A collapsed section knows nothing about
--- which pane owns it, so one hook beats threading a callback through every container between.
---@param callback fun()?
function Private.Node.SetRelayoutHook(callback)
	RelayoutHook = callback
end

--- Asks whoever owns the tree to run a `Refresh`/`Layout` pass. A no-op until a panel claims it.
function Private.Node.Relayout()
	if RelayoutHook then
		RelayoutHook()
	end
end

--- Lays a child out, having first told it what label column it is working against.
---
--- Stamped on every pass rather than at construction because it is inherited: a leaf moved from a grid into
--- a rail has to forget the grid's answer.
---@param container SpotlightsNode
---@param child SpotlightsNode
---@param width number
---@return number height
local function LayoutChild(container, child, width)
	child.labelWidth = container.labelWidth

	return child:Layout(width)
end

--- Adopts children built against some other frame, since `CreateFrame` needs a parent and so callers build
--- leaves before the container that nests them. Re-parenting drops the old anchors; every `Layout` clears
--- and re-sets points anyway.
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

--- Stacks children down a column.
---
--- A hidden child is skipped entirely, and a shown child that lays out to nothing still costs no gap, so a
--- wrapper around nothing is invisible rather than a 6px band.
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

		-- A frame may not be zero tall, but the number handed back is the real one, so a container of nothing
		-- takes no space in its parent.
		self:SetHeight(math.max(offset, 1))

		return offset
	end

	return column
end

--- Lays children out in a fixed number of equal columns, wrapping left to right. A row is as tall as the
--- tallest thing in it, so a wrapped label beside a plain checkbox cannot overlap the row beneath.
---
--- A child that sets `node.span = true` takes a whole row on its own and closes whatever row was being
--- filled. `labelWidth` is inherited by everything below, including through nested containers.
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

	-- Kept beside `grid.labelWidth` rather than in it: the field is overwritten by whichever container holds
	-- this grid on every pass.
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
		--- every child whether it is the last visible one.
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

--- Two nodes side by side, `rightWidth` pinning a trailing pane and `leftWidth` a leading rail. Neither
--- given, the width is halved. The divider is drawn only while both sides are visible.
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

		-- One side alone gets the whole width, so a pane that hides itself gives its room back.
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
--- Title and summary are functions because the summary formats the very settings the body edits, so both
--- are re-read on every `Refresh`. Open state is deliberately transient -- persisting it would cost a
--- saved-variable field per section and a migration.
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
	highlight:SetColorTexture(1, 1, 1, Private.Controls.HighlightAlpha)

	local arrow = header:CreateTexture(nil, "ARTWORK")

	arrow:SetPoint("LEFT", header, "LEFT", SECTION_ARROW_X, 0)

	local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")

	title:SetPoint("LEFT", arrow, "RIGHT", SECTION_TITLE_GAP, 0)
	title:SetJustifyH("LEFT")

	--- Right-aligned rather than trailing the title, whose width is whatever the translation made it. Never
	--- wrapped: the header is one line tall, and clipping beats changing every section's height.
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

	function section:RefreshHeader()
		title:SetText(Title())
		summary:SetText(Summary and Summary() or "")
		UpdateHeader()
	end

	function section:Refresh()
		self:RefreshHeader()

		-- Refreshed whether or not it is open, so a section expanded between passes is current immediately.
		body:Refresh()
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

--- A tab strip assembled in Lua rather than created from `TabSystemTemplate`, because
--- `TabSystemMixin.OnLoad` builds the button pool from `tabTemplate` and a frame created from the XML
--- template has already run its `OnLoad` by the time we could set one.
---
--- `constraints` carries what the template's KeyValues would have, which a hand-built frame inherits
--- neither of. The frame sizes itself from its children, so a caller may anchor it but must not size it.
---@param parent Frame
---@param template string the button template, which is also what decides whether the art hangs above or below the strip
---@param constraints { minTabWidth: number?, maxTabWidth: number?, spacing: number? }
---@return SpotlightsTabSystemFrame
function Private.Node.TabSystem(parent, template, constraints)
	local tabSystem = CreateFrame("Frame", nil, parent, "HorizontalLayoutFrame") --[[@as SpotlightsTabSystemFrame]]

	tabSystem.tabTemplate = template
	tabSystem.minTabWidth = constraints.minTabWidth
	tabSystem.maxTabWidth = constraints.maxTabWidth
	tabSystem.spacing = constraints.spacing

	Mixin(tabSystem, TabSystemMixin)
	TabSystemMixin.OnLoad(tabSystem)

	return tabSystem
end

--- One sub-tab: the name on its button, the node it shows, and optionally the states it exists in.
---@class SpotlightsSubTab
---@field name string
---@field node SpotlightsNode
---@field Applies (fun(): boolean)? absent means always, which is what every unconditional tab passes

--- A strip of tabs and the pages behind it, handed back as **two nodes** because the two do not always sit
--- one above the other -- the Appearance tab composes them as `Column { strip, Split(pages, pane) }` -- and
--- only the selection is shared.
---
--- `TabSystemTopButtonTemplate` carries its art on its lower edge, which is what makes a strip read as
--- sitting on the page under it; see `Blizzard_HousingDashboardHouseInfoContent.xml`. The bottom variant is
--- for tabs hanging off the bottom edge of a frame.
---
--- `OnSelected` runs after a click has changed the selection and has to re-read *and* re-lay-out the tree:
--- the page that just became visible has never been refreshed, and `Relayout` alone would not do because
--- visibility is decided in `Refresh`.
---
--- A tab carrying an `Applies` predicate comes and goes with it, and the strip goes with the last one.
---@param parent Frame
---@param tabs SpotlightsSubTab[]
---@param OnSelected fun()
---@return SpotlightsNode strip, SpotlightsNode pages
function Private.Node.SubTabs(parent, tabs, OnSelected)
	local strip = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]
	local pages = CreateFrame("Frame", nil, parent) --[[@as SpotlightsNode]]

	local selected = 1

	---@type SpotlightsNode[]
	local nodes = {}

	for i = 1, #tabs do
		nodes[i] = tabs[i].node
	end

	Adopt(pages, nodes)

	local tabSystem = Private.Node.TabSystem(strip, "TabSystemTopButtonTemplate", {
		minTabWidth = SUBTAB_MIN_WIDTH,
		spacing = 1,
	})

	tabSystem:SetPoint("TOPLEFT", strip, "TOPLEFT", SUBTAB_INSET, -SUBTAB_TOP_PAD)

	for i = 1, #tabs do
		tabSystem:AddTab(tabs[i].name)
	end

	--- Painted directly rather than through `SetTab`, whose callback would refresh a tree still being built.
	tabSystem:SetTabVisuallySelected(selected)

	tabSystem:SetTabSelectedCallback(function(tabID)
		selected = tabID

		OnSelected()
	end)

	---@type table<integer, boolean>
	local applies = {}

	--- Brings the strip in line with the predicates, and the selection in line with the strip.
	---
	--- Run from both nodes because a caller may place them so the strip is not refreshed first, while the
	--- selection has to be corrected before a page draws. Idempotent, so the second run is a re-read.
	---@return integer visible
	local function ResolveTabs()
		local visible = 0
		local first

		for i = 1, #tabs do
			local Applies = tabs[i].Applies

			applies[i] = not Applies or Applies()

			tabSystem:SetTabShown(i, applies[i])

			if applies[i] then
				visible = visible + 1
				first = first or i
			end
		end

		-- A tab that has just gone leaves its own page selected, with no tab left to navigate out of it.
		if not applies[selected] and first then
			selected = first

			-- Painted rather than selected: `SetTab`'s callback refreshes the tree this is a pass over.
			tabSystem:SetTabVisuallySelected(selected)
		end

		return visible
	end

	function strip:Refresh()
		self:SetShown(ResolveTabs() > 1)
	end

	function strip:Layout(width)
		local height = Private.Node.SubTabHeight

		self:SetSize(width, height)

		return height
	end

	function pages:Refresh()
		ResolveTabs()

		for i = 1, #nodes do
			nodes[i]:SetShown(i == selected)
		end

		nodes[selected]:Refresh()
	end

	function pages:Layout(width)
		self:SetWidth(width)

		local node = nodes[selected]

		node:ClearAllPoints()
		node:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)

		local height = LayoutChild(self, node, width)

		self:SetHeight(math.max(height, 1))

		return height
	end

	return strip, pages
end

--- A scroll pane, which is a node that also hands out the frame doing the clipping.
---
--- Exposed for the drag path only: a `ScrollFrame` clips its children when it *draws* them and leaves their
--- rectangles alone, so a row scrolled out of view still reports a hit position and the cursor has to be
--- tested against the viewport too. Nothing else may reach through -- the pane owns the anchors and extent.
---@class SpotlightsScrollPaneNode : SpotlightsNode
---@field viewport Frame

--- A fixed-height window onto a node that may be taller than it. Panes scroll independently rather than
--- the tab as a whole, which is the only way a rail stays put while the list beside it moves, so the
--- viewport's height is given rather than derived from its content.
---
--- Pass a **function** where the pane shares its column with something whose height is not fixed -- a
--- section's open state, say. It is re-read on every pass.
---@param parent Frame
---@param node SpotlightsNode
---@param height number | fun(): number
---@return SpotlightsScrollPaneNode
function Private.Node.ScrollPane(parent, node, height)
	local pane = CreateFrame("Frame", nil, parent) --[[@as SpotlightsScrollPaneNode]]

	local scroll = CreateFrame("ScrollFrame", nil, pane)

	-- `InitScrollFrameWithScrollBar` installs an `OnMouseWheel` script, which does nothing on a frame that is
	-- not listening for the wheel.
	scroll:EnableMouseWheel(true)
	scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)

	--- A sibling of the scroll frame rather than a child, because a `ScrollFrame` clips: a bar anchored
	--- past its right edge would be clipped away.
	local scrollBar = CreateFrame("EventFrame", nil, pane, "MinimalScrollBar")

	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -3)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 3)

	ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

	pane.viewport = scroll

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
		local extent = type(height) == "function" and height() or height --[[@as number]]

		self:SetWidth(width)
		self:SetHeight(extent)

		local childWidth = math.max(width - SCROLL_GUTTER, 1)

		content:SetWidth(childWidth)

		-- The scroll child's height is the scroll extent, so a node that hid half its rows shrinks the bar.
		content:SetHeight(math.max(LayoutChild(self, node, childWidth), 1))

		return extent
	end

	return pane
end

--- Makes a node belong to the states a predicate admits, by wrapping `Refresh` rather than asking a
--- section or control to learn what a category is. Containers skip hidden children outright, so hiding is
--- all this has to do. Wraps in place, so a caller holding a more specific node keeps its type.
---@param node SpotlightsNode
---@param Applies fun(): boolean
---@return SpotlightsNode
function Private.Node.OnlyWhen(node, Applies)
	local Refresh = node.Refresh

	function node:Refresh()
		local shown = Applies()

		self:SetShown(shown)

		if shown then
			Refresh(self)
		end
	end

	return node
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
