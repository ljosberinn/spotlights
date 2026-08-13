---@type string, Spotlights
local _, Private = ...

---@class SpotlightsMover
Private.Mover = {}

---@type Frame?
local overlay

---@type Frame?
local handle

--- The two reasons the rectangle can be on screen, kept independent: unlocking is "positioning
--- this"; previewing auras is "styling what sits on it". A user doing the second must not lose
--- the first.
local unlocked = false
local previewingAuras = false

--- The grid's rectangle only: no wash, no label, no mouse.
---
--- Deliberately not anchored or parented to the container. The container is protected from the
--- first slot header onwards, and protection propagates along anchor relationships, so an overlay
--- tied to it would inherit that and every Show/Hide/SetPoint on the thing meant to be dragged by
--- hand would combat-block. Positioned against UIParent instead, it stays an unprotected frame of
--- ours; the cost is `Sync`, which runs only when the container moves.
---
--- HIGH strata so previews parented here sit above the spotlights they cover. That is only the
--- starting value: `Sync` re-reads it from the configured grid strata, since the user can raise the
--- spotlights past this one.
---
--- Split from the drag handle (once the same frame) so a preview can hang grid-aligned displays
--- here without a mouse-enabled handle swallowing interaction with the panel behind it.
---@return Frame
local function Get()
	if overlay then
		return overlay
	end

	overlay = CreateFrame("Frame", "SpotlightsMover", UIParent)
	overlay:SetFrameStrata("HIGH")
	overlay:Hide()

	return overlay
end

--- The blue slab you drag: the wash, the label, the mouse and the drag scripts.
---
--- A child of the rectangle rather than the rectangle itself, so it can be hidden while previews
--- parented alongside it stay up. It fills its parent, so the drag maths is unchanged.
---@return Frame
local function Handle()
	if handle then
		return handle
	end

	handle = CreateFrame("Frame", nil, Get())
	handle:SetAllPoints()
	handle:Hide()
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")

	local backdrop = handle:CreateTexture(nil, "BACKGROUND")
	backdrop:SetAllPoints()
	backdrop:SetColorTexture(0.1, 0.5, 0.9, 0.25)

	local label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(Private.L.Mover.Label)

	handle:SetScript("OnDragStart", Private.Mover.OnDragStart)
	handle:SetScript("OnDragStop", Private.Mover.OnDragStop)

	return handle
end

--- The cursor position in the container's units.
---
--- GetCursorPosition answers in raw screen pixels while every rectangle the drag maths compares
--- against is read off the container in its own units; the two differ by the effective scale
--- whenever the user is not at 100%. Mixing them makes a dragged frame drift from the cursor,
--- invisible at the default scale.
---
--- The container's effective scale rather than UIParent's, because the grid carries the user's
--- frame scale on top of it -- and it is the container's rectangle, and the offsets stored from it,
--- that this feeds.
---@return number x, number y
local function CursorPosition()
	local scale = Private.Container.Get():GetEffectiveScale()
	local x, y = GetCursorPosition()

	return x / scale, y / scale
end

--- Cursor-to-corner offset, captured at drag start so the grid does not jump to centre itself
--- under the cursor.
local grabX, grabY = 0, 0

--- Manual cursor tracking rather than `StartMoving`, which mishandles scaled frames and jumps
--- the frame on the first mouse movement.
---
--- The offset is captured against the *container*, not this overlay: they are the same rectangle
--- by construction, and taking it from the container means the arithmetic never depends on Sync
--- having run.
function Private.Mover.OnDragStart()
	if InCombatLockdown() then
		return
	end

	local container = Private.Container.Get()
	local left, bottom = container:GetLeft(), container:GetBottom()

	if not left or not bottom then
		return
	end

	local cursorX, cursorY = CursorPosition()

	grabX, grabY = left - cursorX, bottom - cursorY

	Handle():SetScript("OnUpdate", Private.Mover.OnUpdate)
end

--- Follows the cursor, clamping every frame.
---
--- Clamping *during* the drag rather than on release is why this is not `SetClampedToScreen`'s
--- job: the frame stops dead at the screen edge and the cursor carries on, so releasing outside
--- the screen leaves the grid where it was last legal. Clamping on release instead reads as the
--- frame snapping back out from under the cursor.
---
--- Combat is re-checked here, not only at drag start: a pull beginning mid-drag would otherwise
--- keep issuing protected SetPoint calls while the button is held.
function Private.Mover.OnUpdate()
	if InCombatLockdown() then
		Private.Mover.OnDragStop()

		return
	end

	local cursorX, cursorY = CursorPosition()

	Private.Container.MoveTo(cursorX + grabX, cursorY + grabY)
	Private.Mover.Sync()
end

function Private.Mover.OnDragStop()
	Handle():SetScript("OnUpdate", nil)
end

