---@type string, Spotlights
local _, Private = ...

---@class SpotlightsLayout
Private.Layout = {}

local Orientation = Private.Enum.Orientation
local GrowX = Private.Enum.GrowX
local GrowY = Private.Enum.GrowY
local DeferralKey = Private.Enum.DeferralKey

--- Nil until the database has loaded, which a geometry pass fired at load can outrun. Callers early-out
--- rather than substituting defaults, which would draw a grid the user never chose for one frame.
---@return SpotlightsLayoutConfig?
local function Config()
	return Private.DB and Private.DB.layout
end

---@return SpotlightsLayoutConfig?
function Private.Layout.GetConfig()
	return Config()
end

--- Cell coordinates for a slot index, 1-based in both axes. `stride` means columns when filling
--- horizontally and rows when filling vertically, which is why it is not called "columns".
---
--- Exported because the Grid tab's fill-order preview places the same indices the same way.
---@param index integer
---@param config SpotlightsLayoutConfig
---@return integer row, integer column
function Private.Layout.CellOf(index, config)
	local offset = index - 1
	local major = math.floor(offset / config.stride) + 1
	local minor = offset % config.stride + 1

	if config.orientation == Orientation.Horizontal then
		return major, minor
	end

	return minor, major
end

--- How many rows and columns a given number of cells occupies. Exported so the fill-order preview's
--- bounding box agrees with the container's.
---@param count integer
---@param config SpotlightsLayoutConfig
---@return integer rows, integer columns
function Private.Layout.Extent(count, config)
	if count < 1 then
		return 0, 0
	end

	local full = math.ceil(count / config.stride)
	local across = math.min(config.stride, count)

	if config.orientation == Orientation.Horizontal then
		return full, across
	end

	return across, full
end

--- The frame point every header anchors by. Growth directions are inverted to get there -- growing *right*
--- means anchoring each cell's *left* edge -- so the grid extends away from a corner that stays put.
---@param config SpotlightsLayoutConfig
---@return string point
local function AnchorPoint(config)
	local vertical = config.growY == GrowY.Down and "TOP" or "BOTTOM"
	local horizontal = config.growX == GrowX.Right and "LEFT" or "RIGHT"

	return vertical .. horizontal
end

--- Pixel offset from the container's anchor corner for a slot index.
---@param index integer
---@param config SpotlightsLayoutConfig
---@return number x, number y
function Private.Layout.OffsetOf(index, config)
	local row, column = Private.Layout.CellOf(index, config)

	local x = (column - 1) * (config.frameWidth + config.spacingX)
	local y = (row - 1) * (config.frameHeight + config.spacingY)

	-- Signs follow the growth direction, since both offsets are measured from the anchor corner.
	return config.growX == GrowX.Right and x or -x, config.growY == GrowY.Down and -y or y
end

--- The container's size for a given slot count, from the **configured** count and never the present one: a
--- container that resized as players came and went would move its own drag box mid-raid.
---@param count integer
---@param config SpotlightsLayoutConfig
---@return number width, number height
function Private.Layout.ContainerSize(count, config)
	local rows, columns = Private.Layout.Extent(count, config)

	if rows < 1 then
		-- A zero-size frame is not a legal anchor target, and an empty grid still has to be somewhere for
		-- the mover to find.
		return config.frameWidth, config.frameHeight
	end

	return columns * config.frameWidth + (columns - 1) * config.spacingX,
		rows * config.frameHeight + (rows - 1) * config.spacingY
end

--- The child dimensions the Blizzard layout pass was last run with; re-running it is the expensive,
--- taint-adjacent part of a geometry update.
local applied = { width = 0, height = 0 }

