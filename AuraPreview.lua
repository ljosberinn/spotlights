---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraPreviews
Private.AuraPreview = {}

--- Fake aura displays, one set per configured cell, shown while the Auras tab is open.
---
--- This file owns cells and lifetimes only; what a display looks like lives in `Private.Auras`, which
--- builds these with the same `Create` and restyles them with the same `Style`/`ApplyAnchor` as the live
--- path.
---
--- They are needed because half the aura settings cannot reach a live display: the button is
--- access-restricted the moment it is drawn, so a texture or colour change waits out a debounce and then
--- leaks the frames it replaces. Nothing here is registered or restricted.
---
--- Parented to the mover's rectangle like the player previews (`Private.Mover.GetOverlay`), which
--- `Mover.Sync` keeps one strata above the configured grid strata, so a preview sits on top of a live
--- spotlight rather than behind it.

local shown = false

--- One host frame per cell, each holding a full set of preview displays. Never destroyed, because frames
--- cannot be.
---@type table<integer, { host: Frame, previews: SpotlightsAuraPreview[] }>
local cells = {}

--- The host for one cell, created on first use. A frame of its own rather than anchoring displays straight
--- to the overlay, so one `SetShown` covers a cell's whole set and the displays reuse the anchor arithmetic
--- they use against a spotlight -- the host *is* the spotlight as far as they are concerned.
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

--- Positions and restyles one cell's previews, and decides whether they belong on screen. Called from
--- `Layout.ApplyContainer` with the same offsets `Preview.Place` gets.
---
--- Unlike a player preview, shown whether or not the cell holds a live spotlight: an aura preview over a
--- real frame is the point.
---@param index integer
---@param point AnchorPoint
---@param x number
---@param y number
---@param config SpotlightsLayoutConfig
function Private.AuraPreview.Place(index, point, x, y, config)
	-- Nothing is created until the tab is first opened: `ApplyContainer` runs on every roster event and zone
	-- change, so building unconditionally would cost a grid's worth of frames from login.
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

--- Re-runs the placement pass, so live previews pick up a changed aura setting. Routed through the layout
--- pass rather than looping cells here (see `Private.Preview.Restyle`), and a no-op when nothing is
--- previewed.
function Private.AuraPreview.Restyle()
	if not shown then
		return
	end

	Private.Events.Request(Private.Enum.DeferralKey.Layout)
end

--- Rebuilds preview records after a specialization changes which aura features are active. Frames cannot be
--- destroyed, so the old records are hidden and replaced under the existing cell hosts.
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

--- Turns aura previewing on or off. Called only by the options frame.
---
--- Delegates the rectangle to `Private.Mover`, which arbitrates between an unlocked mover and this.
--- Hiding it hides every preview parented to it, so there is no hide loop on the way out.
---@param value boolean
function Private.AuraPreview.SetShown(value)
	if shown == value then
		return
	end

	shown = value

	Private.Mover.SetPreviewingAuras(value)

	if value then
		-- The full request rather than the Layout key alone (see `Private.Preview`): these anchor to the
		-- overlay, which `Mover.Sync` aligns in the Position pass.
		Private.Layout.Request()
	end
end