--- Puts the overlay back on top of the container's rectangle.
---
--- Called from the container's own apply pass, so the overlay tracks the grid through a
--- resolution change, a slot-count change and a resize -- none of which go through a drag.
---
--- Safe to call before the database exists: an unsized container yields nil corners and this
--- does nothing rather than anchoring the overlay to a corner of the screen.
function Private.Mover.Sync()
	-- Keyed on the rectangle being up rather than on the mover being unlocked, because a preview
	-- parented here needs the same alignment and gets it from the same call.
	if not overlay or not overlay:IsShown() then
		return
	end

	local container = Private.Container.Get()
	local left, bottom = container:GetLeft(), container:GetBottom()

	if not left or not bottom then
		return
	end

	--- Set before the anchor below, and the reason that anchor can pass the container's numbers
	--- straight through: `GetLeft` and `GetSize` answer in the container's own units while a SetPoint
	--- offset is read in the anchored frame's. Matching the scale makes those the same units, and
	--- makes a preview parented here the size of the spotlight it stands in for.
	---
	--- The strata follows for the same reason it was HIGH to begin with: previews have to draw over
	--- the frames they preview, wherever the user has put those.
	overlay:SetScale(container:GetScale())
	overlay:SetFrameStrata(Private.Container.OverlayStrata())

	overlay:ClearAllPoints()
	PixelUtil.SetPoint(overlay, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
	overlay:SetSize(container:GetSize())
end

---@return boolean
function Private.Mover.IsUnlocked()
	return unlocked
end

--- The overlay, for `Private.Preview` to parent its frames to.
---
--- Exposed because it is the only frame in the addon that is both unprotected and aligned to the
--- grid's rectangle, which is what a preview needs:
---
--- - Parenting a preview to the **container** would make it protected, and the hide that has to
---   work as combat starts would block, leaving fictional raid members on screen for the fight.
--- - Parenting to **UIParent** keeps it unprotected but forces its position to be recomputed from
---   the container's rect on every drag frame.
---
--- Parented here, previews inherit correct positioning from `Sync`, unprotected status, and their
--- whole lifetime: hiding the overlay hides them, so locking the mover needs no preview-specific
--- call.
---@return Frame
function Private.Mover.GetOverlay()
	return Get()
end

--- Brings the rectangle, the handle and the player previews in line with who currently wants them.
---
--- One function rather than a branch in each setter, because the two reasons overlap: closing the
--- Auras tab while unlocked must leave the mover as it was, and locking the mover while the tab is
--- open must leave previews up.
---
--- Player previews follow either reason. Unlocked, the grid must be legible as a shape, and out of
--- a group there is otherwise nothing on screen -- secure headers cannot show a nonexistent unit,
--- so an empty grid would mean dragging an invisible rectangle. The aura tab needs them because an
--- aura display is styled against a spotlight.
local function Apply()
	local wanted = unlocked or previewingAuras

	Private.Preview.SetShown(wanted)
	Handle():SetShown(unlocked)

	if not wanted then
		Private.Mover.OnDragStop()
		Get():Hide()

		return
	end

	Get():Show()
	Private.Mover.Sync()
end

--- Shows or hides the drag handle.
---
--- Previewing is tied to the mover rather than the options panel because unlocking means
--- "positioning this", whether from the panel button or from `/spotlights mover`. Keying it on the
--- panel would leave `/spotlights mover` useless out of a group and would show fictional players to
--- anyone who opened the settings.
---@param value boolean
function Private.Mover.SetUnlocked(value)
	unlocked = value

	Apply()
end

--- Shows or hides the grid rectangle for the aura preview layer, without the drag handle.
---
--- The reason the overlay was split. An aura preview needs somewhere grid-aligned and unprotected
--- to live -- the rectangle -- but without a mouse-enabled slab that would swallow clicks meant
--- for the options panel and make "styling my auras" look like "moving my grid".
---@param value boolean
function Private.Mover.SetPreviewingAuras(value)
	previewingAuras = value

	Apply()
end

-- Locking on PLAYER_REGEN_DISABLED rather than merely refusing to drag. Leaving the handle up
-- and inert in combat invites the user to drag a frame that will not follow, reading as broken.
Private.Events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if unlocked then
		Private.Mover.SetUnlocked(false)
		Private.Utils.Print(Private.L.Mover.LockedByCombat)
	end
end)

Private.SlashCommands.Register("mover", "Mover", function()
	if InCombatLockdown() then
		Private.Utils.Print(Private.L.Mover.CombatRefused)

		return
	end

	Private.Mover.SetUnlocked(not unlocked)
	Private.Utils.Print(unlocked and Private.L.Mover.Unlocked or Private.L.Mover.Locked)
end)

-- Named for what it does rather than `reset`, which next to `/spotlights add` reads as "reset
-- everything".
Private.SlashCommands.Register("recenter", "Recenter", function()
	local position = Private.Container.GetPosition()

	if not position then
		Private.Utils.Print(Private.L.Layout.NotLoaded)

		return
	end

	if InCombatLockdown() then
		Private.Utils.Print(Private.L.Mover.CombatRefused)

		return
	end

	position.point, position.x, position.y = "CENTER", 0, 0

	Private.Container.Request()
	Private.Utils.Print(Private.L.Mover.Reset)
end)
