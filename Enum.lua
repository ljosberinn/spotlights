---@type string, Spotlights
local _, Private = ...

---@class SpotlightsEnums
Private.Enum = {}

--- An axis, used for two unrelated things. As the grid's fill direction: horizontal fills across then
--- wraps down, vertical fills down then wraps across, and `stride` means columns when horizontal, rows
--- when vertical. As an aura status bar's fill direction: which way the bar drains.
---
--- Shared rather than duplicated per setting, since both are the same two-valued choice -- but the
--- labels are not shared, because "Across, Then Down" says nothing about a bar.
---@enum SpotlightsOrientation
Private.Enum.Orientation = {
	Horizontal = 1,
	Vertical = 2,
}

--- Which way the grid grows from its anchor. Directions, not frame points: Layout maps them to an
--- anchor corner, since growing right means anchoring left.
---@enum GrowX
Private.Enum.GrowX = {
	Right = "RIGHT",
	Left = "LEFT",
}

---@enum GrowY
Private.Enum.GrowY = {
	Down = "DOWN",
	Up = "UP",
}

--- What a configured slot holds. `Blank` is a user-placed spacer that reserves its grid cell;
--- `Retired` is a pooled header kept alive but hidden, since frames cannot be destroyed.
---@alias SlotKind "player" | "blank" | "retired"

---@alias HealthTextFormat
---| "percent"
---| "absValue"
---| "absValueAbbreviated"

---@alias SpotlightsAuraDisplayKey "bar" | "icon" | "square"
---@alias SpotlightsAuraFeatureKey "prescience" | "shiftingSands" | "sensePower" | "cooldownAuras" | "defensiveAuras"

--- Work deferred past combat, and the throttle keys used out of combat. Both queues drain through
--- the same ordered dispatch.
---@enum DeferralKey
Private.Enum.DeferralKey = {
	Config = "config",
	Build = "build",
	Registry = "registry",
	Geometry = "geometry",
	Layout = "layout",
	Position = "position",
	NameStrata = "nameStrata",
	Auras = "auras",
}

--- Drain order, and why the queue is a set not a list: geometry must never run against a roster
--- the registry has not rebuilt. Config leads, because Build and Refresh read the option table it
--- may have just changed.
---
--- Position is last of the geometry passes because clamping the container to the screen needs its
--- *final* size, and Layout sizes it. The other order clamps against the previous slot count.
---
--- NameStrata follows Position and does have an ordering constraint: a name layer set to inherit takes
--- the strata the container currently has, and Position is the pass that changes it. The other order
--- pins every inheriting name to the strata the grid just left.
---
--- Auras is last outright, but not by ordering constraint: nothing it does is read by another pass
--- and nothing it reads is written by one. A spotlight gains aura displays from the unit the secure
--- header assigned it, which arrives by attribute, not this queue. It is here only so a pass blocked
--- by combat resumes with everything else.
Private.Enum.DeferralOrder = {
	Private.Enum.DeferralKey.Config,
	Private.Enum.DeferralKey.Build,
	Private.Enum.DeferralKey.Registry,
	Private.Enum.DeferralKey.Geometry,
	Private.Enum.DeferralKey.Layout,
	Private.Enum.DeferralKey.Position,
	Private.Enum.DeferralKey.NameStrata,
	Private.Enum.DeferralKey.Auras,
}

--- The anchor points a saved position may name, as a set so a stored value can be validated before
--- SetPoint -- which errors outright on an unrecognised point and takes the container pass with it.
---
--- Nine rather than WoW's full set: the only ones CalcPoint produces (a vertical half and a
--- horizontal third combine into a corner, an edge midpoint, or the centre).
---@type table<string, boolean>
Private.Enum.AnchorPoints = {
	TOPLEFT = true,
	TOP = true,
	TOPRIGHT = true,
	LEFT = true,
	CENTER = true,
	RIGHT = true,
	BOTTOMLEFT = true,
	BOTTOM = true,
	BOTTOMRIGHT = true,
}

--- The same nine points in dropdown order: reading order, top-left first.
---
--- Separate from `AnchorPoints` because that is a set (for validation) and `pairs` over it would
--- reshuffle the menu between sessions.
---@type AnchorPoint[]
Private.Enum.AnchorPointOrder = {
	"TOPLEFT",
	"TOP",
	"TOPRIGHT",
	"LEFT",
	"CENTER",
	"RIGHT",
	"BOTTOMLEFT",
	"BOTTOM",
	"BOTTOMRIGHT",
}

--- The strata a spotlight may be placed in, in stacking order -- which is both the order the strata
--- dropdown offers and how "the strata above this one" is answered for the preview overlay.
---
--- Blizzard's list without `PARENT`, which is an instruction rather than a layer, and without
--- `BLIZZARD`, which sits above everything and is the game's own.
---@type FrameStrata[]
Private.Enum.FrameStrataOrder = {
	"BACKGROUND",
	"LOW",
	"MEDIUM",
	"HIGH",
	"DIALOG",
	"FULLSCREEN",
	"FULLSCREEN_DIALOG",
	"TOOLTIP",
}

--- What `appearance.nameStrata` holds when the name layer is to set no strata of its own.
---
--- A member of the setting's value space rather than a nil, so the dropdown has an entry to select and
--- `Filled` has something to fill an older database with -- a nil would be indistinguishable from a
--- field that never arrived, and would be re-filled on every load.
---
--- Deliberately not one of `FrameStrataOrder`'s names, so it can never be handed to `SetFrameStrata`.
Private.Enum.NameStrataInherit = "INHERIT"

--- The same strata as a set, for validating a stored one before `SetFrameStrata`, which errors
--- outright on a name it does not know and takes the container pass with it.
---
--- Derived rather than written out a second time: unlike the anchor points, the order here *is* the
--- meaning, so a hand-kept set could disagree with it about which strata exist.
---@type table<string, boolean>
Private.Enum.FrameStrata = {}

for i = 1, #Private.Enum.FrameStrataOrder do
	Private.Enum.FrameStrata[Private.Enum.FrameStrataOrder[i]] = true
end

--- A name no player can hold, used as the `nameList` value for blank and retired slots. Never
--- leave `nameList` nil: with `groupFilter` and `roleFilter` also nil, SecureGroupHeader_Update
--- falls back to groupFilter "1,2,3,4,5,6,7,8" and renders the entire group into one slot.
Private.Enum.NameListSentinel = "\1"
