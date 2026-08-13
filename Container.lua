---@type string, Spotlights
local _, Private = ...

---@class SpotlightsContainer
Private.Container = {}

local DeferralKey = Private.Enum.DeferralKey

---@type Frame?
local container

--- The container's normal visibility condition. Named because `SetPreviewing` swaps it out and has
--- to put back exactly this string; two copies of a macro condition that must agree is fragile.
---
--- Bare `[group]` is `[group:party]`, which is true in a party *and* in a raid -- the same set the
--- headers render for now that they carry `showParty` beside the template's `showRaid`. Solo is
--- excluded, deliberately: no header resolves a kind outside a group, so a shown container would hold
--- nothing but empty frames.
local VISIBILITY_CONDITION = "[group] show; hide"

--- The anchor frame every slot header hangs off. A plain Frame of ours, created unprotected -- but
--- it does **not stay** that way, and code that mutates it must not assume otherwise.
---
--- Protection is not only inherited parent-to-child. Anchoring or parenting a protected frame *to*
--- an unprotected one protects the target too, because moving the target would move the protected
--- frame. Every slot header is parented and anchored here, so from the first header onwards
--- `SetSize`, `SetPoint`, `Show` and `Hide` on this frame are protected calls. Measured, not
--- deduced: `ADDON_ACTION_BLOCKED ... SpotlightsContainer:SetSize()`.
---
--- What that does not cost is the reason this frame exists: it is still a frame we own and can move
--- freely out of combat, and being a separate object from the headers is what lets the state driver
--- below own its visibility.
---@return Frame
function Private.Container.Get()
	if container then
		return container
	end

	container = CreateFrame("Frame", "SpotlightsContainer", UIParent)
	container:SetSize(1, 1)
	container:SetPoint("CENTER")

	-- The outermost of three clamp layers, and the cheapest. It only does anything because
	-- ApplyContainer sizes this frame to the grid's bounding box; on the 1x1 frame it starts as,
	-- there is nothing to keep on screen.
	--
	-- Not sufficient alone: it constrains where the engine *puts* the frame, not what we compute,
	-- so a drag can still run past the edge and a saved position from a larger resolution can still
	-- be off-screen. Those are the other two layers: the manual clamp during drag, and the re-clamp
	-- in ApplyPosition.
	container:SetClampedToScreen(true)

	-- Visibility goes to the secure state driver rather than our own Show/Hide, for two reasons.
	-- The cheap one: SecureGroupHeader_OnEvent early-outs entirely when the header is not visible,
	-- so hiding this collapses every header's roster scan to nothing when we are not in a group.
	--
	-- The load-bearing one: the driver performs the show from inside the restricted environment, so
	-- each header's OnShow -- which *is* SecureGroupHeader_Update -- runs untainted. Joining a group
	-- mid-combat therefore populates the frames immediately instead of waiting for the next roster
	-- event.
	--
	-- Consequence: never call Show or Hide on this frame; the next driver evaluation would override
	-- it. To hide it for other reasons, compose the condition or unregister the driver and take
	-- manual control for the duration.
	RegisterStateDriver(container, "visibility", VISIBILITY_CONDITION)

	return container
end

--- Takes the container's visibility over for the duration of a preview, and gives it back.
---
--- The state driver above is keyed on `[group]`, so outside a group the container is hidden and no
--- preview inside it can be seen. `Show()` is not the answer (see `Get`): the next driver evaluation
--- overrides it, and a driver evaluates on far more than group changes.
---
--- So the driver's *condition* is what changes -- the "take manual control" case `Get` anticipates.
--- Re-registering replaces the previous registration rather than stacking, and restoring the
--- original string is a plain re-register with no cleanup.
---
--- The unconditional `show` is deliberately not `[group] show; show`: an unconditional driver
--- is the honest expression of "visible regardless".
---
--- Out of combat only. `RegisterStateDriver` errors under lockdown (`SecureHandlers.lua:435`). Both
--- callers are already out-of-combat paths (the mover locks on `PLAYER_REGEN_DISABLED`, the options
--- panel closes), but the guard is here because that is not a property that survives a third caller.
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

--- The strata the mover's rectangle belongs in: one above the spotlights, so an aura preview drawn
--- there covers the frame it stands in for instead of disappearing behind it.
---
--- Capped at the top of the list. A user who puts their grid at `TOOLTIP` gets previews in the same
--- strata rather than none at all, which is the honest answer when there is nothing above.
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
--- Out of combat only, like everything else that writes to this frame: it is protected from the
--- first slot header onwards, so `SetScale` and `SetFrameStrata` are protected calls exactly as
--- `SetSize` is. Both reach the spotlights by inheritance -- no header and no unit frame sets a
--- scale or a strata of its own, which is why the unit frame template no longer declares `LOW`.
---@param position SpotlightsPositionConfig
local function ApplyDisplay(position)
	local frame = Private.Container.Get()

	frame:SetScale(position.scale)
	frame:SetFrameStrata(position.strata)
end

