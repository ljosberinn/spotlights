---@type string, Spotlights
local _, Private = ...

---@class SpotlightsPreview
Private.Preview = {}

--- Stand-in frames for the cells the secure headers cannot fill.
---
--- Why they must exist: outside a raid, `GetGroupHeaderType` returns no kind, so
--- `SecureGroupHeader_Update` calls `configureChildren` with an empty table and every child hides
--- itself (`SecureGroupHeaders.lua:404-408`). No attribute overrides that -- the header's contract
--- is to show real units -- so a preview cannot be a spotlight with fake data; it must be a
--- different frame.
---
--- These are created by us and never touched by a secure header, so they take plain numbers and no
--- secret value is involved anywhere in this file: a preview shows a made-up health fraction
--- through `SetValue`.
---
--- Parented to the mover overlay (load-bearing; see `Private.Mover.GetOverlay`): the overlay is the
--- only frame both unprotected and aligned to the grid, so previews inherit correct positioning,
--- unprotected status, and their entire lifetime from it. Hiding the overlay hides them, which is
--- why locking the mover mid-pull needs no protected call.
---
--- Built from the real template, so what you position is what you get: same regions, inset and bar
--- texture the appearance settings resolve to. Replaces WU-5's placeholder textures rather than
--- coexisting with them.

local shown = false

---@type SpotlightsUnitFrame[]
local previews = {}

--- Deterministic per index, so a given cell always previews as the same class. Uses the real class
--- colours rather than a made-up palette.
local PREVIEW_CLASSES = {
	"PRIEST",
	"DRUID",
	"PALADIN",
	"SHAMAN",
	"MONK",
	"EVOKER",
	"WARRIOR",
	"MAGE",
}

--- Varied so the grid does not read as one solid block of colour, which makes it hard to see where
--- one frame ends and the next begins while dragging.
local PREVIEW_HEALTH = { 1.0, 0.72, 0.94, 0.45, 0.83, 0.61, 1.0, 0.29 }

--- One preview frame, created on first use and never destroyed.
---
--- No events, no attribute mirror, no unit. Every mixin updater early-outs on a nil `displayedUnit`,
--- so inheriting them is free and none can fire on a unitless frame -- which lets this reuse the
--- template wholesale.
---@param index integer
---@return SpotlightsUnitFrame
local function Acquire(index)
	local preview = previews[index]

	if preview then
		return preview
	end

	preview = CreateFrame(
		"Button",
		nil,
		Private.Mover.GetOverlay(),
		"SpotlightsUnitFrameTemplate"
	) --[[@as SpotlightsUnitFrame]]

	-- Not clickable, not hoverable. The template inherits SecureUnitButtonTemplate's OnClick and
	-- declares UnitFrame_OnEnter, both of which read a unit this frame will never have.
	preview:EnableMouse(false)
	preview:RegisterForClicks()

	-- Nothing here ever calls UpdateSelectionHighlight, so hide the outline the XML left showing.
	preview.selectionHighlight:SetAlpha(0)
	preview.tempMaxHealthLoss:Hide()

	previews[index] = preview

	return preview
end

