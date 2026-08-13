---@type string, Spotlights
local _, Private = ...

--- The one sanctioned global in this addon: XML `mixin=` resolves against _G, so this table has to
--- be reachable there.
SpotlightsUnitFrameMixin = {}

--- Registered per unit by the attribute mirror. Keep this set equal to the handled set.
local UNIT_EVENTS = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_CONNECTION",
	"UNIT_NAME_UPDATE",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
	"UNIT_IN_RANGE_UPDATE",
	"UNIT_PHASE",
	"UNIT_FACTION",
	"UNIT_FLAGS",
}

--- Not unit-filtered, so registered once per frame rather than re-registered by the mirror.
local GLOBAL_EVENTS = {
	"PLAYER_TARGET_CHANGED",
	"PLAYER_FLAGS_CHANGED",
}

local DISCONNECTED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
local BACKGROUND_MULTIPLIER = 0.2

--- The health bar's inset on every side. Must match the template's healthBar anchors:
--- UpdateTempMaxHealthLoss re-anchors that bar and has to put it back exactly where the XML had it.
local HEALTH_BAR_INSET = 1

--- The absorb overlay's opacity.
local ABSORB_ALPHA = 0.6

-- Round to one decimal below 10%, then to whole percentages. The curve keeps the secret health
-- percentage opaque while still giving the FontString a single, safe value to format.
local healthPercentCurve = C_CurveUtil.CreateCurve()
healthPercentCurve:SetType(Enum.LuaCurveType.Step)
healthPercentCurve:AddPoint(0, 0)
for tenth = 1, 100 do
	local threshold = tenth / 10
	healthPercentCurve:AddPoint((threshold - 0.05) / 100, threshold)
end
for whole = 11, 100 do
	healthPercentCurve:AddPoint((whole - 0.5) / 100, whole)
end

--- The appearance block, or nil before the database has loaded.
---
--- Read per call rather than cached: every value is a setting the options frame can change at any
--- moment.
---@return SpotlightsAppearanceConfig?
local function Appearance()
	return Private.DB and Private.DB.appearance
end

--- Whether `unit` is close enough to matter, for alpha purposes only.
---
--- **The return may be a secret value.** Pipe it directly into `SetAlphaFromBoolean`; never compare
--- it, cache it as a plain bool, or store it in a table we later iterate. The companion validity
--- return cannot be tested from tainted addon code, so the API's primary result is the only value
--- used here.
---
---@param unit string
---@return boolean inRange
local function IsInRange(unit)
	local isPlayer = UnitIsUnit(unit, "player")

	if not issecretvalue(isPlayer) and isPlayer then
		return true
	end

	local phaseReason = UnitPhaseReason(unit)

	if not issecretvalue(phaseReason) and phaseReason ~= nil then
		return false
	end

	local inRange = UnitInRange(unit)

	return inRange
end

--- Name layout, factored out so the live frames and the preview style the name the same way.
---@class SpotlightsNameStyle
Private.NameStyle = {}

--- The horizontal justification implied by an anchor point.
---
--- The name spans the frame between opposed horizontal anchors, so `wordwrap=false` has a width to
--- truncate against. Justification still decides how text sits within that span.
---@param point string
---@return string
local function JustifyForPoint(point)
	if point:find("LEFT") then
		return "LEFT"
	elseif point:find("RIGHT") then
		return "RIGHT"
	end

	return "CENTER"
end

