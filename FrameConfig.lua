---@type string, Spotlights
local _, Private = ...

---@class SpotlightsFrameConfig
Private.FrameConfig = {}

--- Blizzard's native raid-frame size, for a database with no layout yet. Hardcoded rather than read from
--- `CompactUnitFrameUtil.NativeFrameWidth` (`CompactUnitFrameUtil.lua:10-11`), so a patch that moves the
--- native size cannot resize a grid nobody asked to resize.
local NATIVE_FRAME_WIDTH = 72
local NATIVE_FRAME_HEIGHT = 36

---@class SpotlightsChildSize
---@field frameWidth number
---@field frameHeight number

--- The dimensions every child is created and resized at.
---@type SpotlightsChildSize
local size = {
	frameWidth = NATIVE_FRAME_WIDTH,
	frameHeight = NATIVE_FRAME_HEIGHT,
}

--- The current child size, updating it first if either dimension is supplied. A single shared table written
--- once by the geometry pass and read by the passes after it, so **callers must not keep it**.
---@param width number?
---@param height number?
---@return SpotlightsChildSize
function Private.FrameConfig.Get(width, height)
	size.frameWidth = width or size.frameWidth
	size.frameHeight = height or size.frameHeight

	return size
end