--- Fills one preview with plausible contents.
---
--- Prefers the slot's *configured* name, so previewing a populated grid shows the people who will
--- be in it. An unassigned slot falls back to a fabricated label; a spacer is left blank to read
--- as a hole.
---@param preview SpotlightsUnitFrame
---@param index integer
---@param slot SpotlightsSlot?
local function Fill(preview, index, slot)
	local blank = slot and slot.kind == "blank"
	local name = slot and slot.name

	preview.name:SetText(
		blank and "" or (name or string.format(Private.L.Preview.Label, index))
	)
	preview.healthText:SetText("")

	local class = PREVIEW_CLASSES[(index - 1) % #PREVIEW_CLASSES + 1]
	local classColor = RAID_CLASS_COLORS[class]
	local fraction = blank and 0 or PREVIEW_HEALTH[(index - 1) % #PREVIEW_HEALTH + 1]

	-- Plain numbers on a 0..1 scale; nothing secret reaches a preview.
	preview.healthBar:SetMinMaxValues(0, 1)
	preview.healthBar:SetValue(fraction)

	-- Texture before colour: SetStatusBarTexture resets the region's vertex colour to white, the
	-- same trap UpdateTexture documents on the real frames.
	local appearance = Private.DB and Private.DB.appearance

	if appearance then
		local path = Private.Media.StatusBar(appearance.barTexture)

		preview.healthBar:SetStatusBarTexture(path)
		preview.background:SetTexture(path)
	end

	-- The same static-or-class choice the live frame makes. A preview never disconnects or dies, so
	-- that branch of the live path has no counterpart here.
	local healthR, healthG, healthB, healthA = classColor.r, classColor.g, classColor.b, 1
	local bgR, bgG, bgB, bgA = classColor.r * 0.2, classColor.g * 0.2, classColor.b * 0.2, 1
	local nameR, nameG, nameB, nameA = classColor.r, classColor.g, classColor.b, 1

	if appearance then
		if not appearance.healthUseClassColor then
			healthR, healthG, healthB, healthA = appearance.healthColorR, appearance.healthColorG, appearance.healthColorB, appearance.healthColorA
			bgR, bgG, bgB, bgA = appearance.healthBgColorR, appearance.healthBgColorG, appearance.healthBgColorB, appearance.healthBgColorA
		end

		if not appearance.nameUseClassColor then
			nameR, nameG, nameB, nameA = appearance.nameColorR, appearance.nameColorG, appearance.nameColorB, appearance.nameColorA
		end

		Private.NameStyle.ApplyLayout(preview.name, appearance)
		preview.healthText:SetFont(Private.Media.Font(appearance.healthTextFont), appearance.healthTextFontSize, "OUTLINE")
		preview.healthText:ClearAllPoints()
		preview.healthText:SetPoint(appearance.healthTextPoint, preview, appearance.healthTextPoint, appearance.healthTextX, appearance.healthTextY)
		preview.healthText:SetJustifyH("CENTER")
		preview.healthText:SetShown(appearance.healthTextEnabled)
		if appearance.healthTextFormat == "percent" then
			local percent = fraction * 100
			preview.healthText:SetText(percent < 10 and string.format("%.1f%%", percent) or string.format("%.0f%%", percent))
		elseif appearance.healthTextFormat == "absValueAbbreviated" then
			preview.healthText:SetText(AbbreviateNumbers(fraction * 100000))
		else
			preview.healthText:SetText(string.format("%d", fraction * 100000))
		end
	end

	preview.healthBar:SetStatusBarColor(healthR, healthG, healthB, healthA)
	preview.background:SetVertexColor(bgR, bgG, bgB, bgA)
	preview.name:SetVertexColor(nameR, nameG, nameB, nameA)
	local textR, textG, textB, textA = appearance and appearance.healthTextColorR or 0.5, appearance and appearance.healthTextColorG or 0.5, appearance and appearance.healthTextColorB or 0.5, appearance and appearance.healthTextColorA or 1
	if appearance and appearance.healthTextUseClassColor then
		textR, textG, textB, textA = classColor.r, classColor.g, classColor.b, 1
	end
	preview.healthText:SetVertexColor(textR, textG, textB, textA)

	-- Dimmed as a whole so a preview is never mistaken for a live spotlight. Deliberately not
	-- SetAlphaFromBoolean: there is no secret here, and the secret-safe setter would needlessly make
	-- this frame's Alpha aspect secret.
	preview:SetAlpha((blank and 0.25 or 0.7) * (appearance and appearance.frameAlpha or 1))
end

--- Positions and fills the preview for one cell, and decides whether it belongs on screen.
---
--- A cell whose header is currently showing gets no preview: that cell is occupied by the real
--- thing, and a stand-in behind it would show through the frame's own transparency.
---@param index integer
---@param point AnchorPoint
---@param x number
---@param y number
---@param config SpotlightsLayoutConfig
---@param slot SpotlightsSlot?
function Private.Preview.Place(index, point, x, y, config, slot)
	-- Nothing is created until previewing is first switched on. `ApplyContainer` runs on every
	-- roster event and zone change, so building a frame per slot here unconditionally would keep a
	-- grid's worth of frames -- and the mover overlay they parent to -- alive from login for a
	-- feature that may never be used.
	if not shown then
		local existing = previews[index]

		if existing then
			existing:Hide()
		end

		return
	end

	local preview = Acquire(index)
	local overlay = Private.Mover.GetOverlay()

	-- Anchored to the overlay with the *same* point and offsets the header uses against the
	-- container. Mover.Sync keeps the two rectangles identical, so a preview lands exactly where its
	-- spotlight will.
	preview:ClearAllPoints()
	preview:SetSize(config.frameWidth, config.frameHeight)
	preview:SetPoint(point, overlay, point, x, y)

	Fill(preview, index, slot)

	-- Occupancy is decided by the header's *child*, and by `IsVisible` rather than `IsShown`. The
	-- header is `Show()`n at creation and stays so forever, so `header:IsShown()` is true even out
	-- of a raid with nothing rendered -- testing it would hide every preview in the case previews
	-- exist for. The child is what the secure update shows and hides, and `IsVisible` walks the
	-- parent chain, so it answers whether there is a live spotlight in this cell right now.
	local header = Private.SlotHeader.Get(index)
	local child = header and header:GetAttribute("child1") --[[@as Frame?]]

	preview:SetShown(not (child and child:IsVisible()))
end

--- Re-runs the placement pass, so live previews pick up a changed appearance setting.
---
--- Routed through the layout pass rather than looping frames here, because `Fill` needs each cell's
--- slot and offsets, which `ApplyContainer` already has. Duplicating it would mean two places
--- deciding what a preview looks like.
---
--- A no-op when nothing is being previewed, so the options frame can call this after every
--- appearance write without asking whether it matters.
function Private.Preview.Restyle()
	if not shown then
		return
	end

	Private.Events.Request(Private.Enum.DeferralKey.Layout)
end

--- The cell whose preview is under the cursor, or nil.
---
--- The drop target for a cell nobody is in yet, which out of a raid is every cell -- so while the
--- mover is unlocked this is the only thing answering, and it makes the grid assignable before a
--- raid exists.
---
--- This index needs no compaction lookup: `Place` fills preview *i* from `slots[i]`, so the index
--- already is a slot number.
---
--- A hidden preview cannot match: `IsCursorOver` tests visibility, so cells whose real spotlight is
--- on screen fall through to `Private.SlotHeader.CellUnderCursor` instead of being claimed twice.
---@return integer? slot
function Private.Preview.CellUnderCursor()
	if not shown then
		return nil
	end

	for i = 1, #previews do
		if Private.Utils.IsCursorOver(previews[i]) then
			return i
		end
	end

	return nil
end

--- Hides every preview from `first` onwards. For cells that no longer exist.
---@param first integer
function Private.Preview.HideFrom(first)
	for i = first, #previews do
		previews[i]:Hide()
	end
end

--- Turns previewing on or off. Called by the mover, and only by the mover.
---
--- No hide loop on the way out: the caller hides the overlay a moment later, which hides every
--- preview with it. Nothing here has to run under combat lockdown.
---@param value boolean
function Private.Preview.SetShown(value)
	shown = value

	-- The container's visibility is a secure state driver keyed on `[group:raid]`, so showing
	-- previews outside a raid means taking that condition over for the duration. Container owns the
	-- detail; this just says when.
	Private.Container.SetPreviewing(value)

	if value then
		-- The full request, not just Layout. Previews anchor to the overlay, which `Mover.Sync`
		-- aligns to the container from the *Position* pass -- after Layout has sized the container.
		-- Asking only for Layout would align the overlay to the container's previous size.
		Private.Layout.Request()
	end
end
