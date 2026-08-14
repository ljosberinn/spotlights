---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraPreviews
Private.AuraPreview = {}

--- Fake aura displays, one set per configured cell, shown while the Auras or the Roster tab is open.
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
--- whole lifetime from it. `Mover.Sync` also keeps it one strata above the configured grid strata,
--- so a preview sits on top of a live spotlight -- in a raid the real frames are the backdrop to
--- style against.

local shown = false

--- Which options pages currently want the layer up, as a set of tab keys.
---
--- A set rather than a boolean because a tab switch fires the incoming page's `OnShow` and the
--- outgoing page's `OnHide` in an order the shell does not promise. A boolean handed `true` and
--- `false` in the wrong order ends up off; a set ends up holding exactly the pages on screen either
--- way.
---@type table<string, true>
local wanted = {}

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
	PixelUtil.SetSize(cell.host, config.frameWidth, config.frameHeight)
	PixelUtil.SetPoint(cell.host, point, overlay, point, x, y)
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

--- Rebuilds preview records after a specialization changes which aura features are active.
---
--- Frames cannot be destroyed, so the old records are hidden and replaced with new records under the
--- existing cell hosts. This is only used for the rare specialization transition, not normal styling.
function Private.AuraPreview.Rebuild()
	for _, cell in pairs(cells) do
		for i = 1, #cell.previews do
			cell.previews[i].anchor:Hide()
		end

		cell.previews = Private.Auras.CreatePreviews(cell.host)
	end

	if shown then
		Private.Events.Request(Private.Enum.DeferralKey.Layout)
	end
end

--- Points the layer at one aura category, or at all of them when handed nil.
---
--- Lives here rather than beside the strip that usually drives it, because the pages that want the
--- layer up also decide what it shows, and pairing the rebuild with the write is what keeps a page
--- from repointing the layer without repainting it.
---@param featureKey SpotlightsAuraFeatureKey?
function Private.AuraPreview.SetFeature(featureKey)
	if Private.Auras.SetPreviewFeature(featureKey) then
		Private.AuraPreview.Rebuild()
	end
end

--- Records whether one options page wants aura previewing, and turns the layer on or off to match.
---
--- Delegates the rectangle to `Private.Mover`, which arbitrates between an unlocked mover and this.
--- Hiding it hides every preview parented to it, so there is no hide loop on the way out.
---@param page string
---@param value boolean
function Private.AuraPreview.SetPageShown(page, value)
	wanted[page] = value or nil

	local wants = next(wanted) ~= nil

	if shown == wants then
		return
	end

	shown = wants

	Private.Mover.SetPreviewingAuras(wants)

	if wants then
		-- The full request rather than the Layout key alone (see `Private.Preview`): these are
		-- anchored to the overlay, which `Mover.Sync` aligns to the container in the Position pass,
		-- after Layout has sized the container.
		Private.Layout.Request()
	end
end
