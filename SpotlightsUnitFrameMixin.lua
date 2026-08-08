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
}

--- Not unit-filtered, so registered once per frame rather than re-registered by the mirror.
local GLOBAL_EVENTS = {
	"PLAYER_TARGET_CHANGED",
}

local DISCONNECTED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
local BACKGROUND_MULTIPLIER = 0.2

--- The health bar's inset on every side. Must match the template's healthBar anchors:
--- UpdateTempMaxHealthLoss re-anchors that bar and has to put it back exactly where the XML had it.
local HEALTH_BAR_INSET = 1

--- The absorb overlay's opacity.
local ABSORB_ALPHA = 0.6

--- The appearance block, or nil before the database has loaded.
---
--- Read per call rather than cached: every value is a setting the options frame can change at any
--- moment.
---@return SpotlightsAppearanceConfig?
local function Appearance()
	return Private.DB and Private.DB.appearance
end

--- Prescience. A single fixed ID rather than a per-class table: `C_Spell.IsSpellInRange` answers
--- non-nil only when the spell is known and castable, so a player who cannot cast this falls through
--- to the fallback path.
local RANGE_SPELL = 409311

--- CheckInteractDistance index 4, "follow", at 28 yards. Shorter than the 40 of most friendly
--- spells, so it only answers when the spell itself does not.
local FOLLOW_DISTANCE_INDEX = 4

--- Whether `unit` is close enough to matter, for alpha purposes only.
---
--- **The return may be a secret value.** Pipe it into `SetAlphaFromBoolean`; never compare it, cache
--- it as a plain bool, or store it in a table we later iterate.
---
--- Ordering is load-bearing: every step before the last answers with a plain boolean, keeping the
--- frame's Alpha aspect non-secret, and is skipped when its source turns out secret. Only
--- `UnitInRange` is unconditionally secret, and it is the last resort.
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

	-- Plain booleans, measured: the primary source. nil means the spell cannot be cast on this unit
	-- at all -- not the same answer as out of range -- so it falls through instead of resolving.
	local inSpellRange = C_Spell.IsSpellInRange(RANGE_SPELL, unit)

	if inSpellRange ~= nil then
		return inSpellRange
	end

	if not InCombatLockdown() then
		local canInteract = CheckInteractDistance(unit, FOLLOW_DISTANCE_INDEX)

		if not issecretvalue(canInteract) and canInteract ~= nil then
			-- Normalised rather than returned as-is: SetAlphaFromBoolean type-checks its first
			-- argument, and this API has returned a truthy number historically.
			return canInteract ~= false
		end
	end

	-- Unconditionally SecretReturns, and the only option left once we are in combat. Its second
	-- return is deliberately dropped: comparing checkedRange against inRange is what makes
	-- CompactUnitFrame_UpdateInRange throw.
	local inRange = UnitInRange(unit)

	return inRange
end

--- Name layout, factored out so the live frames and the preview style the name the same way.
---@class SpotlightsNameStyle
Private.NameStyle = {}

--- The horizontal justification implied by an anchor point.
---
--- A single-point anchor has no width to justify within, but justification decides which way the
--- text grows: a right-edge anchor reads correctly only if right-justified to grow leftward.
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