--- Re-anchors and resizes one header. Out of combat only.
---
--- **The Hide/Show dance is a hard requirement.** Every attribute write on a *visible* header synchronously
--- runs SecureGroupHeader_Update, which re-anchors children with SetPoint and without ClearAllPoints first
--- (SecureGroupHeaders.lua:202-211), so a child accumulates anchors and the grid cascades diagonally until
--- a /reload. Hiding first means the update does not run.
---
--- The previous shown state is restored rather than assumed: Registry.Refresh has already decided which
--- headers are visible, and geometry runs after it in DeferralOrder.
---@param header Frame
---@param index integer
---@param config SpotlightsLayoutConfig
local function PlaceHeader(header, index, config)
	local wasShown = header:IsShown()

	header:Hide()

	Private.SlotHeader.ApplySize(header, config.frameWidth, config.frameHeight)

	header:ClearAllPoints()

	local point = AnchorPoint(config)
	local x, y = Private.Layout.OffsetOf(index, config)

	PixelUtil.SetPoint(header, point, Private.Container.Get(), point, x, y)

	if wasShown then
		header:Show()
	end
end

--- Anchors and sizes every header, and resizes the children that already exist. Out of combat only, and
--- idempotent, so the in-loop re-check can abandon a half-finished pass safely.
local function ApplyGeometry()
	if Private.Events.DeferIfInCombat(DeferralKey.Geometry) then
		return
	end

	local config = Config()

	if not config then
		return
	end

	-- Pushed into the shared config *before* anything reads it: initialConfigFunction only sizes children
	-- created later, so existing ones are resized by the pass below, which reads this.
	Private.FrameConfig.Get(config.frameWidth, config.frameHeight)

	local count = Private.SlotHeader.Count()

	for i = 1, count do
		if Private.Events.DeferIfInCombat(DeferralKey.Geometry) then
			return
		end

		local header = Private.SlotHeader.Get(i) --[[@as Frame]]

		PlaceHeader(header, i, config)
	end

	-- Only when the size moved: geometry is requested on every roster event and zone change, while
	-- re-anchoring a header already moves its child with it.
	if applied.width ~= config.frameWidth or applied.height ~= config.frameHeight then
		applied.width = config.frameWidth
		applied.height = config.frameHeight

		Private.SlotHeader.ForEachChild(Private.SlotHeader.ApplyChildConfig)
	end
end

--- Sizes the container and positions the preview frames. Out of combat only.
---
--- The container is protected despite being a plain frame we created: anchoring a protected frame *to* an
--- unprotected one protects the target too, so from the first header onwards `container:SetSize` is a
--- protected call. See `Container.Get`.
---
--- The guard also covers `Private.Container.Get()` below: a first-ever call registers a state driver, and
--- the SecureHandlers API errors outright in combat (`SecureHandlers.lua:435`).
local function ApplyContainer()
	if Private.Events.DeferIfInCombat(DeferralKey.Layout) then
		return
	end

	local config = Config()

	if not config then
		return
	end

	local slots = Private.Registry.GetSlots()
	local container = Private.Container.Get()

	container:SetSize(Private.Layout.ContainerSize(#slots, config))

	local point = AnchorPoint(config)

	for i = 1, #slots do
		local x, y = Private.Layout.OffsetOf(i, config)

		Private.Preview.Place(i, point, x, y, config, slots[i])

		-- The same offsets, so an aura preview lands where its display will. It takes no slot: an aura
		-- display looks the same whoever is in the cell.
		Private.AuraPreview.Place(i, point, x, y, config)
	end

	Private.Preview.HideFrom(#slots + 1)
	Private.AuraPreview.HideFrom(#slots + 1)
end

Private.Events.RegisterHandler(DeferralKey.Geometry, ApplyGeometry)
Private.Events.RegisterHandler(DeferralKey.Layout, ApplyContainer)

--- Requests a full geometry, container and position pass. Position is included because the container's
--- *size* decides whether its saved position is still on screen, so clamping is owed to every geometry
--- change and not only to a move.
function Private.Layout.Request()
	Private.Events.Request(DeferralKey.Geometry)
	Private.Events.Request(DeferralKey.Layout)
	Private.Events.Request(DeferralKey.Position)
end
