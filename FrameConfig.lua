---@type string, Spotlights
local _, Private = ...

---@class SpotlightsFrameConfig
Private.FrameConfig = {}

--- Blizzard's native raid-frame size, the starting point for a database with no layout yet.
--- Hardcoded rather than read from `CompactUnitFrameUtil.NativeFrameWidth`
--- (`CompactUnitFrameUtil.lua:10-11`), because this is a *default* rather than a live reading: a
--- patch that moved the native size would silently resize a grid nobody asked to resize.
local NATIVE_FRAME_WIDTH = 72
local NATIVE_FRAME_HEIGHT = 36

---@class SpotlightsChildSize
---@field frameWidth number
---@field frameHeight number

--- The dimensions every child is created and resized at.
---
--- All this file has left, now our template lays itself out. It used to wrap 12.1's
--- `CompactUnitFrameUtil.ApplyConfig` and 12.0.7's `DefaultCompactUnitFrameSetup`.
---@type SpotlightsChildSize
local size = {
	frameWidth = NATIVE_FRAME_WIDTH,
	frameHeight = NATIVE_FRAME_HEIGHT,
}

--- The current child size, updating it first if either dimension is supplied.
---
--- A single shared table rather than a fresh one per call: the geometry pass writes it once and the
--- registry and rescan passes read it afterwards. Callers must not keep it beyond that pass.
---@param width number?
---@param height number?
---@return SpotlightsChildSize
function Private.FrameConfig.Get(width, height)
	size.frameWidth = width or size.frameWidth
	size.frameHeight = height or size.frameHeight

	return size
end
