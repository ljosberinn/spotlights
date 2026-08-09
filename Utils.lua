---@type string, Spotlights
local _, Private = ...

---@class SpotlightsUtils
Private.Utils = {}

local PREFIX = "|cff33ff99Spotlights|r: "

--- The aura container system (`AuraContainer` frame type, `CustomAuraContainerTemplate`,
--- `Blizzard_AuraContainer`) arrived whole in 12.1.0. The TOC still supports 120007, where none of
--- it exists, so anything touching it must ask first. Read once: build number is restart-stable.
Private.IsTwelveDotOne = select(4, GetBuildInfo()) >= 120100

---@return boolean
function Private.Utils.IsAugmentation()
	return select(3, UnitClass("player")) == Constants.UICharacterClasses.Evoker
		and PlayerUtil.GetCurrentSpecID() == 1473
end

---@param message string
function Private.Utils.Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

---@param format string
---@param ... any
function Private.Utils.Printf(format, ...)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. string.format(format, ...))
end

--- Whether the cursor is inside a frame's rectangle.
---
--- Rectangle arithmetic rather than `GetMouseFoci`/`IsMouseOver`: those answer "is this frame the
--- mouse *focus*", which depends on stacking and on every frame having mouse input enabled -- and
--- the drop targets here fail both by design. The mover overlay is mouse-enabled, HIGH strata and
--- covers the grid, so the focus over any cell is the overlay; previews set `EnableMouse(false)`.
--- The caller wants a geometric answer: which cell is under the cursor.
---
--- `GetCursorPosition` is in raw screen pixels while `GetLeft` and friends are in the frame's own
--- scaled units, so divide the cursor by that frame's effective scale, not UIParent's -- a panel
--- and a grid cell at different scales then both measure correctly.
---
--- A frame never positioned has nil corners, read as "not under the cursor" rather than erroring.
---@param frame Frame
---@return boolean
function Private.Utils.IsCursorOver(frame)
	if not frame:IsVisible() then
		return false
	end

	local left, right = frame:GetLeft(), frame:GetRight()
	local bottom, top = frame:GetBottom(), frame:GetTop()

	if not left or not right or not bottom or not top then
		return false
	end

	local scale = frame:GetEffectiveScale()
	local x, y = GetCursorPosition()

	x, y = x / scale, y / scale

	return x >= left and x <= right and y >= bottom and y <= top
end