--- The frame the name is drawn in, created on first ask.
---
--- The name used to be a FontString in the button's own `OVERLAY` layer, which is *below* every layer of
--- every child frame -- so an aura display, which hangs off a child frame, covered it and no draw-layer
--- change could rescue it. A layer of our own is a sibling of those child frames rather than a region
--- under them, which is what makes `nameStrata` expressible at all.
---
--- Shared with `Private.Preview` so a preview and a live spotlight stack their names the same way.
---
--- **Out of combat only on a live spotlight.** The layer is parented to a secure unit button, so
--- `SetAllPoints` and `SetFrameLevel` on it are protected calls for the same reason the container's
--- `SetSize` is. Preview frames are ours and need no such care.
---@param frame SpotlightsUnitFrame
---@return Frame
function Private.NameStyle.EnsureLayer(frame)
	local layer = frame.spotlightsNameLayer

	if layer then
		return layer
	end

	layer = CreateFrame("Frame", nil, frame)

	--- Load-bearing rather than incidental, which is why it is said out loud even though frames ship
	--- with the mouse off: a mouse-enabled frame across the whole spotlight would swallow the clicks the
	--- secure button exists to receive, and take the hover-only setting down with them.
	layer:EnableMouse(false)

	--- The parent's own level rather than the `+1` a new frame defaults to. An aura display's anchor is
	--- a child frame at that `+1`, so at the default the name would rise over every aura the moment this
	--- layer existed -- a profile rendering differently on the first load of a build it never configured.
	--- Raising the name is what `nameStrata` is for, and it should take saying so.
	layer:SetFrameLevel(frame:GetFrameLevel())
	layer:SetAllPoints(frame)

	--- `ApplyLayout` anchors the name against `fontString:GetParent()`, so a layer covering the same
	--- rectangle preserves every stored offset without that arithmetic learning the layer exists.
	frame.name:SetParent(layer)

	frame.spotlightsNameLayer = layer

	return layer
end

--- Puts the configured strata on the name layer.
---
--- `SetFrameStrata` has no inverse, so `INHERIT` is expressed by naming the strata the layer *would*
--- have inherited rather than by leaving the call out -- a layer raised once and then set back to
--- inherit has to come back down. Read off the frame rather than out of the position block, so the
--- answer is also right for a preview, whose parent is not the container.
---
--- **A protected call on a live spotlight.** Callers on that path go through the deferral queue; the
--- preview path may call it outright.
---@param frame SpotlightsUnitFrame
---@param appearance SpotlightsAppearanceConfig
function Private.NameStyle.ApplyStrata(frame, appearance)
	local layer = frame.spotlightsNameLayer

	if not layer then
		return
	end

	local strata = appearance.nameStrata

	layer:SetFrameStrata(Private.Enum.FrameStrata[strata] and strata or frame:GetFrameStrata())
end

--- Puts the configured strata on every live spotlight's name layer.
---
--- Deferred rather than run inline because it is a protected call on every frame it touches. The panel
--- refuses to open in combat, but a slash command and an import do not -- and under `INHERIT` this also
--- runs off the container's own pass, which a fight starting can catch mid-flight.
local function ApplyNameStrata()
	if Private.Events.DeferIfInCombat(Private.Enum.DeferralKey.NameStrata) then
		return
	end

	local appearance = Appearance()

	if not appearance then
		return
	end

	Private.SlotHeader.ForEachChild(function(child)
		Private.NameStyle.ApplyStrata(child, appearance)
	end)
end

Private.Events.RegisterHandler(Private.Enum.DeferralKey.NameStrata, ApplyNameStrata)

--- Requests that pass. For the setting itself, and for anything that changes what `INHERIT` resolves to.
function Private.NameStyle.Request()
	Private.Events.Request(Private.Enum.DeferralKey.NameStrata)
end

--- Applies the font, size, placement, justification and *visibility* of the name, but not its colour.
---
--- The opposed anchors follow the selected row and preserve the selected point's offset. Keeping both
--- edges is important: a single anchor leaves the FontString unconstrained and allows names to bleed
--- outside the frame.
---
--- `nameEnabled` is applied here rather than by each caller, so the live frames, the grid previews and
--- the options pane all answer it from one place. `nameHoverOnly` is the live mixin's alone: a preview
--- has no cursor over it in the sense that setting means, and one that hid its name to be accurate
--- would be a preview of nothing.
---
--- The shadow is re-asserted after `SetFont`, which clears it.
---@param fontString FontString
---@param appearance SpotlightsAppearanceConfig
function Private.NameStyle.ApplyLayout(fontString, appearance)
	fontString:SetShown(appearance.nameEnabled)
	fontString:SetFont(Private.Media.Font(appearance.nameFont), appearance.nameFontSize, "")
	fontString:SetShadowColor(0, 0, 0, 1)
	fontString:SetShadowOffset(1, -1)
	fontString:SetWordWrap(false)

	local point = appearance.namePoint
	local parent = fontString:GetParent()
	local horizontal = point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER"
	local vertical = point:find("TOP") and "TOP" or point:find("BOTTOM") and "BOTTOM" or "CENTER"
	local firstPoint = vertical == "CENTER" and "LEFT" or vertical .. "LEFT"
	local secondPoint = vertical == "CENTER" and "RIGHT" or vertical .. "RIGHT"
	local firstX = horizontal == "RIGHT" and 0 or appearance.nameX
	local secondX = horizontal == "LEFT" and 0 or appearance.nameX
	local firstY = vertical == "BOTTOM" and 0 or appearance.nameY
	local secondY = vertical == "TOP" and 0 or appearance.nameY

	fontString:ClearAllPoints()
	PixelUtil.SetPoint(fontString, firstPoint, parent, firstPoint, firstX, firstY)
	PixelUtil.SetPoint(fontString, secondPoint, parent, secondPoint, secondX, secondY)
	fontString:SetJustifyH(JustifyForPoint(point))
