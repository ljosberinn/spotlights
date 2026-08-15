---@type string, Spotlights
local _, Private = ...

---@class SpotlightsPreviewPane
Private.PreviewPane = {}

--- The Appearance tab's preview pane: one inert spotlight, scaled to fit, over a caption. It exists because
--- outside a raid nothing on screen wears those settings, and the grid previews need the mover unlocked.
---
--- What it shows is `Private.Preview`'s fabrication through the same `Fill` the grid previews use, so
--- nothing here reads a unit and nothing here can hold a secret.
---
--- `outOfRangeAlpha` and `deadAlpha` cannot appear -- they are what a spotlight fades *to*, and a dummy
--- that is neither has nothing to fade from. Everything else on the tab reaches the pane.

--- The pane's width, and what it fits the mini frame against: the caption states the scale and is written
--- in `Refresh`, which runs before `Layout` hands a node its width. Callers pin the pane through `Split`'s
--- `rightWidth`.
Private.PreviewPane.Width = 174

--- The rectangle the mini frame is centred in. Fixed, so a pane does not grow and shrink with the width
--- slider and move the caption under the cursor dragging it.
---
--- Also what `Fit` measures against whatever height a caller passed: a taller pane is a taller window onto
--- the same size frame, since two stacked panes at two scales would be worse than the clipping.
local STAGE_HEIGHT = 96

--- Kept clear either side, so a frame at the pane's full width does not touch the divider beside it.
local STAGE_INSET = 8

--- Any index whose made-up health is not full: at full health the bar covers its own background, which is
--- one of the settings this pane exists to show.
local DUMMY_INDEX = 2

--- How far the mini frame has to shrink to fit the stage. Never above 1, since a magnified spotlight would
--- show a two-pixel border where the real one has one.
---@param config SpotlightsLayoutConfig
---@return number
local function Fit(config)
	return math.min(1, (Private.PreviewPane.Width - STAGE_INSET * 2) / config.frameWidth,
		STAGE_HEIGHT / config.frameHeight)
end

--- The default caption: the size the frame really is, plus the percentage that keeps it honest once the
--- frame no longer fits.
---@return string
local function Caption()
	local config = Private.Layout.GetConfig()

	if not config then
		return ""
	end

	return string.format(Private.L.Settings.PreviewCaption, config.frameWidth, config.frameHeight,
		math.floor(Fit(config) * 100 + 0.5))
end

--- A pane that hands its mini frame back, so a caller can hang more off it -- the aura sections preview a
--- display anchored to a spotlight, and that spotlight is this one.
---
--- Only the aura sections pass `class`, deliberately: the Appearance tab answers "what does this setting
--- do", where a fixed fabricated colour makes both sides of a class-colour toggle visible, while the Auras
--- tab's pane is the backdrop a display is styled against and should look like the user's own frames.
---
--- No gate on the `*UseClassColor` switches: with all three off the override reaches nothing anyway, and
--- gating on the bar's alone would leave a fabricated *name* colour on a frame whose bar is static.
---@class SpotlightsPreviewPaneNode : SpotlightsNode
---@field frame SpotlightsUnitFrame

--- A table rather than five positional parameters, two of them adjacent optional strings.
---@param page Frame
---@param options { CaptionText: (string | fun(): string)?, class: string?, heading: string?, stageHeight: number? }?
---@return SpotlightsPreviewPaneNode
function Private.PreviewPane.Build(page, options)
	local L = Private.L.Settings

	options = options or {}

	local stageHeight = options.stageHeight or STAGE_HEIGHT
	local class = options.class
	local stage = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	--- A window onto a spotlight, not a canvas it may spill out of: a name at +100 or an aura display at
	--- -200 would otherwise draw across the controls beside the pane.
	stage:SetClipsChildren(true)

	local frame = Private.Preview.CreateFrame(stage)

	-- Centre to centre with no offsets, which is the one anchor a change of scale cannot move.
	frame:SetPoint("CENTER", stage, "CENTER", 0, 0)

	function stage:Refresh()
		local config = Private.Layout.GetConfig()

		if config then
			--- From `Refresh` rather than `Layout`, so a write to either size field repaints the pane without
			--- a layout pass -- the fit is decided against two constants.
			---
			--- Scale first: `PixelUtil` snaps a size against the frame's *effective* scale, so sizing before
			--- scaling snaps against the scale being replaced.
			frame:SetScale(Fit(config))
			PixelUtil.SetSize(frame, config.frameWidth, config.frameHeight)
		end

		Private.Preview.Fill(frame, DUMMY_INDEX, nil, nil, class)
	end

	function stage:Layout(width)
		self:SetSize(width, stageHeight)

		return stageHeight
	end

	local pane = Private.Node.Column(page, {
		Private.Controls.SubHeading(page, options.heading or L.PreviewHeading),
		stage,
		Private.Controls.Paragraph(page, options.CaptionText or Caption),
	}) --[[@as SpotlightsPreviewPaneNode]]

	pane.frame = frame

	return pane
end