--- The screen's dimensions in the container's own units.
---
--- `GetLeft` and friends answer in the frame's own scaled units while `UIParent:GetWidth()` answers
--- in UIParent's, and the two differ by the user's frame scale -- so a scaled grid clamped against
--- the raw screen size would be held inside a rectangle the wrong size, by a factor that grows with
--- the scale.
---
--- Measured from the effective scales rather than from the setting, so it is right even on the pass
--- that has not applied the setting yet.
---@return number width, number height
local function ScreenSize()
	local frame = Private.Container.Get()
	local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()

	return UIParent:GetWidth() * ratio, UIParent:GetHeight() * ratio
end

--- Turns the container's current rectangle into a corner-relative point and offset.
---
--- The screen is split into vertical halves and horizontal thirds, and the grid's centre decides
--- which region it belongs to. The offset is measured from *that* corner, so a grid dropped near
--- the top right stays near the top right at another resolution rather than drifting inward.
---
--- The middle horizontal third has no corner to measure from, so its offset is from the screen
--- centre -- the one case where a coordinate is the honest answer, because "centred" is what the
--- user expressed.
---@return AnchorPoint point, number x, number y
local function CalcPoint()
	local frame = Private.Container.Get()
	local screenWidth, screenHeight = ScreenSize()
	local centerX, centerY = frame:GetCenter()

	-- Nil before the frame has both a size and an anchor. Nothing sensible to compute, and the
	-- stored position is still valid, so return it unchanged.
	if not centerX or not centerY then
		local saved = Private.Container.GetPosition()

		if saved then
			return saved.point, saved.x, saved.y
		end

		return "CENTER", 0, 0
	end

	local vertical, y

	if centerY >= screenHeight / 2 then
		vertical = "TOP"
		y = frame:GetTop() - screenHeight
	else
		vertical = "BOTTOM"
		y = frame:GetBottom()
	end

	if centerX >= screenWidth * 2 / 3 then
		return (vertical .. "RIGHT") --[[@as AnchorPoint]], frame:GetRight() - screenWidth, y
	end

	if centerX <= screenWidth / 3 then
		return (vertical .. "LEFT") --[[@as AnchorPoint]], frame:GetLeft(), y
	end

	return vertical --[[@as AnchorPoint]], centerX - screenWidth / 2, y
end

--- Nudges a point/offset pair until the container's rectangle lies wholly on screen.
---
--- Works in deltas rather than recomputing an anchor, which keeps it independent of which corner
--- `point` names: a SetPoint offset always means right and up no matter what it is measured from,
--- so the same delta applies to all nine.
---
--- A container larger than the screen cannot satisfy both edges. The left and bottom branches win,
--- so an oversized grid overflows off the right and top -- the corner least likely to hold the
--- cursor, and the direction the grid grows from by default.
---@param point AnchorPoint
---@param x number
---@param y number
---@return AnchorPoint point, number x, number y
local function Clamp(point, x, y)
	local frame = Private.Container.Get()

	frame:ClearAllPoints()
	PixelUtil.SetPoint(frame, point, UIParent, point, x, y)

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

	PixelUtil.SetPoint(frame, point, UIParent, point, x, y)

	return point, x, y
end

--- Moves the container to an absolute screen position, clamped, and persists the result.
---
--- The drag path. Takes a bottom-left corner because that is what cursor tracking naturally
--- produces; Clamp and CalcPoint turn it back into the corner-relative form the database stores.
---
--- Out of combat only: `SetPoint` on this frame is protected from the first header onwards.
---@param left number
---@param bottom number
function Private.Container.MoveTo(left, bottom)
	local position = Private.Container.GetPosition()

	if not position or InCombatLockdown() then
		return
	end

	Clamp("BOTTOMLEFT", left, bottom)

	position.point, position.x, position.y = CalcPoint()
end

--- Applies the saved position, re-clamping it first. Out of combat only.
---
--- The third clamp layer, and the one that earns its keep on login: a position saved at 3440x1440
--- can be entirely off-screen at 1920x1080, and `SetClampedToScreen` will not rescue it because the
--- engine only constrains movement it performs itself. Re-clamping here checks against the *current*
--- screen every time the position is used.
---
--- The corrected values are written back, so a grid pulled on-screen by a resolution change stays
--- where the clamp put it instead of jumping back out at the next change.
---
--- Scale and strata are applied from here rather than from a pass of their own, and *before* the
--- clamp: a scale change resizes the rectangle being clamped, so clamping first would measure the
--- old one and leave a grown grid hanging off the screen edge until something else moved it.
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

	-- A name layer set to inherit expresses that by naming the strata it would have inherited, which is
	-- the one just written here. Without this, changing the grid's strata leaves every inheriting name
	-- pinned to the layer the grid has left.
	Private.NameStyle.Request()

	Private.Mover.Sync()
end

Private.Events.RegisterHandler(DeferralKey.Position, ApplyPosition)

--- Requests a re-clamp and re-apply.
function Private.Container.Request()
	Private.Events.Request(DeferralKey.Position)
end

-- Both change what "on screen" means without moving the frame, so a position legal a moment ago
-- may not be now. DISPLAY_SIZE_CHANGED covers resolution or windowed-mode changes; UI_SCALE_CHANGED
-- covers the scale slider and "use UI scale" toggle, which change UIParent's dimensions in the
-- units everything here works in.
Private.Events.RegisterEvent("UI_SCALE_CHANGED", Private.Container.Request)
Private.Events.RegisterEvent("DISPLAY_SIZE_CHANGED", Private.Container.Request)