end

--- Blizzard's own opt-out for the temporary maximum-health-loss bar, cached rather than asked for
--- per update.
---
--- `CVarCallbackRegistry:GetCVarValueBool` is not a cache read here. It only consults
--- `cvarValueCache` for CVars marked with `SetCVarCachable`, and **this CVar is not one of them** --
--- its single reader in the entire client is `UnitFrame.lua:29`. Every call is a `GetCVar` C call.
---
--- A tainted execution could not use that cache even if it existed: `GetCVarValue` populates it only
--- under `issecure()` (`CvarUtil.lua:150-152`), which is never us. So the only cache we can have is
--- our own.
---
--- Worth caching because UpdateTempMaxHealthLoss runs on UNIT_MAXHEALTH,
--- UNIT_MAX_HEALTH_MODIFIERS_CHANGED and every UpdateAll, for an answer that changes only when a
--- user opens the interface options.
local TEMP_MAX_HEALTH_LOSS_CVAR = "showTempMaxHealthLoss"
local showTempMaxHealthLoss = CVarCallbackRegistry:GetCVarValueBool(TEMP_MAX_HEALTH_LOSS_CVAR)

--- Both setters take secrets, so the values go straight in.
function SpotlightsUnitFrameMixin:UpdateHealthValues()
	local unit = self.displayedUnit

	if not unit then
		return
	end

	self.healthBar:SetMinMaxValues(0, UnitHealthMax(unit))
	self.healthBar:SetValue(UnitHealth(unit))
end

--- Health colour.
---
--- UnitClass's second return carries no secret annotation -- only the localised first one does --
--- so indexing RAID_CLASS_COLORS with it is legal. UnitIsConnected and UnitIsDead are documented as
--- never secret, so both branches are safe.
---
--- Three cases in priority order: a disconnected or dead unit is grey regardless of the setting;
--- otherwise the static colour wins when class colour is off; otherwise the class colour.
---
--- The background follows the bar in every case except static, where it is its own setting: class
--- and disconnected derive it as the bar colour at a fifth, which the static default reproduces.
function SpotlightsUnitFrameMixin:UpdateHealthColor()
	local unit = self.displayedUnit

	if not unit then
		return
	end

	local appearance = Appearance()
	local r, g, b, a
	local bgR, bgG, bgB, bgA

	if not UnitIsConnected(unit) or UnitIsDead(unit) then
		r, g, b, a = DISCONNECTED_COLOR.r, DISCONNECTED_COLOR.g, DISCONNECTED_COLOR.b, 1
		bgR, bgG, bgB, bgA = r * BACKGROUND_MULTIPLIER, g * BACKGROUND_MULTIPLIER, b * BACKGROUND_MULTIPLIER, 1
	elseif appearance and not appearance.healthUseClassColor then
		r, g, b, a = appearance.healthColorR, appearance.healthColorG, appearance.healthColorB, appearance.healthColorA
		bgR, bgG, bgB, bgA = appearance.healthBgColorR, appearance.healthBgColorG, appearance.healthBgColorB,
			appearance.healthBgColorA
	else
		local _, classFilename = UnitClass(unit)
		local color = classFilename and RAID_CLASS_COLORS[classFilename]

		if not color then
			return
		end

		r, g, b, a = color.r, color.g, color.b, 1
		bgR, bgG, bgB, bgA = r * BACKGROUND_MULTIPLIER, g * BACKGROUND_MULTIPLIER, b * BACKGROUND_MULTIPLIER, 1
	end

	self.healthBar:SetStatusBarColor(r, g, b, a)

	-- `raidframe-hp-bg-white` is a white texture meant to be tinted, and this is the only thing that
	-- tints it. Without this the frame reads as an empty white box.
	self.background:SetVertexColor(bgR, bgG, bgB, bgA)
