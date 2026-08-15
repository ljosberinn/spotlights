---@type string, Spotlights
local _, Private = ...

---@class SpotlightsUtils
Private.Utils = {}

local PREFIX = "|cff33ff99Spotlights|r: "

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
--- Rectangle arithmetic rather than `GetMouseFoci`/`IsMouseOver`, which answer whether the frame is the
--- mouse *focus* -- and the drop targets here fail that by design: the mover overlay covers the grid and
--- previews set `EnableMouse(false)`.
---
--- `GetCursorPosition` is in raw screen pixels while `GetLeft` and friends are in the frame's own scaled
--- units, so the cursor is divided by *that* frame's effective scale rather than UIParent's.
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