--- Applies the font, size, placement and justification of the name, but not its colour.
---
--- Single-anchored rather than spanning both edges as the template's XML does, because the point is
--- now a setting: the name grows from wherever it is anchored. `wordwrap` stays false, so a name too
--- long runs off one edge rather than wrapping.
---
--- The shadow is re-asserted after `SetFont`, which clears it.
---@param fontString FontString
---@param appearance SpotlightsAppearanceConfig
function Private.NameStyle.ApplyLayout(fontString, appearance)
	fontString:SetFont(Private.Media.Font(appearance.nameFont), appearance.nameFontSize, "")
	fontString:SetShadowColor(0, 0, 0, 1)
	fontString:SetShadowOffset(1, -1)

	fontString:ClearAllPoints()
	fontString:SetPoint(
		appearance.namePoint,
		fontString:GetParent(),
		appearance.namePoint,
		appearance.nameX,
		appearance.nameY
	)
	fontString:SetJustifyH(JustifyForPoint(appearance.namePoint))
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
	local r, g, b
	local bgR, bgG, bgB

	if not UnitIsConnected(unit) or UnitIsDead(unit) then
		r, g, b = DISCONNECTED_COLOR.r, DISCONNECTED_COLOR.g, DISCONNECTED_COLOR.b
		bgR, bgG, bgB = r * BACKGROUND_MULTIPLIER, g * BACKGROUND_MULTIPLIER, b * BACKGROUND_MULTIPLIER
	elseif appearance and not appearance.healthUseClassColor then
		r, g, b = appearance.healthColorR, appearance.healthColorG, appearance.healthColorB
		bgR, bgG, bgB = appearance.healthBgColorR, appearance.healthBgColorG, appearance.healthBgColorB
	else
		local _, classFilename = UnitClass(unit)
		local color = classFilename and RAID_CLASS_COLORS[classFilename]

		if not color then
			return
		end

		r, g, b = color.r, color.g, color.b
		bgR, bgG, bgB = r * BACKGROUND_MULTIPLIER, g * BACKGROUND_MULTIPLIER, b * BACKGROUND_MULTIPLIER
	end

	self.healthBar:SetStatusBarColor(r, g, b)

	-- `raidframe-hp-bg-white` is a white texture meant to be tinted, and this is the only thing that
	-- tints it. Without this the frame reads as an empty white box.
	self.background:SetVertexColor(bgR, bgG, bgB)
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

	local r, g, b = appearance.nameColorR, appearance.nameColorG, appearance.nameColorB
	local unit = self.displayedUnit

	if appearance.nameUseClassColor and unit then
		local _, classFilename = UnitClass(unit)
		local color = classFilename and RAID_CLASS_COLORS[classFilename]

		if color then
			r, g, b = color.r, color.g, color.b
		end
	end

	-- SetVertexColor rather than SetTextColor, matching Blizzard's own name updater: it colours a
	-- FontString whose Text aspect may be secret, and the vertex colour is not that aspect.
	self.name:SetVertexColor(r, g, b)
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

	self.healthBar:SetPoint(
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
		self:SetAlphaFromBoolean(false, 1.0, appearance.deadAlpha)
		return
	end

	self:SetAlphaFromBoolean(IsInRange(unit), 1.0, appearance.outOfRangeAlpha)
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
		frame:UpdateRangeAlpha()
	end,

	-- Absorbs share the health bar's scale, so a max-health change moves them too.
	UNIT_MAXHEALTH = function(frame)
		frame:UpdateHealthValues()
		frame:UpdateAbsorb()
		frame:UpdateTempMaxHealthLoss()
	end,

	UNIT_CONNECTION = function(frame)
		frame:UpdateHealthValues()
		frame:UpdateHealthColor()
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
	-- left watching someone who has left the raid.
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

	-- Range is the one thing UpdateAll cannot get right on the first try, and it needs a second
	-- attempt rather than a better first one.
	--
	-- configureChildren assigns the unit at :213 and only calls Show() at :224, so this runs against
	-- a unit the client has had no frame to answer range questions about yet -- and
	-- UNIT_IN_RANGE_UPDATE is edge-triggered, so a premature answer here is never revisited.
	--
	-- One deferred re-assert closes that window. It fires once per changed unit, which the early-out
	-- above makes true. UpdateRangeAlpha re-reads displayedUnit, so a unit that changed again or was
	-- released in the meantime is handled by the same call.
	RunNextFrame(function()
		self:UpdateRangeAlpha()
	end)
end

--- Keeps the cached CVar current, and redraws on the change.
---
--- This puts a tainted closure of ours into a registry Blizzard owns and every addon shares -- the
--- exact shape WU-5b was written to escape. **CVarCallbackRegistry is built to take tainted
--- registrants.** `RegisterCallback` routes the event-key insert through an attribute delegate,
--- commented in Blizzard's source as a "taint barrier" (`CallbackRegistry.lua:106-126`), and
--- `TriggerEvent` dispatches every callback through `securecallfunction` inside a
--- `secureexecuterange` (`CallbackRegistry.lua:198-204`) -- so our taint cannot reach the iteration
--- or any other registrant. `standardIconAnchor` was a bare module-level table handed straight to a
--- C function, with no barrier.
---
--- The rule: **sharing state with Blizzard is safe exactly where Blizzard wrote a barrier for it,
--- and nowhere else.**
---
--- The discarded first parameter is the **owner**, not the value: the dispatch is
--- `securecallfunction(func, owner, ...)` (`CallbackRegistry.lua:209-210`), and omitting `owner` at
--- registration means it is a generated numeric ID rather than nil. Taking `value` as the first
--- parameter would silently compare that ID against "0" and leave the feature permanently enabled.
CVarCallbackRegistry:RegisterCallback(TEMP_MAX_HEALTH_LOSS_CVAR, function(_, value)
	-- Blizzard's own conversion (`CvarUtil.lua:158-161`), not `not not value`: CVAR_UPDATE carries
	-- the value as a *string*, so "0" is the disabled case and is truthy in Lua.
	showTempMaxHealthLoss = value ~= nil and value ~= "0"

	Private.SlotHeader.ForEachChild(function(child)
		child:UpdateTempMaxHealthLoss()
	end)
end)