end

--- The unit's name.
---
--- UnitName rather than GetUnitName: the realm suffix costs width the frame does not have, and every
--- spotlight is a group member whose bare name is unambiguous in practice.
---
--- The name may arrive secret, which is harmless here: SetText accepts it and nothing reads it back.
--- Never route a name through this into Private.Roster -- that side needs real strings to key on.
function SpotlightsUnitFrameMixin:UpdateName()
	local unit = self.displayedUnit

	if not unit then
		return
	end

	self.name:SetText(UnitName(unit))
end

local function HealthTextLayout(fontString, appearance)
	fontString:SetFont(Private.Media.Font(appearance.healthTextFont), appearance.healthTextFontSize, "OUTLINE")
	fontString:ClearAllPoints()
	PixelUtil.SetPoint(
		fontString,
		appearance.healthTextPoint,
		fontString:GetParent(),
		appearance.healthTextPoint,
		appearance.healthTextX,
		appearance.healthTextY
	)
	fontString:SetJustifyH(JustifyForPoint(appearance.healthTextPoint))
end

function SpotlightsUnitFrameMixin:UpdateHealthText()
	local unit = self.displayedUnit
	local appearance = Appearance()

	if not unit or not appearance then
		return
	end

	HealthTextLayout(self.healthText, appearance)

	local r, g, b, a = appearance.healthTextColorR, appearance.healthTextColorG, appearance.healthTextColorB,
		appearance.healthTextColorA
	if appearance.healthTextUseClassColor then
		local _, classFilename = UnitClass(unit)
		local color = classFilename and RAID_CLASS_COLORS[classFilename]
		if color then
			r, g, b, a = color.r, color.g, color.b, 1
		end
	end
	self.healthText:SetVertexColor(r, g, b, a)
	self.healthText:SetShown(appearance.healthTextEnabled)

	if not appearance.healthTextEnabled then
		return
	end

	if appearance.healthTextFormat == "percent" then
		self.healthText:SetFormattedText("%g%%", UnitHealthPercent(unit, true, healthPercentCurve))
	elseif appearance.healthTextFormat == "absValueAbbreviated" then
		self.healthText:SetText(AbbreviateNumbers(UnitHealth(unit)))
	else
		self.healthText:SetFormattedText("%d", UnitHealth(unit))
	end
end

--- The name's font, size, placement and colour -- everything about it except the text.
---
--- Split from `UpdateName` because the two change on different beats: the text follows
--- `UNIT_NAME_UPDATE`, the styling follows only a settings write. A class colour reads the same
--- non-secret `UnitClass` second return the health colour does.
---
--- Layout is shared with the preview through `Private.NameStyle`; only the colour is decided here.
--- A child with no unit keeps the static colour rather than guessing a class one. The name is not
--- greyed on disconnect: the health bar already says that, and grey on grey reads worse.
function SpotlightsUnitFrameMixin:UpdateNameStyle()
	local appearance = Appearance()

	if not appearance then
		return
	end

	Private.NameStyle.ApplyLayout(self.name, appearance)

	-- After `ApplyLayout`, which decides visibility from `nameEnabled` alone. Hover-only is the term it
	-- cannot know about.
	self:UpdateNameVisibility()

	local r, g, b, a = appearance.nameColorR, appearance.nameColorG, appearance.nameColorB, appearance.nameColorA
	local unit = self.displayedUnit

	if appearance.nameUseClassColor and unit then
		local _, classFilename = UnitClass(unit)
		local color = classFilename and RAID_CLASS_COLORS[classFilename]

		if color then
			r, g, b, a = color.r, color.g, color.b, 1
		end
	end

	-- SetVertexColor rather than SetTextColor, matching Blizzard's own name updater: it colours a
	-- FontString whose Text aspect may be secret, and the vertex colour is not that aspect.
	self.name:SetVertexColor(r, g, b, a)
end

