---@type string, Spotlights
local _, Private = ...

---@class SpotlightsEnums
Private.Enum = {}

--- An axis, shared by the grid's fill direction -- where `stride` means columns when horizontal and rows
--- when vertical -- and an aura bar's. The labels are not shared: "Across, Then Down" says nothing about a
--- bar.
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

---@alias SpotlightsAuraDisplayKey "bar" | "icon" | "square" | "text" | "frameColor"
---@alias SpotlightsAuraFeatureKey "prescience" | "shiftingSands" | "sensePower" | "cooldownAuras" | "defensiveAuras" | "customAuras"

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

--- Drain order, and why the queue is a set not a list. Config leads, because Build and Refresh read the
--- option table it may have changed; geometry must never run against a roster the registry has not rebuilt.
---
--- Position is last of the geometry passes because clamping needs the container's *final* size, which
--- Layout decides. NameStrata follows it because a name layer set to inherit takes the strata Position just
--- wrote.
---
--- Auras is last outright but under no ordering constraint -- nothing it reads or writes crosses this
--- queue. It is here so a pass blocked by combat resumes with everything else.
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

--- A set, so a stored position can be validated before SetPoint, which errors outright on an unrecognised
--- point and takes the container pass with it. Nine rather than WoW's full set: the only ones `CalcPoint`
--- produces.
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

--- The same nine in reading order. Separate from `AnchorPoints` because `pairs` over that set would
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

--- Stacking order, which is both what the dropdown offers and how "the strata above this one" is answered
--- for the preview overlay. Blizzard's list without `PARENT`, an instruction rather than a layer, and
--- without `BLIZZARD`, which is the game's own.
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

--- What `appearance.nameStrata` holds when the name layer is to set no strata of its own. A value rather
--- than a nil, which would be indistinguishable from a field that never arrived and re-filled every load.
--- Deliberately not one of `FrameStrataOrder`'s names, so it can never reach `SetFrameStrata`.
Private.Enum.NameStrataInherit = "INHERIT"

--- The same strata as a set, for validating a stored one before `SetFrameStrata`, which errors outright on
--- a name it does not know. Derived rather than hand-kept, since the order above *is* the meaning.
---@type table<string, boolean>
Private.Enum.FrameStrata = {}

for i = 1, #Private.Enum.FrameStrataOrder do
	Private.Enum.FrameStrata[Private.Enum.FrameStrataOrder[i]] = true
end

--- A name no player can hold, used as the `nameList` for blank and retired slots. **Never leave `nameList`
--- nil**: with `groupFilter` and `roleFilter` also nil, SecureGroupHeader_Update falls back to groupFilter
--- "1,2,3,4,5,6,7,8" and renders the entire group into one slot.
Private.Enum.NameListSentinel = "\1"
