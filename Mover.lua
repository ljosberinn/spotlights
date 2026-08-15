---@type string, Spotlights
local _, Private = ...

---@class SpotlightsMover
Private.Mover = {}

---@type Frame?
local overlay

---@type Frame?
local handle

--- The two reasons the rectangle can be on screen, kept independent: unlocking is "positioning this";
--- previewing auras is "styling what sits on it".
local unlocked = false
local previewingAuras = false

--- The grid's rectangle only: no wash, no label, no mouse.
---
--- **Deliberately not anchored or parented to the container**, which is protected from the first slot
--- header onwards -- protection propagates along anchor relationships, so an overlay tied to it would
--- combat-block on the Show/Hide/SetPoint that drag it. The cost is `Sync`.
---
--- HIGH strata so previews parented here sit above the spotlights they cover; `Sync` re-reads it from the
--- configured grid strata, which the user can raise past this one.
---
--- Split from the drag handle so a preview can hang grid-aligned displays here without a mouse-enabled
--- handle swallowing interaction with the panel behind it.
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

--- The blue slab you drag. A child of the rectangle rather than the rectangle itself, so it can be hidden
--- while previews parented alongside it stay up. It fills its parent, so the drag maths is unchanged.
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

--- The cursor position in the container's units. GetCursorPosition answers in raw screen pixels while the
--- drag maths compares against rectangles read off the container, and mixing the two makes a dragged frame
--- drift from the cursor. The container's effective scale, not UIParent's, since the grid carries the
--- user's frame scale on top.
---@return number x, number y
local function CursorPosition()
	local scale = Private.Container.Get():GetEffectiveScale()
	local x, y = GetCursorPosition()

	return x / scale, y / scale
end

--- Cursor-to-corner offset, captured at drag start so the grid does not jump to centre itself
--- under the cursor.
local grabX, grabY = 0, 0

--- Manual cursor tracking rather than `StartMoving`, which mishandles scaled frames and jumps on the first
--- mouse movement. The offset is captured against the *container*, so the arithmetic never depends on
--- `Sync` having run.
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

--- Follows the cursor, clamping every frame so the grid stops dead at the screen edge while the cursor
--- carries on -- clamping on release instead reads as the frame snapping out from under the cursor.
---
--- Combat is re-checked here, not only at drag start: a pull beginning mid-drag would otherwise keep
--- issuing protected SetPoint calls while the button is held.
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

--- Puts the overlay back on top of the container's rectangle. Called from the container's own apply pass,
--- so the overlay tracks the grid through a resolution change, a slot-count change and a resize. Safe
--- before the database exists: an unsized container yields nil corners and this does nothing.
function Private.Mover.Sync()
	-- Keyed on the rectangle being up rather than on the mover being unlocked, because a preview parented
	-- here needs the same alignment from the same call.
	if not overlay or not overlay:IsShown() then
		return
	end

	local container = Private.Container.Get()
	local left, bottom = container:GetLeft(), container:GetBottom()

	if not left or not bottom then
		return
	end

	--- Set before the anchor, and what lets it pass the container's numbers straight through: `GetLeft` and
	--- `GetSize` answer in the container's units while a SetPoint offset is read in the anchored frame's.
	--- The strata follows so previews draw over the frames they preview, wherever the user put those.
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

--- The overlay, for `Private.Preview` to parent its frames to: the only frame in the addon both
--- unprotected and aligned to the grid's rectangle.
---
--- - The **container** would make a preview protected, so the hide that has to work as combat starts would
---   block, leaving fictional raid members on screen for the fight.
--- - **UIParent** keeps it unprotected but forces its position to be recomputed on every drag frame.
---
--- Parented here, previews inherit positioning from `Sync`, unprotected status, and their whole lifetime.
---@return Frame
function Private.Mover.GetOverlay()
	return Get()
end

--- Brings the rectangle, the handle and the player previews in line with who currently wants them.
---
--- One function rather than a branch in each setter, because the two reasons overlap: closing the Auras tab
--- while unlocked must leave the mover as it was, and locking the mover while the tab is open must leave
--- previews up. Previews follow either reason -- out of a group there is otherwise nothing on screen to
--- drag or to style against.
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

--- Shows or hides the drag handle. Previewing is tied to the mover rather than the options panel, which
--- would leave `/spotlights mover` useless out of a group and show fictional players to anyone who opened
--- the settings.
---@param value boolean
function Private.Mover.SetUnlocked(value)
	unlocked = value

	Apply()
end

--- Shows or hides the grid rectangle for the aura preview layer, without the drag handle -- the reason the
--- overlay was split. A mouse-enabled slab would swallow clicks meant for the options panel.
---@param value boolean
function Private.Mover.SetPreviewingAuras(value)
	previewingAuras = value

	Apply()
end

-- Locked rather than left up and inert, which would invite dragging a frame that cannot follow.
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

-- Not `reset`, which next to `/spotlights add` reads as "reset everything".
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