--- Whether the name is drawn right now: the two toggles, and -- while hover-only is on -- whether the
--- cursor is over this spotlight.
---
--- **Nothing here is derived from the unit.** The name *text* may arrive secret, but the two settings
--- and the mouse state are ours, so `SetShown` on the FontString is legal and is what to use. There is
--- no secret in this path to justify an alpha trick, and reaching for one would make the FontString's
--- Alpha aspect secret for nothing.
---
--- Not a protected call: a FontString is a region, not a frame, and hiding one on a secure button is
--- what Blizzard's own name updater does.
function SpotlightsUnitFrameMixin:UpdateNameVisibility()
	local appearance = Appearance()

	if not appearance then
		return
	end

	self.name:SetShown(appearance.nameEnabled
		and (not appearance.nameHoverOnly or self.spotlightsHovered == true))
end

--- The outline shown while this unit is the player's target.
---
--- SetAlphaFromBoolean rather than SetShown. UnitIsUnit(unit, "target") may answer with a secret
--- depending on content type, which SetShown rejects outright. The value goes into the setter
--- instead, and the question stops being ours to ask.
function SpotlightsUnitFrameMixin:UpdateSelectionHighlight()
	local unit = self.displayedUnit

	if not unit then
		return
	end

	self.selectionHighlight:SetAlphaFromBoolean(UnitIsUnit(unit, "target"), 1, 0)
end

--- The absorb overlay.
---
--- UnitGetTotalAbsorbs is always secret but never needs arithmetic: on the same 0..maxHealth scale
--- as health, the secret goes straight into SetValue. That is why the incoming-heal overlay is out
--- and this is in -- prediction needs derived widths, and a width is a number you must compute.
---
--- Zero needs no special case: an empty bar is the correct rendering of no absorb.
function SpotlightsUnitFrameMixin:UpdateAbsorb()
	local unit = self.displayedUnit
	local absorbBar = self.spotlightsAbsorbBar

	if not unit or not absorbBar then
		return
	end

	absorbBar:SetMinMaxValues(0, UnitHealthMax(unit))
	absorbBar:SetValue(UnitGetTotalAbsorbs(unit))
end

--- Temporary maximum-health loss: the slice of the bar the unit cannot currently heal into.
---
--- Reimplemented from TempMaxHealthLossMixin (`UnitFrame.lua:25-53`): it pulls the health bar's
--- right edge in by the lost fraction and fills the gap, but also drives a divider texture that only
--- the player frame declares.
---
--- GetUnitTotalModifiedMaxHealthPercent carries no secret annotation, which makes the arithmetic
--- legal. **Never** substitute UNIT_MAX_HEALTH_MODIFIERS_CHANGED's arg2 -- that event is
--- SecretPayloads and the Clamp would be comparing a secret.
---
--- Blizzard's CVar opt-out is respected rather than reimplemented as a setting. Restoring the anchor
--- when it is off matters: the health bar keeps whatever edge the last update gave it, so disabling
--- the feature mid-session would otherwise keep a permanently short bar. That is also why the
--- callback below redraws rather than only updating the cache.
function SpotlightsUnitFrameMixin:UpdateTempMaxHealthLoss()
	local unit = self.displayedUnit

	if not unit then
		return
	end

	local lost = 0

	if showTempMaxHealthLoss then
		-- Loss only, never gain, which is also why a negative clamps away to nothing.
		lost = Clamp(GetUnitTotalModifiedMaxHealthPercent(unit), 0, 1)
	end

	-- Measured off the frame rather than the health bar, whose width is the very thing this is about
	-- to change -- reading it back would compound the inset on every update.
	local fullWidth = self:GetWidth() - (HEALTH_BAR_INSET * 2)

	PixelUtil.SetPoint(
		self.healthBar,
		"BOTTOMRIGHT",
		self,
		"BOTTOMRIGHT",
		-HEALTH_BAR_INSET - (fullWidth * lost),
		HEALTH_BAR_INSET
	)

	self.tempMaxHealthLoss:SetValue(lost)
	self.tempMaxHealthLoss:SetShown(lost > 0)
end

