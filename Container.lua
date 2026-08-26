---@type string, Spotlights
local _, Private = ...

---@class SpotlightsContainer
Private.Container = {}

local DeferralKey = Private.Enum.DeferralKey

---@type Frame?
local container

--- The effective scale the spotlights' pixel-snapped anchors were last resolved against. See
--- `ApplyDisplay`.
---@type number?
local anchoredScale

--- Named because `SetPreviewing` swaps it out and has to put back exactly this string.
---
--- Bare `[group]` is `[group:party]`, true in a party *and* in a raid -- the same set the headers render
--- for. Solo is excluded deliberately: no header resolves a kind outside a group.
local VISIBILITY_CONDITION = "[group] show; hide"

--- The anchor frame every slot header hangs off. Created unprotected -- but it does **not stay** that way,
--- and code that mutates it must not assume otherwise.
---
--- Anchoring or parenting a protected frame *to* an unprotected one protects the target too, so from the
--- first header onwards `SetSize`, `SetPoint`, `Show` and `Hide` here are protected calls. Measured, not
--- deduced: `ADDON_ACTION_BLOCKED ... SpotlightsContainer:SetSize()`.
---
--- It is still a frame we own and can move freely out of combat, and being a separate object from the
--- headers is what lets the state driver below own its visibility.
---@return Frame
function Private.Container.Get()
	if container then
		return container
	end

	container = CreateFrame("Frame", "SpotlightsContainer", UIParent)
	container:SetSize(1, 1)
	container:SetPoint("CENTER")

	-- The outermost of three clamp layers, constraining where the engine *puts* the frame rather than what
	-- we compute. The other two are the manual clamp during drag and the re-clamp in ApplyPosition.
	container:SetClampedToScreen(true)

	-- WARNING: never call Show or Hide on this frame; the next driver evaluation would override it. To hide
	-- it for other reasons, compose the condition or unregister the driver for the duration.
	--
	-- The driver performs the show from inside the restricted environment, so each header's OnShow -- which
	-- *is* SecureGroupHeader_Update -- runs untainted, and joining a group mid-combat populates the frames
	-- immediately. It also collapses every header's roster scan while ungrouped, since
	-- SecureGroupHeader_OnEvent early-outs when the header is not visible.
	RegisterStateDriver(container, "visibility", VISIBILITY_CONDITION)

	return container
end

--- Takes the container's visibility over for the duration of a preview, and gives it back.
---
--- The driver's *condition* is what changes, since `Show()` would be overridden by the next evaluation
--- (see `Get`). Re-registering replaces the previous registration rather than stacking, so restoring the
--- original string needs no cleanup.
---
--- Out of combat only: `RegisterStateDriver` errors under lockdown (`SecureHandlers.lua:435`). Both callers
--- are already out-of-combat paths, but that is not a property that survives a third caller.
---@param previewing boolean
function Private.Container.SetPreviewing(previewing)
	if InCombatLockdown() then
		return
	end

	local frame = Private.Container.Get()

	RegisterStateDriver(frame, "visibility", previewing and "show" or VISIBILITY_CONDITION)
end

--- The saved position, or nil before the database has loaded.
---@return SpotlightsPositionConfig?
function Private.Container.GetPosition()
	return Private.DB and Private.DB.position
end

