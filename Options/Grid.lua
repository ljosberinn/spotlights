---@type string, Spotlights
local _, Private = ...

--- The Grid tab: the *Fill* column of layout controls beside the fill-order preview
--- (`Options/FillOrder.lua`), which reads the same fields these write.

local COLUMN_LABEL_WIDTH = 100
local FILL_ORDER_WIDTH = 280

local STRIDE_MIN, STRIDE_MAX = 1, 29
local SPACING_MIN, SPACING_MAX = 0, 40

local Orientation = Private.Enum.Orientation
local GrowX = Private.Enum.GrowX
local GrowY = Private.Enum.GrowY

---@return SpotlightsLayoutConfig?
local function Layout()
	return Private.Layout.GetConfig()
end

---@return { value: any, label: string }[]
local function OrientationChoices()
	local L = Private.L.Settings

	return {
		{ value = Orientation.Horizontal, label = L.Horizontal },
		{ value = Orientation.Vertical,   label = L.Vertical },
	}
end

---@return { value: any, label: string }[]
local function GrowXChoices()
	local L = Private.L.Settings

	return {
		{ value = GrowX.Left,  label = L.GrowLeft },
		{ value = GrowX.Right, label = L.GrowRight },
	}
end

---@return { value: any, label: string }[]
local function GrowYChoices()
	local L = Private.L.Settings

	return {
		{ value = GrowY.Up,   label = L.GrowUp },
		{ value = GrowY.Down, label = L.GrowDown },
	}
end

--- Writes a layout field and requests both the passes it invalidates and a panel refresh. The refresh is
--- what the fill-order pane needs: it reads these fields but is a sibling node no control's own `Refresh`
--- reaches.
---@param field string
---@param value any
local function SetLayoutField(field, value)
	local layout = Layout()

	if not layout then
		return
	end

	layout[field] = value

	Private.Layout.Request()
	Private.Options.Refresh()
end

---@return SpotlightsOrientation?
local function GetOrientation()
	local layout = Layout()

	return layout and layout.orientation
end

---@param value SpotlightsOrientation
local function SetOrientation(value)
	SetLayoutField("orientation", value)
end

---@return integer
local function GetStride()
	local layout = Layout()

	return layout and layout.stride or 5
end

---@param value integer
local function SetStride(value)
	SetLayoutField("stride", value)
end

---@return GrowX?
local function GetGrowX()
	local layout = Layout()

	return layout and layout.growX
end

---@param value GrowX
local function SetGrowX(value)
	SetLayoutField("growX", value)
end

---@return GrowY?
local function GetGrowY()
	local layout = Layout()

	return layout and layout.growY
end

---@param value GrowY
local function SetGrowY(value)
	SetLayoutField("growY", value)
end

---@return number
local function GetSpacingX()
	local layout = Layout()

	return layout and layout.spacingX or 3
end

---@param value number
local function SetSpacingX(value)
	SetLayoutField("spacingX", value)
end

---@return number
local function GetSpacingY()
	local layout = Layout()

	return layout and layout.spacingY or 3
end

---@param value number
local function SetSpacingY(value)
	SetLayoutField("spacingY", value)
end

---@param page Frame
---@return SpotlightsNode
local function BuildGrid(page)
	local L = Private.L.Settings

	local fill = Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.FillHeading),

		Private.Controls.Dropdown(page, L.Orientation, OrientationChoices(), GetOrientation, SetOrientation),
		Private.Controls.Slider(page, L.Stride, STRIDE_MIN, STRIDE_MAX, 1, GetStride, SetStride),
		Private.Controls.Segmented(page, L.GrowX, GrowXChoices(), GetGrowX, SetGrowX),
		Private.Controls.Segmented(page, L.GrowY, GrowYChoices(), GetGrowY, SetGrowY),

		Private.Controls.NumberPair(page, L.Spacing, {
			{
				label = L.SpacingHorizontalShort,
				get = GetSpacingX,
				set = SetSpacingX,
				minimum = SPACING_MIN,
				maximum = SPACING_MAX,
			},
			{
				label = L.SpacingVerticalShort,
				get = GetSpacingY,
				set = SetSpacingY,
				minimum = SPACING_MIN,
				maximum = SPACING_MAX,
			},
		}),
	}, 1, COLUMN_LABEL_WIDTH)

	local fillOrder = Private.FillOrder.Build(page)

	return Private.Node.Split(page, fill, fillOrder, { rightWidth = FILL_ORDER_WIDTH })
end

Private.Options.Builders.grid = BuildGrid