--- The frame's whole-frame fade: dead first, then out of range.
---
--- Both fades write `self`'s alpha, so they cannot be two independent setters -- the last to run
--- would win. Resolved here into one write. Dead takes precedence: a dead player also out of range
--- reads as dead.
---
--- Death is safe to branch on because `UnitIsDead` is documented as never secret, unlike range, so
--- it can gate which fade runs. Both branches write through `SetAlphaFromBoolean`: range makes this
--- frame's Alpha aspect secret, and the two branches must not disagree about whether it is secret
--- from one call to the next. Never read GetAlpha() on a spotlight.
function SpotlightsUnitFrameMixin:UpdateRangeAlpha()
	local unit = self.displayedUnit

	if not unit then
		return
	end

	local appearance = Appearance()

	if not appearance then
		return
	end

	-- A plain boolean, so it can gate which fade applies. `deadAlpha` in both slots so a dead unit
	-- reads the same whether or not it is also in range.
	if UnitIsDead(unit) then
		self:SetAlphaFromBoolean(false, appearance.frameAlpha, appearance.frameAlpha * appearance.deadAlpha)
		return
	end

	self:SetAlphaFromBoolean(IsInRange(unit), appearance.frameAlpha, appearance.frameAlpha * appearance.outOfRangeAlpha)
end

--- Bar art and the absorb overlay's visibility. Not per-unit, so safe on a child with nothing
--- assigned.
---
--- The texture goes on the health fill *and* the background, so a chosen texture reads as one bar
--- rather than a fill floating over Blizzard's art.
---
--- `SetStatusBarTexture` and `SetTexture` both reset the region's vertex colour to white, so this
--- ends in UpdateHealthColor -- otherwise changing texture silently turns every spotlight white
--- until the next health event.
function SpotlightsUnitFrameMixin:UpdateTexture()
	local appearance = Appearance()

	if not appearance then
		return
	end

	local path = Private.Media.StatusBar(appearance.barTexture)

	self.healthBar:SetStatusBarTexture(path)
	self.background:SetTexture(path)

	if self.spotlightsAbsorbBar then
		self.spotlightsAbsorbBar:SetShown(appearance.showAbsorb)
	end

	self:UpdateHealthColor()
end

--- Everything a freshly assigned unit needs.
function SpotlightsUnitFrameMixin:UpdateAll()
	if not self.displayedUnit then
		return
	end

	self:UpdateHealthValues()
	self:UpdateHealthColor()
	self:UpdateAbsorb()
	self:UpdateTempMaxHealthLoss()
	self:UpdateRangeAlpha()
	self:UpdateName()
	self:UpdateNameStyle()
	self:UpdateHealthText()
	self:UpdateSelectionHighlight()
end

--- One entry per whitelisted event, and no default case.
---@type table<string, fun(frame: SpotlightsUnitFrame)>
local EVENT_HANDLERS = {
	-- Colour follows health because death is only observable through it: UnitIsDead flips with the
	-- value and no separate event announces it.
	UNIT_HEALTH = function(frame)
		frame:UpdateHealthValues()
		frame:UpdateHealthColor()
		frame:UpdateHealthText()
		frame:UpdateRangeAlpha()
	end,

	-- Absorbs share the health bar's scale, so a max-health change moves them too.
	UNIT_MAXHEALTH = function(frame)
		frame:UpdateHealthValues()
		frame:UpdateAbsorb()
		frame:UpdateTempMaxHealthLoss()
		frame:UpdateHealthText()
	end,

	UNIT_CONNECTION = function(frame)
		frame:UpdateHealthValues()
		frame:UpdateHealthColor()
		frame:UpdateHealthText()
	end,

	UNIT_NAME_UPDATE = function(frame)
		frame:UpdateName()
	end,

	UNIT_ABSORB_AMOUNT_CHANGED = function(frame)
		frame:UpdateAbsorb()
	end,

	UNIT_MAX_HEALTH_MODIFIERS_CHANGED = function(frame)
		frame:UpdateTempMaxHealthLoss()
	end,

	-- SecretPayloads, used purely as a trigger: the payload is never read, and the answer is
	-- re-derived through IsInRange so the non-secret sources still get their chance.
	UNIT_IN_RANGE_UPDATE = function(frame)
		frame:UpdateRangeAlpha()
	end,

	UNIT_PHASE = function(frame)
		frame:UpdateRangeAlpha()
	end,

	PLAYER_TARGET_CHANGED = function(frame)
		frame:UpdateSelectionHighlight()
	end,

	UNIT_FACTION = function(frame)
		Private.Auras.UpdateAssistability(frame)
	end,

	UNIT_FLAGS = function(frame)
		Private.Auras.UpdateAssistability(frame)
	end,

	PLAYER_FLAGS_CHANGED = function(frame)
		Private.Auras.UpdateAssistability(frame)
	end,
}