--- The strata the mover's rectangle belongs in: one above the spotlights, so an aura preview drawn there
--- covers the frame it stands in for. Capped at the top of the list, so a grid at `TOOLTIP` gets its
--- previews in the same strata rather than none at all.
---@return FrameStrata
function Private.Container.OverlayStrata()
	local position = Private.Container.GetPosition()
	local order = Private.Enum.FrameStrataOrder
	local current = position and position.strata

	for i = 1, #order do
		if order[i] == current then
			return order[math.min(i + 1, #order)]
		end
	end

	-- Before the database has loaded, and for a strata this build does not know. Above the default
	-- `LOW`, which is what the overlay wants in both cases.
	return "HIGH"
end

--- Puts the configured scale and strata on the container.
---
--- Out of combat only, like everything else that writes to this frame: it is protected from the first slot
--- header onwards. Both settings reach the spotlights by inheritance -- no header and no unit frame sets a
--- scale or strata of its own.
---
--- **A scale change invalidates every pixel-snapped anchor under this frame**, because `PixelUtil` resolves
--- an offset against the effective scale at the moment of the call and stores a plain number. This path is
--- the only one a scale change takes, so the re-anchor has to happen here.
---
--- Compared against the last scale actually anchored under, rather than `position.scale` against
--- `GetScale`, because `UI_SCALE_CHANGED` moves UIParent and leaves both sides of that comparison equal.
--- See docs/notes/ContainerScaleAndAnchors.md.
---@param position SpotlightsPositionConfig
local function ApplyDisplay(position)
	local frame = Private.Container.Get()

	frame:SetScale(position.scale)
	frame:SetFrameStrata(position.strata)

	local scale = frame:GetEffectiveScale()

	if scale ~= anchoredScale then
		anchoredScale = scale

		Private.SlotHeader.ForEachChild(function(child)
			child:UpdateTempMaxHealthLoss()
		end)
	end
end

--- The screen's dimensions in the container's own units, since `GetLeft` and friends answer in the frame's
--- scaled units while `UIParent:GetWidth()` answers in UIParent's. Measured from the effective scales
--- rather than from the setting, so it is right even on a pass that has not applied the setting yet.
---@return number width, number height
local function ScreenSize()
	local frame = Private.Container.Get()
	local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()

	return UIParent:GetWidth() * ratio, UIParent:GetHeight() * ratio
end

--- A point's position on each axis as a fraction of the rectangle: 0 is the left or bottom edge, 1 the
--- right or top, 0.5 the centre. Covers all nine points, because a saved position may name any of them.
---@param point AnchorPoint
---@return number horizontal, number vertical
local function Factors(point)
	local horizontal = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
	local vertical = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5

	return horizontal, vertical
end

--- How far corner `to` sits from corner `from` on a rectangle of the given size.
---
--- Exported for the version 7 migration step, which cannot be re-run to correct a divergence and so must
--- not carry a copy of this arithmetic.
---@param from AnchorPoint
---@param to AnchorPoint
---@param width number
---@param height number
---@return number x, number y
function Private.Container.CornerDelta(from, to, width, height)
	local fromH, fromV = Factors(from)
	local toH, toV = Factors(to)

	return (toH - fromH) * width, (toV - fromV) * height
end

--- The corner the grid grows from, or nil before the database has loaded. Every saved offset measures this
--- corner rather than one of the rectangle's, which is what keeps the grid still when a slot count adds a
--- column and `Layout.ApplyContainer` resizes the container around it.
---@return AnchorPoint?
local function GrowthPoint()
	local config = Private.Layout.GetConfig()

	return config and Private.Layout.AnchorPoint(config)
end

--- Turns the container's current growth corner into a corner-relative point and offset.
---
--- The screen is split into vertical halves and horizontal thirds; the offset is measured from the corner
--- of whichever region holds the grid's centre, so a grid dropped near the top right stays there at another
--- resolution. The middle third has no corner, so it measures from the screen centre.
---@return AnchorPoint point, number x, number y
local function CalcPoint()
	local frame = Private.Container.Get()
	local screenWidth, screenHeight = ScreenSize()
	local centerX, centerY = frame:GetCenter()
	local growth = GrowthPoint()

	-- Nil before the frame has both a size and an anchor, or before the database has loaded; the stored
	-- position is still valid.
	if not centerX or not centerY or not growth then
		local saved = Private.Container.GetPosition()

		if saved then
			return saved.point, saved.x, saved.y
		end

		return "CENTER", 0, 0
	end

	local growthH, growthV = Factors(growth)
	local growthX = frame:GetLeft() + growthH * frame:GetWidth()
	local growthY = frame:GetBottom() + growthV * frame:GetHeight()

	local vertical = centerY >= screenHeight / 2 and "TOP" or "BOTTOM"
	local horizontal = ""

	if centerX >= screenWidth * 2 / 3 then
		horizontal = "RIGHT"
	elseif centerX <= screenWidth / 3 then
		horizontal = "LEFT"
	end

	local point = (vertical .. horizontal) --[[@as AnchorPoint]]
	local regionH, regionV = Factors(point)

	return point, growthX - regionH * screenWidth, growthY - regionV * screenHeight
end

--- Nudges a point/offset pair until the container's rectangle lies wholly on screen.
---
--- Two-point deliberately: `point` names the UIParent corner the offset is measured from, while the frame
--- hangs by its growth corner -- the one point `SetSize` leaves where it is, so a slot count that adds a
--- column cannot move the grid.
---
--- Works in deltas, which keeps it independent of which corner `point` names: a SetPoint offset means right
--- and up no matter what it is measured from. A container larger than the screen cannot satisfy both edges,
--- and the left and bottom branches win, so an oversized grid overflows off the right and top.
---@param point AnchorPoint
---@param x number
---@param y number
---@return AnchorPoint point, number x, number y
local function Clamp(point, x, y)
	local frame = Private.Container.Get()
	local growth = GrowthPoint() or point

	frame:ClearAllPoints()
	PixelUtil.SetPoint(frame, growth, UIParent, point, x, y)

	local left, bottom = frame:GetLeft(), frame:GetBottom()
	local right, top = frame:GetRight(), frame:GetTop()

	if not left or not bottom or not right or not top then
		return point, x, y
	end

	local screenWidth, screenHeight = ScreenSize()
	local dx, dy = 0, 0

	if left < 0 then
		dx = -left
	elseif right > screenWidth then
		dx = screenWidth - right
	end

	if bottom < 0 then
		dy = -bottom
	elseif top > screenHeight then
		dy = screenHeight - top
	end

	if dx == 0 and dy == 0 then
		return point, x, y
	end

	x, y = x + dx, y + dy

	PixelUtil.SetPoint(frame, growth, UIParent, point, x, y)

	return point, x, y
end

--- Moves the container to an absolute screen position, clamped, and persists the result. Takes a
--- bottom-left corner because that is what cursor tracking produces, and walks it across the rectangle to
--- the growth corner, which is what `Clamp` anchors by; `CalcPoint` then turns it back into the
--- corner-relative form the database stores.
---
--- Out of combat only: `SetPoint` on this frame is protected from the first header onwards.
---@param left number
---@param bottom number
function Private.Container.MoveTo(left, bottom)
	local position = Private.Container.GetPosition()
	local growth = GrowthPoint()

	if not position or not growth or InCombatLockdown() then
		return
	end

	local width, height = Private.Container.Get():GetSize()
	local growthH, growthV = Factors(growth)

	Clamp("BOTTOMLEFT", left + growthH * width, bottom + growthV * height)

	position.point, position.x, position.y = CalcPoint()
end

--- Applies the saved position, re-clamping it first. Out of combat only.
---
--- The third clamp layer, and the one that earns its keep on login: a position saved at 3440x1440 can be
--- entirely off-screen at 1920x1080, which `SetClampedToScreen` will not rescue because the engine only
--- constrains movement it performs itself. The corrected values are written back.
---
--- Scale and strata are applied here and *before* the clamp, since a scale change resizes the rectangle
--- being clamped.
local function ApplyPosition()
	if Private.Events.DeferIfInCombat(DeferralKey.Position) then
		return
	end

	local position = Private.Container.GetPosition()

	if not position then
		return
	end

	ApplyDisplay(position)

	position.point, position.x, position.y = Clamp(position.point, position.x, position.y)

	-- A name layer set to inherit stores the strata it inherited, which is the one just written here, so
	-- without this it stays pinned to the layer the grid has left.
	Private.NameStyle.Request()

	Private.Mover.Sync()
end

Private.Events.RegisterHandler(DeferralKey.Position, ApplyPosition)

--- Requests a re-clamp and re-apply.
function Private.Container.Request()
	Private.Events.Request(DeferralKey.Position)
end

--- Puts the grid back in the middle of the screen.
---
--- Not `CENTER, 0, 0`, which now means the *growth corner* at the screen centre and leaves the rectangle
--- hanging off it by half its size in each axis. Offsetting by where that corner sits relative to the
--- rectangle's own centre is what centres the rectangle instead.
---
--- Combat is the callers' to refuse, since each reports it differently; the write itself is plain table
--- work and the apply defers on its own.
function Private.Container.Recenter()
	local position = Private.Container.GetPosition()
	local growth = GrowthPoint()

	if not position or not growth then
		return
	end

	local width, height = Private.Container.Get():GetSize()

	position.point = "CENTER"
	position.x, position.y = Private.Container.CornerDelta("CENTER", growth, width, height)

	Private.Container.Request()
end

--- Moves the saved offset onto the growth corner a layout change has just produced, keeping **slot 1**
--- where it is: slot 1 is anchored at zero offset from the container's growth corner, so flipping a growth
--- direction walks that corner to the opposite side of slot 1's own rectangle.
---
--- Frame size and not container size for that reason -- what is being held still is one spotlight, not the
--- grid's bounding box, so a reversed grid unfolds from the frame the user was looking at.
---
--- Takes the growth point read *before* the layout field was written, and must run before the passes
--- `Layout.Request` queued for the next frame.
---@param previous AnchorPoint
function Private.Container.Rebase(previous)
	local position = Private.Container.GetPosition()
	local config = Private.Layout.GetConfig()

	if not position or not config then
		return
	end

	local growth = Private.Layout.AnchorPoint(config)
	local x, y = Private.Container.CornerDelta(previous, growth, config.frameWidth, config.frameHeight)

	position.x, position.y = position.x + x, position.y + y
end

-- Both change what "on screen" means without moving the frame, so a position legal a moment ago may not be
-- now.
Private.Events.RegisterEvent("UI_SCALE_CHANGED", Private.Container.Request)
Private.Events.RegisterEvent("DISPLAY_SIZE_CHANGED", Private.Container.Request)
