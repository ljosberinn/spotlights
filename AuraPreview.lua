---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraPreviews
Private.AuraPreview = {}

--- Fake aura displays, one set per configured cell, shown while the Auras tab is open.
---
--- This file owns cells and lifetimes only. What a display looks like lives in `Private.Auras`,
--- which hands back records built by the same `Create` the live path uses and restyles them with
--- the same `Style`/`ApplyAnchor`.
---
--- Why a preview is needed: half the aura settings cannot reach a live display -- the button is
--- access-restricted the moment it is drawn, so a texture or colour change waits out a debounce and
--- then leaks the frames it replaces. Here nothing is registered or restricted, so every setting
--- applies instantly.
---
--- Parented to the mover's rectangle, like the player previews (`Private.Mover.GetOverlay`): the
--- only frame both unprotected and grid-aligned, so these inherit correct positioning and their
--- whole lifetime from it. It is also HIGH strata where spotlights are LOW, so a preview sits on top
--- of a live spotlight -- in a raid the real frames are the backdrop to style against.

local shown = false

--- One host frame per cell, each holding a full set of preview displays. Never destroyed, because
--- frames cannot be.
---@type table<integer, { host: Frame, previews: SpotlightsAuraPreview[] }>
local cells = {}

--- The host for one cell, created on first use.
---
--- A frame of its own rather than anchoring displays straight to the overlay, so one `SetShown`
--- covers a cell's whole set and the displays can reuse the anchor arithmetic they use against a
--- spotlight. The host *is* the spotlight as far as they are concerned.
---@param index integer
---@return { host: Frame, previews: SpotlightsAuraPreview[] }
local function Acquire(index)
	local cell = cells[index]

	if cell then
		return cell
	end

	local host = CreateFrame("Frame", nil, Private.Mover.GetOverlay())

	cell = { host = host, previews = Private.Auras.CreatePreviews(host) }
	cells[index] = cell

	return cell
end

--- Positions and restyles one cell's previews, and decides whether they belong on screen.
---
--- Called from `Layout.ApplyContainer` beside `Preview.Place`, with the same cell offsets -- so a
--- preview lands exactly where its display will.
---
--- Unlike a player preview, this is shown whether or not the cell holds a live spotlight: a player
--- preview behind a real frame would show through and read as a rendering fault, but an aura
--- preview over one is the point.
---@param index integer
---@param point AnchorPoint
---@param x number
---@param y number
---@param config SpotlightsLayoutConfig
function Private.AuraPreview.Place(index, point, x, y, config)
	-- Nothing is created until the tab is first opened. `ApplyContainer` runs on every roster event
	-- and zone change, so building a grid's worth of frames here unconditionally would cost them
	-- from login for a feature most sessions never touch.
	if not shown then
		local existing = cells[index]

		if existing then
			existing.host:Hide()
		end

		return
	end

	local cell = Acquire(index)
	local overlay = Private.Mover.GetOverlay()

	cell.host:ClearAllPoints()
	cell.host:SetSize(config.frameWidth, config.frameHeight)
	cell.host:SetPoint(point, overlay, point, x, y)
	cell.host:Show()

	Private.Auras.StylePreviews(cell.previews)
end

--- Hides every preview from `index` onwards. For cells that no longer exist.
---@param first integer
function Private.AuraPreview.HideFrom(first)
	for index, cell in pairs(cells) do
		if index >= first then
			cell.host:Hide()
		end
	end
end

--- Re-runs the placement pass, so live previews pick up a changed aura setting.
---
--- Routed through the layout pass rather than looping cells here (see `Private.Preview.Restyle`):
--- `ApplyContainer` already holds each cell's offsets and frame size. A no-op when nothing is
--- previewed, so the options frame can call it after every aura write without checking.
function Private.AuraPreview.Restyle()
	if not shown then
		return
	end

	Private.Events.Request(Private.Enum.DeferralKey.Layout)
end

--- Turns aura previewing on or off. Called only by the options frame.
---
--- Delegates the rectangle to `Private.Mover`, which arbitrates between an unlocked mover and this.
--- Hiding it hides every preview parented to it, so there is no hide loop on the way out.
---@param value boolean
function Private.AuraPreview.SetShown(value)
	-- Gated here rather than at the call site. The Auras tab exists on every client -- on one
	-- without aura displays it holds a single line explaining why -- so "is the Auras tab open" is
	-- true for a non-Evoker, and turning the layer on for them would light up the grid rectangle
	-- and a raid's worth of fictional players to preview nothing.
	value = value and Private.Auras.IsSupported

	if shown == value then
		return
	end

	shown = value

	Private.Mover.SetPreviewingAuras(value)

	if value then
		-- The full request rather than the Layout key alone (see `Private.Preview`): these are
		-- anchored to the overlay, which `Mover.Sync` aligns to the container in the Position pass,
		-- after Layout has sized the container.
		Private.Layout.Request()
	end
end