---@param event string
function SpotlightsUnitFrameMixin:OnEvent(event)
	if not self.displayedUnit then
		return
	end

	local handler = EVENT_HANDLERS[event]

	if handler then
		handler(self)
	end
end

--- Registers the events that are not unit-filtered. Called once at child setup; the mirror handles
--- the unit-filtered set, which has to be re-registered per unit.
function SpotlightsUnitFrameMixin:RegisterGlobalEvents()
	for i = 1, #GLOBAL_EVENTS do
		self:RegisterEvent(GLOBAL_EVENTS[i])
	end
end

--- Creates the bar UpdateAbsorb drives. Once per child, from InitChild.
---
--- The one region the template cannot declare, because it has to read the health bar's orientation
--- and fill direction at construction time.
---
--- A StatusBar rather than the sized textures Blizzard's absorb overlay uses: those are positioned
--- by arithmetic on the absorb amount, which a secret value cannot be subjected to. This inherits
--- the health bar's scale and geometry, so UpdateAbsorb needs no maths.
function SpotlightsUnitFrameMixin:CreateAbsorbBar()
	if self.spotlightsAbsorbBar then
		return
	end

	local healthBar = self.healthBar
	local absorbBar = CreateFrame("StatusBar", nil, healthBar)

	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)

	-- Read off the health bar rather than assumed, so the two cannot drift if the health bar's
	-- orientation ever becomes a setting.
	absorbBar:SetOrientation(healthBar:GetOrientation())
	absorbBar:SetReverseFill(healthBar:GetReverseFill())

	-- A texture has to exist before SetTextureWithAddressModeOptions can point it at the atlas. Same
	-- call Blizzard makes for its own absorb fill, so it tiles the way the native shield does.
	absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")

	SetTextureWithAddressModeOptions(
		absorbBar:GetStatusBarTexture(),
		"raidframe-shield-fill",
		TextureKitConstants.IgnoreAtlasSize,
		TextureKitConstants.AddressModeWrap,
		TextureKitConstants.AddressModeWrap
	)

	absorbBar:SetStatusBarColor(1, 1, 1, ABSORB_ALPHA)

	self.spotlightsAbsorbBar = absorbBar
end

--- Mirrors the header's secure `unit` assignment into plain Lua fields.
---
--- Read rather than written, always. The header assigns `unit` securely; writing it back ourselves
--- would taint a value Blizzard set cleanly, and is combat-blocked besides.
---
--- The early-out is load-bearing. configureChildren writes SetAttribute("unit", ...)
--- unconditionally with no compare-before-write, so every displayed child is rewritten on every
--- header update even when nothing changed.
---@param value string? the new unit token, or nil when the child is released
function SpotlightsUnitFrameMixin:OnUnitAttributeChanged(value)
	-- Comparing the two is safe without an issecretvalue guard: SetAttribute is
	-- AllowedWhenUntainted, so a secret can never become a frame attribute in the first place.
	local changed = value ~= self.unit

	if not changed then
		return
	end

	self.unit = value
	self.displayedUnit = value

	-- Above the nil branch so it is told about a released unit too, and the aura container is not
	-- left watching someone who has left the group.
	Private.Auras.OnUnitChanged(self, value)

	if value == nil then
		for i = 1, #UNIT_EVENTS do
			self:UnregisterEvent(UNIT_EVENTS[i])
		end

		return
	end

	for i = 1, #UNIT_EVENTS do
		self:RegisterUnitEvent(UNIT_EVENTS[i], value)
	end

	self:UpdateAll()
end

CVarCallbackRegistry:RegisterCallback(TEMP_MAX_HEALTH_LOSS_CVAR, function(_, value)
	-- Blizzard's own conversion (`CvarUtil.lua:158-161`), not `not not value`: CVAR_UPDATE carries
	-- the value as a *string*, so "0" is the disabled case and is truthy in Lua.
	showTempMaxHealthLoss = value ~= nil and value ~= "0"

	Private.SlotHeader.ForEachChild(function(child)
		child:UpdateTempMaxHealthLoss()
	end)
end)
