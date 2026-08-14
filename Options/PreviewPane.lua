---@type string, Spotlights
local _, Private = ...

---@class SpotlightsPreviewPane
Private.PreviewPane = {}

--- The Appearance tab's preview pane: one inert spotlight, scaled to fit, over a caption.
---
--- Why it is worth a pane at all: every setting on that tab is about what a spotlight *looks* like,
--- and outside a raid there is nothing on screen wearing them -- the grid previews need the mover
--- unlocked, and unlocking the mover to check a font size means leaving the panel. The pane answers
--- the same question without either.
---
--- What it shows is `Private.Preview`'s own fabrication, through the same `Fill` the grid previews
--- use: same template, same appearance block, same made-up health fraction. Nothing here reads a
--- unit, so nothing here can hold a secret.
---
--- Two appearance settings cannot appear: `outOfRangeAlpha` and `deadAlpha` are what a spotlight
--- fades *to*, and a dummy that is neither out of range nor dead has nothing to fade from. Everything
--- else on the tab reaches the pane.

--- The pane's width, and what it fits the mini frame against.
---
--- Both, deliberately: the caption states the scale, captions are written in `Refresh`, and `Layout`
--- -- where a node is told its width -- runs after. Fitting against the width the pane *is* rather
--- than the width it was handed keeps the two in step, at the cost of the caller having to honour it.
--- Callers pin the pane through `Split`'s `rightWidth`.
Private.PreviewPane.Width = 174

--- The rectangle the mini frame is centred in. Fixed, so the pane is the same height whatever the
--- frame size is set to -- a pane that grew and shrank with the width slider would move the caption
--- under the user's cursor while they dragged it.
local STAGE_HEIGHT = 96

--- Kept clear either side of the mini frame, so a frame at the pane's full width does not touch the
--- divider beside it.
local STAGE_INSET = 8

--- Which fabricated spotlight the pane shows. Any index whose made-up health is not full: at full
--- health the bar covers its own background, and the background colour is one of the settings this
--- pane exists to show.
local DUMMY_INDEX = 2

--- How far the mini frame has to shrink to fit the stage. Never above 1: a magnified spotlight would
--- show a two-pixel border where the real one has one, which is worse than a small preview.
---@param config SpotlightsLayoutConfig
---@return number
local function Fit(config)
	return math.min(1, (Private.PreviewPane.Width - STAGE_INSET * 2) / config.frameWidth,
		STAGE_HEIGHT / config.frameHeight)
end

--- The default caption: the size the frame really is, and what the pane had to do to show it.
---
--- The size is the point -- the pane is the one place a `100 × 40` reads as a rectangle rather than
--- as two numbers -- and the percentage is what keeps that honest once the frame no longer fits.
---@return string
local function Caption()
	local config = Private.Layout.GetConfig()

	if not config then
		return ""
	end

	return string.format(Private.L.Settings.PreviewCaption, config.frameWidth, config.frameHeight,
		math.floor(Fit(config) * 100 + 0.5))
end

--- A pane that hands its mini frame back, so a caller can hang more off it than the frame itself --
--- the aura sections preview a display anchored to a spotlight, and that spotlight is this one.
---
--- Only the aura sections pass `class`, and the difference is deliberate rather than an oversight of
--- the tab that does not. The Appearance tab's pane answers "what does this setting do", and a colour
--- that is the same on every character is what makes the two sides of a class-colour toggle visibly
--- different from each other. The Auras tab's pane is not the subject -- it is the backdrop a display
--- is styled against -- so the question it answers is "what will this look like on my frames", which
--- a fabricated class answers wrongly for everyone but that class.
---
--- No gate on the `*UseClassColor` switches, though `Fill` reads the class colour only where one is
--- on: with all three off the override reaches nothing and the frame renders as it does today, so a
--- branch making that true could only ever agree with the code under it. Gating on the bar's switch
--- alone would also leave a fabricated *name* colour on a frame whose bar is static.
---@class SpotlightsPreviewPaneNode : SpotlightsNode
---@field frame SpotlightsUnitFrame

---@param page Frame
---@param CaptionText (fun(): string)? defaults to the frame's size and the scale it is shown at
---@param class string? class filename the dummy wears instead of the fabricated one
---@return SpotlightsPreviewPaneNode
function Private.PreviewPane.Build(page, CaptionText, class)
	local L = Private.L.Settings
	local stage = CreateFrame("Frame", nil, page) --[[@as SpotlightsNode]]

	--- The stage is a window onto a spotlight, not a canvas the spotlight may spill out of. Several
	--- settings position something by an offset measured from the frame -- a name at +100, an aura
	--- display at -200 -- and without this those draw across the controls beside the pane and, in the
	--- aura sections, across the sections under it.
	stage:SetClipsChildren(true)

	local frame = Private.Preview.CreateFrame(stage)

	-- Centre to centre with no offsets, which is the one anchor a change of scale cannot move.
	frame:SetPoint("CENTER", stage, "CENTER", 0, 0)

	function stage:Refresh()
		local config = Private.Layout.GetConfig()

		if config then
			--- Sized and scaled from `Refresh` rather than `Layout`, so a write to either size field
			--- repaints the pane without a layout pass: the fit is decided against this pane's own
			--- width, which is a constant, and the stage's height, which is another.
			---
			--- Scale first: `PixelUtil` snaps a size against the frame's *effective* scale, so sizing
			--- before scaling snaps against the scale being replaced.
			frame:SetScale(Fit(config))
			PixelUtil.SetSize(frame, config.frameWidth, config.frameHeight)
		end

		Private.Preview.Fill(frame, DUMMY_INDEX, nil, nil, class)
	end

	function stage:Layout(width)
		self:SetSize(width, STAGE_HEIGHT)

		return STAGE_HEIGHT
	end

	local pane = Private.Node.Column(page, {
		Private.Controls.SubHeading(page, L.PreviewHeading),
		stage,
		Private.Controls.Paragraph(page, CaptionText or Caption),
	}) --[[@as SpotlightsPreviewPaneNode]]

	pane.frame = frame

	return pane
end
