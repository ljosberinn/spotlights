---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuras
Private.Auras = {}

--- Tracked aura displays: which spells a spotlight watches for, and what it draws when one lands.
---
--- A specialisation change swaps the active feature set. Existing containers cannot be removed
--- (`CustomAuraContainerInboundMixin` exposes `AddAuraSlot` and no inverse), so old records are hidden
--- and discarded from the active record map before the new set is built.

local DeferralKey = Private.Enum.DeferralKey

-- Note the absence of `local Enum = Private.Enum`, which the rest of the addon does freely. This
-- file needs the *game's* `Enum` for the status bar options below; shadowing it here would turn
-- `Enum.StatusBarInterpolation` into a nil index at the one call site that matters.

--- Prescience's slot shows only the copy *we* applied, and `PLAYER` says so. It also keeps the class
--- gate a pure cost decision rather than a behaviour change.
local OWN_FILTER =
	AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful, AuraUtil.AuraFilters.Player)

--- Sense Power's slot pools the spotlighted player's own major cooldowns beside Sense Power, none of
--- them cast by us. `PLAYER` admits only auras cast by the player, pet or vehicle, so it would
--- discard every cooldown before `includeSpellIDs` was consulted -- the slot would show Sense Power
--- alone and read as a sorting bug.
---
--- The spell-ID set does the narrowing instead, more tightly: it names the exact auras rather than
--- trusting the caster. What it no longer excludes is another Evoker's Sense Power on the same unit.
local ANY_FILTER = AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful)

--- One tracked aura: which config block is its own, which spell it watches for, and what its slot is
--- allowed to show.
---@class SpotlightsAuraFeature
---@field key SpotlightsAuraFeatureKey indexes `SpotlightsAurasConfig`, and names the slot inside its container
---@field spellID integer the spell the display is *about*: its icon, and its preview
---@field filter string the aura filter string its slot parses with
---@field Candidates fun(): table<integer, true> every spell its slot may show, `spellID` included
---@field multiple boolean

--- Which pass a changed setting needs: a re-anchor on the next frame, or a replacement container once
--- the value stops moving.
---@alias SpotlightsAuraInvalidation "live" | "rebuild"

--- One kind of display, and the only place the difference between a bar, an icon, a square and a bare
--- countdown lives.
---
--- `config` is loose: the four kinds are configured by different shapes, and a narrower annotation
--- would be a lie in three directions. The four verbs are split because a live display and a preview
--- need different subsets — a live display runs `Create`, `Style`, `Register` once and is then
--- untouchable, while a preview runs `Create`/`Preview` once and `Style` on every settings change.
--- Sharing `Style` is what makes a preview show what will ship.
---@class SpotlightsAuraKind
---@field key SpotlightsAuraDisplayKey
---@field Create fun(host: Frame|table, config: table, spellID: integer, everything: boolean): SpotlightsAuraRegions
---@field Style fun(regions: SpotlightsAuraRegions, anchor: Frame, config: table)
---@field Register fun(button: table, regions: SpotlightsAuraRegions)
---@field Preview fun(regions: SpotlightsAuraRegions, config: table)
---@field PreviewArt? fun(regions: SpotlightsAuraRegions, spellID: integer) absent on a display drawing no spell art
---@field Size fun(config: table, size: SpotlightsChildSize): number, number
---@field Invalidation fun(feature: SpotlightsAuraFeature, field: string): SpotlightsAuraInvalidation which pass one of this kind's settings needs
---@field Invalidated? fun(config: table, record: SpotlightsAuraDisplay): boolean whether a resize has broken something built-in

---@type table<integer, table<integer, boolean>>
local COOLDOWNS = {
	[Constants.UICharacterClasses.Warrior] = {
		[1719] = true, -- Recklessness
		[107574] = true, -- Avatar
		[227847] = true, -- Bladestorm
		[228920] = true, -- Ravager
		[389722] = true, -- Recklessness
	},
	[Constants.UICharacterClasses.Paladin] = {
		[31884] = true, -- Avenging Wrath
		[231895] = true, -- Avenging Wrath
		[454351] = true, -- Avenging Wrath
		[454373] = true, -- Avenging Wrath
	},
	[Constants.UICharacterClasses.Hunter] = {
		[19574] = true, -- Bestial Wrath
		[266779] = true, -- Coordinated Assault
		[288613] = true, -- Trueshot
		[359844] = true, -- Call of the Wild
		[360952] = true, -- Coordinated Assault
		[1250646] = true, -- Takedown
		[1251703] = true, -- Takedown
	},
	[Constants.UICharacterClasses.Rogue] = {
		[13750] = true, -- Adrenaline Rush
		[79140] = true, -- Vendetta
		[121471] = true, -- Shadow Blades
		[360194] = true, -- Deathmark
		[1249810] = true, -- Finish the Job
	},
	[Constants.UICharacterClasses.Priest] = {
		[194249] = true, -- Voidform
		[391109] = true, -- Dark Ascension
	},
	[Constants.UICharacterClasses.DeathKnight] = {
		[42650] = true, -- Army of the Dead, MISSING in-game
		[51271] = true, -- Pillar of Frost
		[1235391] = true, -- Dark Transformation
		[1249658] = true, -- Breath of Sindragosa, MISSING in-game
	},
	[Constants.UICharacterClasses.Shaman] = {
		[114051] = true, -- Ascendance
		[466772] = true, -- Doom Winds
		[1219480] = true, -- Ascendance, MISSING in-game; ele only
	},
	[Constants.UICharacterClasses.Mage] = {
		[12472] = true, -- Icy Veins
		[190319] = true, -- Combustion
		[198144] = true, -- Ice Form
		[365362] = true, -- Arcane Surge
	},
	[Constants.UICharacterClasses.Warlock] = {
		[205180] = true, -- Summon Darkglare
		[387278] = true, -- Summon Darkglare
	},
	[Constants.UICharacterClasses.Monk] = {
		[137639] = true, -- Storm, Earth, and Fire
		[1249625] = true, -- Zenith
	},
	[Constants.UICharacterClasses.Druid] = {
		[50334] = true, -- Berserk
		[102543] = true, -- Incarnation: Avatar of Ashamane
		[102560] = true, -- Incarnation: Chosen of Elune
		[106951] = true, -- Berserk
		[194223] = true, -- Celestial Alignment
		[383410] = true, -- Celestial Alignment
		[390414] = true, -- Incarnation: Chosen of Elune
	},
	[Constants.UICharacterClasses.DemonHunter] = {
		[162264] = true, -- Metamorphosis
		[1217607] = true, -- Void Metamorphosis
	},
	[Constants.UICharacterClasses.Evoker] = {
		[375087] = true, -- Dragonrage
		[1259171] = true, -- Duplicate; the data has Breath of Eons but thats obviously silly
	},
}

--- The game's own Big Defensive list, amended by hand. Its flag covers personal and single-target
--- external mitigation only, so the group-wide effects it misses are added here and ship on like
--- everything else -- being inside one is exactly what a healer reads off a spotlight.
---@type table<integer, table<integer, boolean>>
local DEFENSIVES = {
	[Constants.UICharacterClasses.Warrior] = {
		[871] = true, -- Shield Wall
		[118038] = true, -- Die by the Sword
		[184364] = true, -- Enraged Regeneration
	},
	[Constants.UICharacterClasses.Paladin] = {
		[498] = true, -- Divine Protection
		[642] = true, -- Divine Shield
		[1022] = true, -- Blessing of Protection
		[6940] = true, -- Blessing of Sacrifice
		[31850] = true, -- Ardent Defender
		[86659] = true, -- Guardian of Ancient Kings
		[184662] = true, -- Shield of Vengeance
		[199448] = true, -- Blessing of Sacrifice
		[204018] = true, -- Blessing of Spellwarding
		[212641] = true, -- Guardian of Ancient Kings
	},
	[Constants.UICharacterClasses.Hunter] = {
		[53480] = true, -- Roar of Sacrifice
		[186265] = true, -- Aspect of the Turtle
		[264735] = true, -- Survival of the Fittest
	},
	[Constants.UICharacterClasses.Rogue] = {
		[1966] = true, -- Feint
		[31224] = true, -- Cloak of Shadows
		-- [81549] = false, -- Cloak of Shadows - is in the data, but wrong
	},
	[Constants.UICharacterClasses.Priest] = {
		[19236] = true, -- Desperate Prayer
		[33206] = true, -- Pain Suppression
		[47585] = true, -- Dispersion
		[47788] = true, -- Guardian Spirit
		[81782] = true, -- Power Word: Barrier, the buff on players inside it; unflagged, group-wide
	},
	[Constants.UICharacterClasses.DeathKnight] = {
		[48707] = true, -- Anti-Magic Shell
		[48792] = true, -- Icebound Fortitude
		[55233] = true, -- Vampiric Blood
		[145629] = true, -- Anti-Magic Zone, the buff on allies inside it; unflagged, group-wide
		[444741] = true, -- Anti-Magic Shell proc
	},
	[Constants.UICharacterClasses.Shaman] = {
		[108271] = true, -- Astral Shift
	},
	[Constants.UICharacterClasses.Mage] = {
		[45438] = true, -- Ice Block
		[342246] = true, -- Alter Time
		[414658] = true, -- Ice Cold
	},
	[Constants.UICharacterClasses.Warlock] = {
		[104773] = true, -- Unending Resolve
	},
	[Constants.UICharacterClasses.Monk] = {
		[115203] = true, -- Fortifying Brew
		[116849] = true, -- Life Cocoon
		[120954] = true, -- Fortifying Brew
		[125174] = true, -- Touch of Karma
		[243435] = true, -- Fortifying Brew
	},
	[Constants.UICharacterClasses.Druid] = {
		[22812] = true, -- Barkskin
		[50322] = true, -- Survival Instincts
		[61336] = true, -- Survival Instincts
		[102342] = true, -- Ironbark
	},
	[Constants.UICharacterClasses.DemonHunter] = {
		[207771] = true, -- Fiery Brand
		[209426] = true, -- Darkness, the buff on players inside it; unflagged, group-wide
		[212800] = true, -- Blur
	},
	[Constants.UICharacterClasses.Evoker] = {
		[357170] = true, -- Time Dilation
		[363916] = true, -- Obsidian Scales
		[374227] = true, -- Zephyr
	},
}

--- The current aura settings, or nil before the migration has run.
---
--- Ahead of the feature list below because a function referencing it has to be declared after it --
--- a local is not in scope above its declaration.
---@return SpotlightsAurasConfig?
local function Config()
	return Private.DB and Private.DB.auras
end

--- One spell pool: a shipped catalogue grouped by class, sparse overrides over it, and the user's own
--- IDs beside it.
---
--- Cooldowns and defensives are the same concern at runtime and differ only in what a catalogue entry
--- *means*, so that difference lives in `DefaultEnabled` and every operation below is written once. A
--- cooldown ships on -- `COOLDOWNS` is a membership list -- while a defensive ships on or off per
--- spell, because the ones the game does not count as defensives were added by hand.
---
--- The two pools keep separate saved-variable tables and separate features. This is shared behaviour,
--- not a merged pool.
---@class SpotlightsAuraPool
---@field catalog table<integer, table<integer, boolean>> the shipped spells, grouped by class
---@field overridesKey string the `SpotlightsAurasConfig` field holding deviations from the catalogue
---@field customKey string the `SpotlightsAurasConfig` field holding the user's own spell IDs
---@field DefaultEnabled fun(shipped: boolean): boolean what a catalogue entry says about its default

---@type table<string, SpotlightsAuraPool>
local POOLS = {
	cooldown = {
		catalog = COOLDOWNS,
		overridesKey = "cooldowns",
		customKey = "custom",
		DefaultEnabled = function()
			return true
		end,
	},

	defensive = {
		catalog = DEFENSIVES,
		overridesKey = "defensives",
		customKey = "defensiveCustom",
		DefaultEnabled = function(shipped)
			return shipped
		end,
	},
}

--- A pool's two saved tables, or nils before the migration has run.
---
--- The one place either table is reached by key. Both are guaranteed by the migration and refilled by
--- `Repair` on every load, so the nil case is the window before either has run -- a refresh driven by a
--- slash command during login, which is a real order.
---@param pool SpotlightsAuraPool
---@return table<integer, boolean>? overrides, table<integer, boolean>? custom
local function PoolTables(pool)
	local auras = Config()

	if not auras then
		return nil, nil
	end

	return auras[pool.overridesKey], auras[pool.customKey]
end

--- Whether the pool ships this spell, and switched on or off if so.
---@param pool SpotlightsAuraPool
---@param spellID integer
---@return boolean? default nil when the spell is not in the catalogue at all
local function ShippedDefault(pool, spellID)
	for _, spells in pairs(pool.catalog) do
		local shipped = spells[spellID]

		if shipped ~= nil then
			return pool.DefaultEnabled(shipped)
		end
	end

	return nil
end

--- Every spell in the pool a slot may currently show.
---
--- Read from the database on every call: the set is what a slot's `includeSpellIDs` is built from, so
--- recomputing here is what makes a toggle reach a live display. Cached, it could disagree.
---
--- Not narrowed to the watched unit's class. A container can be repointed at another player
--- (`OnUnitChanged` does so on every roster change), so a per-class set would have to be recomputed in
--- the right order relative to `SetUnit`. The union costs nothing to be right instead: no spell belongs
--- to two classes and nobody changes class. The class grouping in the catalogues is for readers and the
--- options panel, not for this lookup.
---
--- An absent override means the shipped default, which is why a catalogue needs no migration when it
--- grows: the override table holds only the user's own decisions.
---@param pool SpotlightsAuraPool
---@param candidates table<integer, true>? a set to add to, for a slot pooling more than this pool
---@return table<integer, true>
local function PoolCandidates(pool, candidates)
	candidates = candidates or {}
	local overrides, custom = PoolTables(pool)

	for _, spells in pairs(pool.catalog) do
		for spellID, shipped in pairs(spells) do
			local enabled = overrides and overrides[spellID]

			if enabled == nil then
				enabled = pool.DefaultEnabled(shipped)
			end

			if enabled then
				candidates[spellID] = true
			end
		end
	end

	-- The opposite default to the built-ins: nothing the user added counts until they say so, because
	-- an ID typed into a box is a guess until it has been seen to work.
	if custom then
		for spellID, enabled in pairs(custom) do
			if enabled then
				candidates[spellID] = true
			end
		end
	end

	return candidates
end

--- Whether one spell in the pool is switched on.
---
--- The asymmetry between the two lists lives here and nowhere else: a built-in is on unless it deviates
--- from its catalogue entry, and a custom entry is off unless switched on. Both callers -- the panel
--- drawing a checkbox and `PoolCandidates` building the set -- have to agree, so they ask the same
--- function.
---@param pool SpotlightsAuraPool
---@param spellID integer
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean
local function IsPoolEnabled(pool, spellID, custom)
	local overrides, entries = PoolTables(pool)

	if custom then
		return entries ~= nil and entries[spellID] == true
	end

	local default = ShippedDefault(pool, spellID)

	if default == nil then
		return false
	end

	local override = overrides and overrides[spellID]

	if override ~= nil then
		return override
	end

	return default
end

--- Switches one pooled spell on or off, and lands it on every live display.
---
--- A built-in returning to its default is **cleared rather than stored**, which keeps the override
--- table holding only the user's actual decisions -- and therefore keeps a spell added to a catalogue
--- in a later version at its shipped default for someone who once toggled a different one.
---
--- A built-in the catalogue does not list is refused. An override on one could never reach a candidate
--- set, so writing it would leave a saved variable saying something the addon does not act on.
---@param pool SpotlightsAuraPool
---@param spellID integer
---@param enabled boolean
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean applied
local function SetPoolEnabled(pool, spellID, enabled, custom)
	local overrides, entries = PoolTables(pool)

	if not overrides or not entries then
		return false
	end

	if custom then
		if entries[spellID] == nil then
			return false
		end

		entries[spellID] = enabled
	else
		local default = ShippedDefault(pool, spellID)

		if default == nil then
			return false
		end

		-- Spelled out rather than folded into an `and`/`or`: neither operator can yield nil from a
		-- truthy branch, so `enabled ~= default and enabled or nil` stores *nil* when switching a
		-- default-on spell off -- which reads as "default" to everything downstream and would leave the
		-- spell enabled.
		if enabled == default then
			overrides[spellID] = nil
		else
			overrides[spellID] = enabled
		end
	end

	Private.Auras.RefreshCandidates()

	return true
end

--- The user's own spell IDs, in ascending order.
---
--- Sorted rather than iterated, because `pairs` over an integer-keyed map has no order the user would
--- recognise and a list that reshuffled itself whenever the panel reopened would look broken.
---@param pool SpotlightsAuraPool
---@return integer[]
local function CustomPoolSpells(pool)
	local _, entries = PoolTables(pool)
	local spellIDs = {}

	if entries then
		for spellID in pairs(entries) do
			spellIDs[#spellIDs + 1] = spellID
		end
	end

	table.sort(spellIDs)

	return spellIDs
end

--- Adds a spell the user typed in, switched on.
---
--- Enabled immediately, unlike the custom default of off, because adding one *is* the act of asking for
--- it -- the default only governs an entry that arrived some other way, such as a hand-edited database.
---@param pool SpotlightsAuraPool
---@param spellID integer
---@return boolean added false when it is already in the list
local function AddCustomPoolSpell(pool, spellID)
	local _, entries = PoolTables(pool)

	if not entries or entries[spellID] ~= nil then
		return false
	end

	entries[spellID] = true

	Private.Auras.RefreshCandidates()

	return true
end

--- Removes one of the user's own entries.
---
--- No reload is owed, though this is the case that looks most like it should: a spell *shown* this
--- session leaves a slot currently displaying it. Clearing it from the filters is what
--- `SetCandidateFilters` already does -- it drops every candidate and re-acquires from the next aura
--- scan -- so the display empties on its own.
---@param pool SpotlightsAuraPool
---@param spellID integer
---@return boolean removed
local function RemoveCustomPoolSpell(pool, spellID)
	local _, entries = PoolTables(pool)

	if not entries or entries[spellID] == nil then
		return false
	end

	entries[spellID] = nil

	Private.Auras.RefreshCandidates()

	return true
end

--- Puts every shipped spell in the pool back to its default, which is not the same as on: three
--- defensives ship switched off, so this restores a *mix* rather than enabling everything.
---
--- Clearing the override table *is* the reset: it holds only the user's deviations, so an empty one
--- means the catalogue as shipped -- and a spell added in a later version is unaffected either way,
--- since it was never in there.
---
--- The user's own entries are left alone, and the panel offering this says so. They have no shipped
--- default to return to: an entry exists only because it was typed in, so the only thing "default"
--- could mean for one is deleting it, which is not what a reset button is for.
---@param pool SpotlightsAuraPool
---@return boolean applied
local function ResetPool(pool)
	local overrides = PoolTables(pool)

	-- Nothing overridden is already the default state, and refreshing every live display to say so
	-- would be a sweep over the whole raid for no change.
	if not overrides or next(overrides) == nil then
		return false
	end

	-- Emptied rather than replaced, so the table the migration installed stays the one in the database.
	for spellID in pairs(overrides) do
		overrides[spellID] = nil
	end

	Private.Auras.RefreshCandidates()

	return true
end

---@return table<integer, true>
local function PrescienceCandidates()
	return { [410089] = true }
end

local function ShiftingSandsCandidates()
	return { [413984] = true }
end

--- Sense Power's candidates: the spell, plus every major cooldown still switched on.
---
--- Its own composition rule rather than a pool of its own -- the cooldown pool, seeded with Sense
--- Power. The defensive pool is deliberately not in it.
---@return table<integer, true>
local function SensePowerCandidates()
	return PoolCandidates(POOLS.cooldown, { [361022] = true })
end

---@return table<integer, true>
local function CooldownCandidates()
	return PoolCandidates(POOLS.cooldown)
end

---@return table<integer, true>
local function DefensiveCandidates()
	return PoolCandidates(POOLS.defensive)
end

---@param candidates table<integer, true>
---@return integer[]
local function CandidateIDs(candidates)
	local spellIDs = {}

	for spellID in pairs(candidates) do
		spellIDs[#spellIDs + 1] = spellID
	end

	table.sort(spellIDs)

	return spellIDs
end

--- The tracked auras. `key` indexes the config block and names the slot; the rest is what its
--- slot may show and whose auras count.
---
--- Prescience is one spell from one caster, while Sense Power shares its slot with every major
--- cooldown the spotlighted player might have, cast by them rather than by us -- so they are no
--- longer distinguished by spell ID alone.
---@type SpotlightsAuraFeature[]
local EVOKER_FEATURES = {
	{
		key = "prescience",
		spellID = 410089,
		filter = OWN_FILTER,
		Candidates = PrescienceCandidates,
		multiple = false
	},
	{
		key = "shiftingSands",
		spellID = 413984,
		filter = OWN_FILTER,
		Candidates = ShiftingSandsCandidates,
		multiple = false
	},
	{
		key = "sensePower",
		spellID = 361022,
		filter = ANY_FILTER,
		Candidates = SensePowerCandidates,
		multiple = false
	},
}

local NON_EVOKER_FEATURES = {
	{
		key = "cooldownAuras",
		spellID = 0,
		filter = ANY_FILTER,
		Candidates = CooldownCandidates,
		multiple = true,
	},
	{
		key = "defensiveAuras",
		spellID = 0,
		filter = ANY_FILTER,
		Candidates = DefensiveCandidates,
		multiple = true,
	},
}

local FEATURES = NON_EVOKER_FEATURES
local previewFeatureKey
local MAX_PREVIEW_AURAS = 3

function Private.Auras.SetPreviewFeature(featureKey)
	if previewFeatureKey == featureKey then
		return false
	end

	previewFeatureKey = featureKey

	return true
end

--- One feature's record by key, from whichever specialisation's set holds it.
---
--- Both sets rather than the active `FEATURES`, because the options panel asks about the category its
--- strip has selected and the two can disagree for a moment: a specialisation change swaps the set
--- before the strip has corrected the selection against it.
---@param featureKey SpotlightsAuraFeatureKey
---@return SpotlightsAuraFeature?
local function FeatureByKey(featureKey)
	for i = 1, #EVOKER_FEATURES do
		if EVOKER_FEATURES[i].key == featureKey then
			return EVOKER_FEATURES[i]
		end
	end

	for i = 1, #NON_EVOKER_FEATURES do
		if NON_EVOKER_FEATURES[i].key == featureKey then
			return NON_EVOKER_FEATURES[i]
		end
	end

	return nil
end

local function SetFeatureMode()
	local nextFeatures = Private.Utils.IsAugmentation() and EVOKER_FEATURES or NON_EVOKER_FEATURES

	if FEATURES == nextFeatures then
		return false
	end

	FEATURES = nextFeatures

	Private.SlotHeader.ForEachChild(function(child)
		local built = child.spotlightsAuras

		if not built then
			return
		end

		for _, featureBuilt in pairs(built) do
			for _, record in pairs(featureBuilt) do
				record.anchor:Hide()
				record.container:Hide()
			end
		end

		table.wipe(built)
	end)

	Private.Events.Request(DeferralKey.Auras)

	return true
end

Private.Events.RegisterEvent("PLAYER_LOGIN", SetFeatureMode)

--- How faint a preview bar's unfilled remainder is against its own fill. Enough to read the bar's
--- extent against a spotlight, little enough that the fill still reads as the fill -- and multiplied by
--- the display's own opacity on top, since it sits under the same anchor.
local TRACK_ALPHA = 0.35

--- How long a frozen setting has to stop changing before anything is rebuilt.
---
--- A drag writes the database every frame it moves; a restart-on-change timer turns the gesture into
--- one rebuild when the user's hand stops, instead of sixty leaked containers per spotlight. Long
--- enough to cover a slow drag, short enough that a deliberate click still feels immediate. The
--- aura preview layer fills the gap with live feedback while dragging, at no cost.
local REBUILD_DELAY = 0.4

--- Displays waiting on a rebuild, keyed `feature.display`. A set, so a burst of writes to the same
--- display costs one entry.
---@type table<string, boolean>
local pending = {}

--- Whether a rebuild has actually abandoned something since the user was last asked about it.
---
--- Set where the leak happens rather than where it is requested: a frozen setting changed on a
--- display that is switched *off* queues a rebuild that finds nothing to rebuild — no leak — and
--- offering a reload for it would ask the user to fix a problem they do not have.
local reloadPending = false

---@type FunctionContainer?
local rebuildTimer

--- Whether the debounce has expired, so `pending` is a settled batch rather than a gesture still in
--- progress.
---
--- Separate from "is `pending` non-empty". `DeferralKey.Auras` is requested by the free path too, and
--- without this flag a free setting changed mid-drag would drain the drag's half-finished batch on
--- the next frame — no debounce at all, at one leaked container per spotlight per frame.
local settled = false

--- Queues a display for rebuilding once its settings stop moving.
---
--- Restart-on-change: the timer is cancelled and replaced on every write, so a drag of any length
--- costs one rebuild, at the end. The drain runs through `Apply`, which handles combat.
---@param featureKey SpotlightsAuraFeatureKey
---@param displayKey SpotlightsAuraDisplayKey
local function RequestRebuild(featureKey, displayKey)
	pending[featureKey .. "." .. displayKey] = true

	if rebuildTimer then
		rebuildTimer:Cancel()
	end

	rebuildTimer = C_Timer.NewTimer(REBUILD_DELAY, function()
		rebuildTimer = nil
		settled = true

		Private.Events.Request(DeferralKey.Auras)
	end)
end

--- LibSharedMedia's name for the empty border, and how "no border" is spelled in the settings.
local BORDER_NONE = "None"

--- The formatter for the icon's countdown text, replacing the container's default.
---
--- `SetDurationText` with no options selects `DefaultAuraDurationFormatter`, a `SecondsFormatter`
--- that always renders a unit. None of its abbreviations omit the unit, so it cannot produce the bare
--- number this display wants.
---
--- A `NumericRuleFormatter` can, because each breakpoint carries its own format string. Two
--- breakpoints, keyed on remaining seconds:
---   * below three seconds -- one decimal, truncated so it counts down `2.9, 2.8` rather than
---     rounding up.
---   * three seconds and up -- whole seconds, rounded up so `6` still shows while ~5.5s remain,
---     matching the old `6s` text minus its unit.
--- `%.0f`/`%.1f` rather than `%d`, so the already-rounded value never trips an integer specifier.
---
--- Seconds throughout, no minute promotion: a duration over a minute reads `90` rather than a bare
--- `1` ambiguous against one second. These auras are almost always under a minute.
---
--- Built once and shared: never mutated, and `SetDurationText` copies what it is given. Ours, not
--- Blizzard's -- `AuraContainerInbound.GetDefaultAuraDurationFormatter` hands back the global
--- instance, and mutating that would change every aura display in the game.
local DURATION_FORMATTER = C_StringUtil.CreateNumericRuleFormatter()

DURATION_FORMATTER:SetBreakpoints({
	{ threshold = 0, step = 0.1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%.1f" },
	{ threshold = 3, step = 1,   rounding = Enum.NumericRuleFormatRounding.Up,   format = "%.0f" },
})

--- Creation and styling are separate throughout this section, and the preview is why.
---
--- On a real display the two happen once, back to back: the aura button is access-restricted the
--- moment `initializeFrame` returns. The preview layer is the opposite — nothing restricted, and a
--- settings drag restyles it sixty times a second. Split, the same `Style` runs on both, which makes
--- a preview show *what will ship*.
---
--- The asymmetry that remains is in `Create`: a real display builds only the optional regions its
--- config asks for, because an unwanted `Cooldown` under an aura button can never be reclaimed, while
--- a preview builds all of them and lets `Style` decide what is shown. Hence `everything`.

--- The frame a border is drawn on. Created for both kinds, because a border does not care whether it
--- is around a bar or an icon.
---
--- Lifted clear of its host's own frame level so it draws over the bar fill, the icon art and the
--- cooldown swipe rather than under whichever was created after it.
---@param host Frame|table
---@return SpotlightsAuraBorder
local function CreateBorder(host)
	---@type SpotlightsAuraBorder
	local border = CreateFrame("Frame", nil, host, "BackdropTemplate")

	border:SetAllPoints()
	border:SetFrameLevel(host:GetFrameLevel() + 5)

	return border
end

--- Applies the border settings, including the one that means "no border".
---
--- `SetAllPoints` rather than an outset: a backdrop edge straddles the frame's boundary, so a border
--- on the display's own rect lines up with the rect the user positioned. An outset would make the
--- visible display quietly larger than the size the settings report.
---
--- `None` hides rather than clears, and it is a requirement: `SetBackdrop` errors on a backdrop with
--- neither a background nor an edge, and LSM resolves `None` to an empty path.
---@param regions SpotlightsAuraRegions
---@param config SpotlightsAuraDisplayConfig
local function StyleBorder(regions, config)
	local border = regions.border

	if not border then
		return
	end

	if config.borderTexture == BORDER_NONE then
		border:Hide()

		return
	end

	border:SetBackdrop({
		edgeFile = Private.Media.Border(config.borderTexture),
		edgeSize = config.borderSize,
	})
	border:SetBackdropBorderColor(config.borderR, config.borderG, config.borderB, config.borderA)
	border:Show()
end

--- The swipe and the countdown text, which an icon and a square draw identically: neither is about the
--- thing underneath it, and both are wanted over spell art and over a plain block alike.
---
--- Shared rather than written twice because every line of it is a decision with a reason, and two copies
--- of those reasons is two places for one of them to be corrected.
---
--- Either region is created only when the config wants it, unless `everything` says otherwise -- see the
--- note on `Create` above.
---@param host Frame|table
---@param config SpotlightsAuraIconConfig|SpotlightsAuraSquareConfig
---@param regions SpotlightsAuraRegions
---@param everything boolean
local function CreateDuration(host, config, regions, everything)
	if config.showSwipe or everything then
		-- CooldownFrameTemplate carries `setAllPoints` and starts hidden. Both are wanted: the
		-- container shows it through `SetCooldownFromDurationObject`, and `Shown` is a secret aspect
		-- from the moment `SetDurationCooldown` returns, so it could not be shown from here anyway.
		regions.swipe = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")

		regions.swipe:SetDrawEdge(false)

		-- The swipe is driven by an aura timer, not a spell cooldown, and the two display slightly
		-- differently: this keeps the sweep in sync with the aura's own duration. Blizzard sets the
		-- same flag on every aura-fed Cooldown it owns.
		regions.swipe:SetUseAuraDisplayTime(true)

		-- Ours is the only countdown on this display. The cooldown's own numbers would otherwise sit
		-- under the duration text saying the same thing a pixel out of alignment.
		regions.swipe:SetHideCountdownNumbers(true)
	end

	if config.showText or everything then
		-- On a layer of its own, above the swipe rather than *on* it.
		--
		-- A Cooldown is a frame, so its shading draws above anything on the host whatever draw layer
		-- we ask for. Hanging the text off the swipe made switching the swipe off take the duration
		-- with it, so the two settings could not be set independently. One frame above both fixes it.
		local layer = CreateFrame("Frame", nil, host)

		layer:SetAllPoints()
		layer:SetFrameLevel(host:GetFrameLevel() + 6)

		regions.text = layer:CreateFontString(nil, "OVERLAY")
		regions.text:SetPoint("CENTER")
	end
end

--- Applies both duration settings. The `SetShown` calls are no-ops on a live display, where a region
--- exists only when wanted, and are the point on a preview.
---@param regions SpotlightsAuraRegions
---@param config SpotlightsAuraIconConfig|SpotlightsAuraSquareConfig
local function StyleDuration(regions, config)
	if regions.swipe then
		regions.swipe:SetShown(config.showSwipe)
	end

	if regions.text then
		-- `OUTLINE` unconditionally: a duration sits over spell art, a coloured block and a cooldown
		-- swipe, and unoutlined text on any of those is illegible at every font and size.
		regions.text:SetFont(Private.Media.Font(config.font), config.fontSize, "OUTLINE")
		regions.text:SetShown(config.showText)
	end
end

--- Hands the swipe and the countdown to the aura button, after which neither is ours.
---
--- `SetDurationText` is given a `textFormatter` rather than left to pick
--- `DefaultAuraDurationFormatter` -- see `DURATION_FORMATTER`. The formatter is the only thing we are
--- still allowed to decide: the moment this returns the text gains `Text`, `Alpha` and `VertexColor`
--- as secret aspects. The options table is copied in, so passing the one shared formatter to every
--- display is safe.
---@param button table
---@param regions SpotlightsAuraRegions
local function RegisterDuration(button, regions)
	if regions.swipe then
		button:SetDurationCooldown(regions.swipe)
	end

	if regions.text then
		button:SetDurationText(regions.text, { textFormatter = DURATION_FORMATTER })
	end
end

--- Fills a preview's swipe and countdown with a made-up moment.
---
--- Re-armed on every restyle rather than looped, so a preview is a snapshot: it runs down and stops if
--- left alone, and starts again the moment any control moves.
---
--- **The swipe is guarded on the setting here rather than left to `Style`, because `SetCooldown` shows
--- the frame it arms.** So a swipe the user had just switched off was hidden by the styling pass and
--- un-hidden one line later by this — the setting appeared to do nothing.
---@param regions SpotlightsAuraRegions
---@param config SpotlightsAuraIconConfig|SpotlightsAuraSquareConfig
local function PreviewDuration(regions, config)
	if regions.swipe and config.showSwipe then
		regions.swipe:SetCooldown(GetTime() - 8, 20)
	end

	-- No such guard needed: `SetText` on a hidden font string leaves it hidden. A fractional sample,
	-- because the sub-three-second decimal is the visible part of the format and the preview is the
	-- one place to show it.
	if regions.text then
		regions.text:SetText("2.5")
	end
end

--- The regions a duration bar is made of.
---
--- The inline icon is created only when the config wants one, unless `everything` says otherwise. On
--- a real display a texture under an aura button can never be reclaimed, and the toggle that would
--- show it is frozen; on a preview the toggle is live and a region that does not exist cannot be
--- shown.
---@param host Frame|table
---@param config SpotlightsAuraBarConfig
---@param spellID integer
---@param everything boolean
---@return SpotlightsAuraRegions
local function CreateBar(host, config, spellID, everything)
	---@type SpotlightsAuraRegions
	local regions = { bar = CreateFrame("StatusBar", nil, host) }

	--- The unfilled remainder of the bar, and **preview-only**.
	---
	--- A `StatusBar` draws nothing where it is not filled, and a preview's fill is a fixed two thirds --
	--- so without this the pane reports a bar a third narrower than the one being configured, and a
	--- width dragged to cover a spotlight looks like it does not. A live display needs none: its fill
	--- moves, which is what says where the bar ends.
	---
	--- On `host` rather than on the status bar, so it draws under the fill: a child frame is above every
	--- region of its parent whatever layer they claim.
	if everything then
		regions.barTrack = host:CreateTexture(nil, "BACKGROUND")
		regions.barTrack:SetAllPoints(regions.bar)
	end

	if config.showIcon or everything then
		regions.barIcon = host:CreateTexture(nil, "ARTWORK")

		-- The feature's own spell, which is what a **preview** wants: it has no aura and no button. On
		-- a live display `RegisterBar` hands the texture to the button and the container repaints it
		-- per aura, making this the value shown for the fraction of a frame between the two.
		regions.barIcon:SetTexture(C_Spell.GetSpellTexture(spellID))
		regions.barIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end

	-- Last, so it draws over the fill and the inline icon both.
	regions.border = CreateBorder(host)

	return regions
end

--- Applies every bar setting, and is the whole of what a preview and a live display have in common.
---
--- The bar is anchored rather than sized: it fills its host, which fills the container, which fills
--- the anchor — so the one rect anyone sets is the anchor's, which stays writable. A bar sized here
--- would never change size again.
---
--- `SetStatusBarTexture` resolves the stored LibSharedMedia key at the moment it is called, and on a
--- real display it is never called again. So an addon supplying the user's chosen texture that loads
--- after us needs a rebuild here, where a health bar could just be re-textured -- the same problem
--- `Private.Media`'s registration callback solves. LSM registers `Solid` at load, so the default is
--- never affected.
---@param regions SpotlightsAuraRegions
---@param anchor Frame
---@param config SpotlightsAuraBarConfig
local function StyleBar(regions, anchor, config)
	local bar = regions.bar --[[@as StatusBar]]
	local icon = regions.barIcon
	local path = Private.Media.StatusBar(config.texture)
	local vertical = config.orientation == Private.Enum.Orientation.Vertical

	bar:SetStatusBarTexture(path)
	bar:SetStatusBarColor(config.r, config.g, config.b)

	-- **Before `RegisterBar`**, which is the order `InitializeFrame` runs the two in. From the moment
	-- `SetDurationBar` returns the bar carries `SecretAspect.BarValue` and the container owns its fill;
	-- nothing here is written for a bar already being driven. The direction the fill *drains* is
	-- `Enum.StatusBarTimerDirection.RemainingTime`, which is a property of the timer rather than of the
	-- axis, so it needs nothing said about it here.
	bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")

	bar:ClearAllPoints()

	-- The same material and colour as the fill, faint: the remainder has to read as the rest of *this*
	-- bar rather than as a second one behind it.
	if regions.barTrack then
		regions.barTrack:SetTexture(path)
		regions.barTrack:SetVertexColor(config.r, config.g, config.b, TRACK_ALPHA)
	end

	if icon then
		-- A no-op on a live display, where the region exists only when wanted. The preview is the
		-- caller this is written for.
		icon:SetShown(config.showIcon)
	end

	--- The inline icon takes one end of the bar and spans the other axis, and the bar gets what is left.
	---
	--- **The one measurement here that a resize invalidates.** A square needs one dimension told to it,
	--- and there is no anchor for "as wide as I am tall" — so the icon is square against the axis the
	--- fill does *not* run along, at the size the display has now. On a live display that is frozen until
	--- a rebuild; on a preview it is re-measured on every restyle.
	---
	--- Two branches rather than one with the points computed, because the vertical case is the horizontal
	--- one transposed in three separate ways -- which pair of points each region pins, which way round
	--- `iconSide` reads, and which dimension makes the square.
	if config.showIcon and icon then
		icon:ClearAllPoints()

		if vertical then
			-- `iconSide` keeps its `LEFT`/`RIGHT` storage in both orientations: the pair means one end of
			-- the bar and the other, and a vertical bar's ends are its top and its bottom.
			local side = config.iconSide == "RIGHT" and "BOTTOM" or "TOP"
			local opposite = side == "TOP" and "BOTTOM" or "TOP"

			icon:SetPoint(side .. "LEFT")
			icon:SetPoint(side .. "RIGHT")
			PixelUtil.SetHeight(icon, anchor:GetWidth())

			bar:SetPoint(opposite .. "LEFT")
			bar:SetPoint(opposite .. "RIGHT")
			bar:SetPoint(side, icon, opposite)
		else
			local side = config.iconSide == "RIGHT" and "RIGHT" or "LEFT"
			local opposite = side == "LEFT" and "RIGHT" or "LEFT"

			icon:SetPoint("TOP" .. side)
			icon:SetPoint("BOTTOM" .. side)
			PixelUtil.SetWidth(icon, anchor:GetHeight())

			bar:SetPoint("TOP" .. opposite)
			bar:SetPoint("BOTTOM" .. opposite)
			bar:SetPoint(side, icon, opposite)
		end
	else
		bar:SetAllPoints()
	end

	StyleBorder(regions, config)
end

--- Hands an icon texture to the aura button, so it shows whichever aura the slot is tracking.
---
--- **The only way a display can name what it is showing.** Sense Power's slot pools the whole
--- cooldown list beside its own spell, so a static icon would mean a bar tracking `Recklessness`
--- sitting under the Sense Power icon. Prescience's slot admits one spell, making this the same
--- picture; uniform is worth more than a branch to skip it.
---
--- The cost is that `AuraContainerUtil.SetIconTextureForAura` finishes with
--- `SetTexture(secretwrap(icon))`, so the texture's contents are no longer ours to read or repaint.
--- Neither is something we do: every call that shapes this texture has run by the time `Create` and
--- `Style` hand over.
---
--- No empty state to handle. `SetIconTextureForAura` falls back to `QUESTION_MARK_ICON` when there is
--- no aura, but `ApplyAuraInstance` runs `ApplyIcon` immediately before `ApplyVisibility`, which
--- hides the button -- so the placeholder is set and concealed in the same pass.
---@param button table
---@param icon Texture
local function SetAuraIcon(button, icon)
	button:SetIcon(icon)
end

--- Hands the bar and the inline icon to the aura button, the last thing that happens to either.
---
--- No `SetMinMaxValues` and no `SetValue`, here or ever. `SetDurationBar` adds
--- `SecretAspect.BarValue`, and from this point the container drives the fill through
--- `SetTimerDuration` with a duration object we never see the contents of.
---@param button table
---@param regions SpotlightsAuraRegions
local function RegisterBar(button, regions)
	button:SetDurationBar(regions.bar, {
		interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut,
		direction = Enum.StatusBarTimerDirection.RemainingTime,
	})

	if regions.barIcon then
		SetAuraIcon(button, regions.barIcon)
	end
end

--- Fills a preview bar with a made-up remaining fraction.
---
--- Plain numbers, because nothing about a preview is secret. Two thirds rather than full, so the bar
--- reads as a countdown in progress and its direction is visible.
---@param regions SpotlightsAuraRegions
---@param _ SpotlightsAuraBarConfig the settings, which a bar's fake fill has no reason to consult
local function PreviewBar(regions, _)
	regions.bar:SetMinMaxValues(0, 1)
	regions.bar:SetValue(0.65)
end

--- Repaints a preview's inline icon for a different spell.
---
--- **Not `SetAuraIcon`.** That hands the texture to a live aura button, which makes its contents secret
--- and its identity the container's to decide. A preview has no button, so the art is the only thing
--- saying which spell it is about -- and it has to follow a pooled feature's candidate set, which the
--- user edits while looking at it.
---@param regions SpotlightsAuraRegions
---@param spellID integer
local function PreviewBarArt(regions, spellID)
	if regions.barIcon then
		regions.barIcon:SetTexture(C_Spell.GetSpellTexture(spellID))
	end
end

--- The regions a spell icon is made of: the art, an optional swipe, an optional countdown.
---
--- Everything here fills its host, so the display's size is the anchor's size and stays live.
---
--- The texture set here is the *preview's* icon and only incidentally the live display's first frame:
--- `RegisterIcon` hands it to the button, which repaints it per aura. A preview never reaches
--- `Register`, so this is the whole of what it will ever show.
---@param host Frame|table
---@param config SpotlightsAuraIconConfig
---@param spellID integer
---@param everything boolean
---@return SpotlightsAuraRegions
local function CreateIcon(host, config, spellID, everything)
	---@type SpotlightsAuraRegions
	local regions = { icon = host:CreateTexture(nil, "ARTWORK") }

	regions.icon:SetAllPoints()
	regions.icon:SetTexture(C_Spell.GetSpellTexture(spellID))

	-- The border every icon file ships with, cropped off. Every icon display in the game does this,
	-- which is why an uncropped one reads as subtly wrong beside them.
	regions.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	CreateDuration(host, config, regions, everything)

	-- Last, so it draws over the icon art and the swipe both.
	regions.border = CreateBorder(host)

	return regions
end

--- Repaints a preview's art for a different spell, for `PreviewBarArt`'s reason.
---@param regions SpotlightsAuraRegions
---@param spellID integer
local function PreviewIconArt(regions, spellID)
	local icon = regions.icon --[[@as Texture]]

	icon:SetTexture(C_Spell.GetSpellTexture(spellID))
end

--- Applies every icon setting.
---
--- Shorter than its bar counterpart because an icon has less to decide, and both halves of what it does
--- decide are shared with the square.
---@param regions SpotlightsAuraRegions
---@param _ Frame the anchor, which an icon has no use for because it is sized directly by config
---@param config SpotlightsAuraIconConfig
local function StyleIcon(regions, _, config)
	StyleDuration(regions, config)
	StyleBorder(regions, config)
end

--- Hands the art, the swipe and the countdown to the aura button, after which none is ours.
---@param button table
---@param regions SpotlightsAuraRegions
local function RegisterIcon(button, regions)
	SetAuraIcon(button, regions.icon --[[@as Texture]])
	RegisterDuration(button, regions)
end

--- The regions a coloured square is made of: the block, an optional swipe, an optional countdown.
---
--- No spell art and therefore **no `SetIcon`**, which is the whole difference between this and an icon:
--- the display says an aura is up and how long is left, and nothing about which aura it is. That is what
--- makes it readable at a size where an icon is not.
---
--- The block is a plain colour texture rather than a LibSharedMedia one. A material would be a second
--- way to say what the border already says, and it would put this display on the media-registration
--- rebuild path for no visible gain -- see `UnresolvedMedia`, which finds nothing here but the border.
---@param host Frame|table
---@param config SpotlightsAuraSquareConfig
---@param _ integer the spell, which a display drawing no art has nothing to do with
---@param everything boolean
---@return SpotlightsAuraRegions
local function CreateSquare(host, config, _, everything)
	---@type SpotlightsAuraRegions
	local regions = { block = host:CreateTexture(nil, "ARTWORK") }

	regions.block:SetAllPoints()

	CreateDuration(host, config, regions, everything)

	-- Last, so it draws over the block and the swipe both.
	regions.border = CreateBorder(host)

	return regions
end

--- Applies every square setting.
---
--- `SetColorTexture` rather than a white texture tinted by `SetVertexColor`: the two look the same, and
--- one call that means "be this colour" is the honest spelling of a display whose colour is all it has.
--- Three channels, not four -- opacity is the anchor's, which is what keeps it live.
---@param regions SpotlightsAuraRegions
---@param _ Frame the anchor, which a square has no use for because it is sized directly by config
---@param config SpotlightsAuraSquareConfig
local function StyleSquare(regions, _, config)
	local block = regions.block --[[@as Texture]]

	block:SetColorTexture(config.r, config.g, config.b)

	StyleDuration(regions, config)
	StyleBorder(regions, config)
end

--- The one region a bare countdown is made of, plus the border every kind may draw.
---
--- **Not `CreateDuration`.** That builds a swipe and a font string from `showSwipe`/`showText`, and this
--- display has neither field: the text is not an option on it, it *is* it. A preview would also come back
--- with a swipe it can never be told to hide.
---
--- The font string sits on a layer of its own above the border for the reason the icon's does above the
--- swipe -- a border is a child frame, so it draws over any region of the host whatever layer that region
--- claims, and a thick edge would otherwise cut into the number it surrounds.
---
--- Takes the host alone where every other kind takes four: the settings shape nothing built here, there
--- is no spell art to be about, and `everything` has no optional region to decide.
---@param host Frame|table
---@return SpotlightsAuraRegions
local function CreateText(host)
	local layer = CreateFrame("Frame", nil, host)

	layer:SetAllPoints()
	layer:SetFrameLevel(host:GetFrameLevel() + 6)

	---@type SpotlightsAuraRegions
	local regions = { text = layer:CreateFontString(nil, "OVERLAY") }

	-- Centred in the rect `Size` derives from the font size, which is the whole of what that rect is for.
	regions.text:SetPoint("CENTER")

	regions.border = CreateBorder(host)

	return regions
end

--- Applies every setting of a bare countdown.
---
--- **`SetTextColor` has to happen here and can never happen again.** `SetDurationText` adds `Text`, `Alpha`
--- and `VertexColor` to the font string's secret aspects the moment it returns, and `InitializeFrame` runs
--- this immediately before it -- so the colour picker on this display is a rebuild, like the bar's fill
--- colour and the square's block.
---
--- `OUTLINE` unconditionally for `StyleDuration`'s reason: this text sits over a health bar and nothing
--- else, and unoutlined it is illegible at every font and size.
---
--- No `SetShown`. On the other two kinds the countdown is an option; here it is the display, and being
--- switched off is the anchor's answer.
---@param regions SpotlightsAuraRegions
---@param _ Frame the anchor, whose rect this display is centred in rather than measured against
---@param config SpotlightsAuraTextConfig
local function StyleText(regions, _, config)
	local text = regions.text --[[@as FontString]]

	text:SetFont(Private.Media.Font(config.font), config.fontSize, "OUTLINE")
	text:SetTextColor(config.r, config.g, config.b)

	StyleBorder(regions, config)
end

--- What every kind's anchor carries, and therefore what stays live on all four.
---
--- The anchor is a plain frame of ours above the aura button's access restriction, so everything
--- `ApplyAnchor` writes reaches a built display for free. `enabled` looks the most drastic of the five
--- and is the cheapest: one `SetShown` on that frame, or a first build `EnsureDisplays` was going to do
--- anyway.
---@type table<string, SpotlightsAuraInvalidation>
local ANCHOR_INVALIDATION = {
	enabled = "live",
	alpha = "live",
	point = "live",
	x = "live",
	y = "live",
}

--- The border, which all four kinds draw the same way and none can change after the fact: a backdrop
--- belongs to a frame under the aura button.
---
--- `borderA` is classified with the other three channels because all four reach that backdrop through
--- one `SetBackdropBorderColor`. Left out, an alpha write took the live path, which re-anchors a display
--- without restyling it -- so it changed nothing anywhere but the preview.
---@type table<string, SpotlightsAuraInvalidation>
local BORDER_INVALIDATION = {
	borderTexture = "rebuild",
	borderSize = "rebuild",
	borderR = "rebuild",
	borderG = "rebuild",
	borderB = "rebuild",
	borderA = "rebuild",
}

--- The swipe and the countdown, shared by the icon and the square because their duration halves are
--- the same code. All four decide which regions exist under the button, or what the font string sitting
--- there is made of.
---@type table<string, SpotlightsAuraInvalidation>
local DURATION_INVALIDATION = {
	showSwipe = "rebuild",
	showText = "rebuild",
	font = "rebuild",
	fontSize = "rebuild",
}

--- One kind's classification, merged from the groups it shares with the others and the fields that are
--- its own.
---
--- Every field of that kind's config block has to appear in exactly one of the tables handed in.
--- `Invalidation` answers `rebuild` for a field it does not find, which is the safe direction -- a
--- setting wrongly rebuilt still lands, where one wrongly called live is silently dropped below the
--- access restriction -- but it costs a container per assigned spotlight, so an omission is a bug
--- rather than a default worth relying on.
---@param ... table<string, SpotlightsAuraInvalidation>
---@return table<string, SpotlightsAuraInvalidation>
local function Classification(...)
	local merged = {}

	for i = 1, select("#", ...) do
		for field, invalidation in pairs((select(i, ...))) do
			merged[field] = invalidation
		end
	end

	return merged
end

--- A bar's own half: the fill, its colour, and the inline icon. All of it is built into regions under
--- the button. Width and height are the anchor's, so a bar is resized live.
local BAR_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, {
	width = "live",
	height = "live",
	texture = "rebuild",
	r = "rebuild",
	g = "rebuild",
	b = "rebuild",
	orientation = "rebuild",
	showIcon = "rebuild",
	iconSide = "rebuild",
})

--- An icon's own half is nothing but its dimensions and the spacing between pooled copies of it: the
--- art is the button's, and everything else it draws is shared. `gap` is the group's flow-layout
--- spacing rather than a property of the button, which `ApplyGroupLayout` writes to a live container.
local ICON_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, DURATION_INVALIDATION, {
	width = "live",
	height = "live",
	gap = "live",
})

--- A square's own half is the block's colour, which is a texture under the button. `size` is the
--- anchor's, both ways.
local SQUARE_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, DURATION_INVALIDATION, {
	size = "live",
	r = "rebuild",
	g = "rebuild",
	b = "rebuild",
})

--- A bare countdown's own half, and **all of it is frozen**. The colour looks like it belongs beside the
--- anchor's alpha, and does not: `SetDurationText` adds `VertexColor` to the font string's secret aspects,
--- so a colour written after the display was built would be dropped below the access restriction rather
--- than applied.
---
--- `fontSize` owes the rebuild the font string needs *and* a re-anchor, since `Size` derives the rect from
--- it -- but the re-anchor comes for free: draining the rebuild runs `ApplyChild` over every spotlight
--- first, which is where `ApplyAnchor` reads the new size.
local TEXT_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, {
	font = "rebuild",
	fontSize = "rebuild",
	r = "rebuild",
	g = "rebuild",
	b = "rebuild",
})

--- How wide and how tall a bare countdown's anchor is, per point of font size.
---
--- A rect derived from a number we already have, because the alternative is measuring the font string --
--- and its `Text` is secret from the moment the display is registered, so its width is not ours to read.
--- Four ems across fits the widest thing the formatter produces (`2.9`, or a three-digit `120`) with room
--- to spare; the height is a line plus its outline.
---
--- Nothing is clipped to this rect: the string is centred in it and draws past it if it has to. It is a
--- rectangle to hang the number in the middle of, which keeps the anchor's nine points meaning what they
--- mean on every other display.
local TEXT_WIDTH_PER_POINT, TEXT_HEIGHT_PER_POINT = 4, 1.4

--- The four displays a feature can draw.
---
--- `Size` is a function rather than a flag because the display kinds have different config shapes.
---@type SpotlightsAuraKind[]
local DISPLAYS = {
	{
		key = "bar",
		Create = CreateBar,
		Style = StyleBar,
		Register = RegisterBar,
		Preview = PreviewBar,
		PreviewArt = PreviewBarArt,
		Size = function(config, size)
			return config.width, config.height
		end,

		Invalidation = function(_, field)
			return BAR_INVALIDATION[field] or "rebuild"
		end,

		-- The inline icon and nothing else. It was made square against one axis measured at build time,
		-- and it sits below the access restriction, so a spotlight resize leaves it a rectangle that only
		-- a new button can fix. Which axis is the orientation's answer: a vertical bar's icon spans the
		-- width, so a height change leaves it square and a width change does not. A bar without an icon
		-- survives any resize.
		Invalidated = function(config, record)
			if not config.showIcon then
				return false
			end

			if config.orientation == Private.Enum.Orientation.Vertical then
				return record.builtWidth ~= record.anchor:GetWidth()
			end

			return record.builtHeight ~= record.anchor:GetHeight()
		end,
	},
	{
		key = "icon",
		Create = CreateIcon,
		Style = StyleIcon,
		Register = RegisterIcon,
		Preview = PreviewDuration,
		PreviewArt = PreviewIconArt,
		Size = function(config)
			return config.width, config.height
		end,

		-- The one classification a kind cannot state as a table: a pooled feature sizes each button
		-- inside `initializeFrame`, below the access restriction, so there the dimensions are build-time
		-- like everything else down there. A single-aura icon's button fills the anchor instead, which
		-- `ApplyAnchor` resizes live.
		Invalidation = function(feature, field)
			if feature.multiple and (field == "width" or field == "height") then
				return "rebuild"
			end

			return ICON_INVALIDATION[field] or "rebuild"
		end,

		-- No `Invalidated`. Everything under an icon's button fills it, so the anchor's rect is the
		-- display's rect at every size, forever.
	},
	{
		key = "square",
		Create = CreateSquare,
		Style = StyleSquare,
		Register = RegisterDuration,
		Preview = PreviewDuration,

		-- No `PreviewArt`. A block draws no spell art, so there is nothing for a candidate set to repaint.

		-- One field for both axes: a square that could be told to be a rectangle would be an icon
		-- without the art.
		Size = function(config)
			return config.size, config.size
		end,

		Invalidation = function(_, field)
			return SQUARE_INVALIDATION[field] or "rebuild"
		end,

		-- No `Invalidated`, for the icon's reason: block, swipe and text all fill the button.
	},
	{
		key = "text",
		Create = CreateText,
		Style = StyleText,

		-- `RegisterDuration` unchanged, as the square does: it hands over whichever of the swipe and the
		-- countdown exist, and this display has only the second. A `RegisterText` would be that function
		-- with one branch it never takes.
		Register = RegisterDuration,

		-- Likewise `PreviewDuration`: it fills the swipe only when `showSwipe` says so, and there is no
		-- such field here, so what is left is the sample number this display is entirely made of.
		Preview = PreviewDuration,

		-- No `PreviewArt`. A number draws no spell art, so there is nothing for a candidate set to repaint.

		Size = function(config)
			return config.fontSize * TEXT_WIDTH_PER_POINT, config.fontSize * TEXT_HEIGHT_PER_POINT
		end,

		Invalidation = function(_, field)
			return TEXT_INVALIDATION[field] or "rebuild"
		end,

		-- No `Invalidated`. The rect is the font size's answer rather than the spotlight's, so a resize
		-- cannot break anything the button was built against.
	},
}

--- Whether a feature draws a given kind of display at all.
---
--- A pooled feature shows several of the spotlighted player's auras at once, and a column of duration
--- bars over one spotlight is unreadable -- so it draws icons only. The square and the bare countdown are
--- left out of a pooled feature for the opposite reason to the bar's: they fit, but neither carries spell
--- art, so several of them side by side say only that *some* number of things are up. A pooled feature is
--- about which cooldown landed, which is the one thing those two do not say.
---
--- The build path, the preview layer and the options panel all ask here rather than each restating the
--- rule.
---@param feature SpotlightsAuraFeature
---@param display SpotlightsAuraKind
---@return boolean
local function DrawsDisplay(feature, display)
	return not feature.multiple or display.key == "icon"
end

--- One display kind by key, the counterpart to `FeatureByKey`.
---
--- Answers for a kind a feature does not draw: this is the lookup, not the rule. `DrawsDisplay` is the
--- rule, and a settings write to a display nothing renders is still a write.
---@param displayKey SpotlightsAuraDisplayKey
---@return SpotlightsAuraKind?
local function DisplayByKey(displayKey)
	for i = 1, #DISPLAYS do
		if DISPLAYS[i].key == displayKey then
			return DISPLAYS[i]
		end
	end

	return nil
end

--- Everything a settings change gets for free, in one call.
---
--- Position, size, fade and on/off, all written to the **anchor** — a plain frame of ours above the
--- aura button's access restriction, and therefore the only part of a display that can still be told
--- anything after it is built. Runs on a live spotlight, in or out of combat.
---
--- `point` is validated like a saved grid position: `SetPoint` errors on a point it does not
--- recognise, and this runs inside a roster pass where that would take every later spotlight with it.
---
--- The size floor guards against a damaged database, not user input. `SetSize(0, 0)` means "take your
--- size from your anchors", which with a single anchor point is undefined rather than empty.
---
--- `featureEnabled` is the feature's own switch, which the display's cannot override: the anchor is
--- what carries "off" to a built display, so both answers have to meet here rather than at either
--- caller. Hiding it takes the container under it down with it, and a hidden container drops its
--- `UNIT_AURA` registration in `OnHide` -- so a switched-off feature stops being told about auras
--- rather than merely stopping drawing them.
---@param anchor Frame
---@param parent Frame
---@param display SpotlightsAuraKind
---@param config SpotlightsAuraDisplayConfig
---@param size SpotlightsChildSize
---@param featureEnabled boolean
local function ApplyAnchor(anchor, parent, display, config, size, featureEnabled)
	local point = Private.Enum.AnchorPoints[config.point] and config.point or "CENTER"
	local width, height = display.Size(config, size)

	anchor:ClearAllPoints()
	PixelUtil.SetPoint(anchor, point, parent, point, config.x, config.y)
	PixelUtil.SetSize(anchor, math.max(width, 1), math.max(height, 1))
	anchor:SetAlpha(config.alpha)
	anchor:SetShown(featureEnabled and config.enabled)
end

--- Builds one display on one spotlight: an anchor of ours, a container inside it, and the slot.
---
--- **Every irreversible decision in this addon is made in this function.** The button the container
--- hands back is access-restricted the instant `initializeFrame` returns, and that restriction
--- reaches every descendant — so texture, colour, the inline icon and the swipe are settled here for
--- the lifetime of the frame. A slot cannot be removed and its key cannot be reused, so a changed
--- setting means another container beside this one.
---
--- The container is pinned by **opposing corners**, which is load-bearing. A container holding only
--- slots contributes nothing to its own flow layout, whose pass ends in
--- `CustomAuraContainerFlowLayoutMixin` calling `container:SetSize(1, 1)`. Two opposed anchors leave
--- neither axis for `SetSize` to decide, which makes the anchor's rect the display's.
---
--- Called with an anchor already at its final size, so `initializeFrame` can read a height that means
--- something — the bar's inline icon needs one to be square.
---@param child SpotlightsUnitFrame
---@param feature SpotlightsAuraFeature
---@param display SpotlightsAuraKind
---@param config SpotlightsAuraDisplayConfig
---@param anchor Frame
---@return SpotlightsAuraContainer container
local function AttachContainer(child, feature, display, config, anchor)
	---@type SpotlightsAuraContainer
	local container = CreateFrame("AuraContainer", nil, anchor, "CustomAuraContainerTemplate")

	container:SetPoint("TOPLEFT")
	container:SetPoint("BOTTOMRIGHT")

	-- `SetUnit` asserts on a non-string, and a rebuild has no guarantee of a unit the way a first
	-- build does: a spotlight keeps its displays after the header releases it, so a container can be
	-- built for a frame that currently holds nobody. `OnUnitChanged` points it at the next one.
	if child.unit then
		container:SetUnit(child.unit)
	end

	local candidateIDs = feature.multiple and CandidateIDs(feature.Candidates()) or nil

	local function InitializeFrame(button, spellID)
		if feature.multiple then
			local width, height = display.Size(config, Private.FrameConfig.Get())
			PixelUtil.SetSize(button, math.max(width, 1), math.max(height, 1))
		else
			button:SetPoint("TOPLEFT", container, "TOPLEFT")
			button:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT")
		end

		-- Clicks already pass through: the AuraButton intrinsic carries
		-- `ForbiddenAspect.AlwaysPropagateInput`. Motion is ours to turn off, and must be --
		-- otherwise the aura tooltip replaces the unit tooltip on every hover.
		button:SetMouseMotionEnabled(false)

		-- Create, style, register, in that order and once. Styling has to precede registration: it
		-- sets `Shown` on the optional regions, and `SetDurationCooldown` makes that aspect secret
		-- the moment it returns.
		--
		-- `everything` is false, so only the regions this config asks for exist -- anything the
		-- settings can no longer reach could never be reclaimed.
		local regions = display.Create(button, config, spellID or feature.spellID, false)

		display.Style(regions, anchor, config)
		display.Register(button, regions)
	end

	if feature.multiple then
		container:AddAuraGroup(feature.key, feature.filter, {
			candidateFilters = { includeSpellIDs = feature.Candidates() },
			maxFrameCount = #candidateIDs,
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Reverse,
			layout = { elementSpacing = config.gap or 0 },
			initializeFrame = function(button)
				InitializeFrame(button)
			end,
		})
	else
		container:AddAuraSlot(feature.key, feature.filter, {
			candidateFilters = { includeSpellIDs = feature.Candidates() },
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Reverse,
			initializeFrame = function(button)
				InitializeFrame(button, feature.spellID)
			end,
		})
	end

	return container
end

--- Namespaces a media key by its type, because the two together are the identity: LibSharedMedia
--- scopes names per type, so a border and a statusbar may both be called `Steel`.
---@param mediatype string
---@param key string
---@return string
local function MediaKey(mediatype, key)
	return mediatype .. "|" .. key
end

--- Which of a display's media keys LibSharedMedia could not resolve at the moment it was built.
---
--- Recorded because it is a fact about a moment that cannot be recovered afterwards. `Fetch` falls
--- back to a default for an unregistered key and to the user's real choice for a registered one, and
--- once the button exists the texture reads back secret -- there is no way to ask which happened.
---
--- This makes a late registration cheap: only the displays that actually fell back on the key being
--- registered need a new button. Matching the *stored* key instead would rebuild displays that
--- already had it right.
--- `config` is loose for the same reason `SpotlightsAuraKind.config` is: `texture` belongs to a bar,
--- `font` to an icon, only `borderTexture` is shared. The nil checks below are the honest test, since
--- "this display has no font" and "this display's font is unregistered" are the same answer here.
---@param config table
---@return table<string, true>
local function UnresolvedMedia(config)
	local media = Private.Media
	local unresolved = {}

	if config.texture and not media.IsRegistered(config.texture) then
		unresolved[MediaKey(media.StatusBarType, config.texture)] = true
	end

	if config.font and not media.IsFontRegistered(config.font) then
		unresolved[MediaKey(media.FontType, config.font)] = true
	end

	if config.borderTexture and not media.IsBorderRegistered(config.borderTexture) then
		unresolved[MediaKey(media.BorderType, config.borderTexture)] = true
	end

	return unresolved
end

--- Builds one display on one spotlight from nothing: an anchor of ours, a container inside it, the
--- slot, and the record that remembers all three.
---@param child SpotlightsUnitFrame
---@param feature SpotlightsAuraFeature
---@param display SpotlightsAuraKind
---@param config SpotlightsAuraDisplayConfig
---@return SpotlightsAuraDisplay
local function CreateDisplay(child, feature, display, config)
	local anchor = CreateFrame("Frame", nil, child)

	-- Enabled unconditionally, because nothing builds a display for a feature that is switched off:
	-- `EnsureDisplays` is the only caller and gates on it before it gets here.
	ApplyAnchor(anchor, child, display, config, Private.FrameConfig.Get(), true)

	local container = AttachContainer(child, feature, display, config, anchor)

	return {
		anchor = anchor,
		container = container,
		builtWidth = anchor:GetWidth(),
		builtHeight = anchor:GetHeight(),
		unresolved = UnresolvedMedia(config),
	}
end

--- Shows one live aura container only while its unit is assistable by the player.
---
--- Blizzard deliberately skips identity candidate filters for non-assistable units, so a container
--- left visible on one would parse and display helpful auras these displays exist to hide. That makes
--- this a privacy gate rather than a cosmetic one, and the reason it is a function of its own: every
--- path that puts a container on screen has to pass through it, the relationship sweep and the
--- replacement a frozen setting forces alike.
---
--- Deliberately not folded into `ApplyAnchor`. User enablement belongs to the anchor; assistability
--- belongs to the container's lifetime, and a rebuild replaces the container while keeping the anchor.
---@param container SpotlightsAuraContainer
---@param child SpotlightsUnitFrame
local function ApplyAssistability(container, child)
	local unit = child.unit

	container:SetShown(unit ~= nil and UnitCanAssist("player", unit))
end

--- Replaces a display's container and button with a fresh pair styled from the current settings.
---
--- **The only way a frozen setting reaches a live spotlight.** A slot key is scoped to its container,
--- so a second container inside the same anchor may register the same key again with different
--- styling; `CustomAuraContainerTemplate` is declared `allowUntaintedCreation="true"`, so building
--- one from our code is sanctioned. The old container is hidden, which drops its `UNIT_AURA`
--- registration through its own `OnHide`.
---
--- Inside the existing **anchor**, not beside it. The anchor is the display's identity as far as
--- every other part of this file is concerned. Only the two frozen frames underneath are swapped.
---
--- It leaks by construction: WoW cannot destroy a frame, so the old container and its button stay for
--- the session. That is the debt the reload prompt exists to reclaim.
---@param child SpotlightsUnitFrame
---@param feature SpotlightsAuraFeature
---@param display SpotlightsAuraKind
---@param config SpotlightsAuraDisplayConfig
---@param record SpotlightsAuraDisplay
local function RebuildDisplay(child, feature, display, config, record)
	local container = AttachContainer(child, feature, display, config, record.anchor)

	record.container:Hide()

	record.container = container
	record.builtWidth = record.anchor:GetWidth()
	record.builtHeight = record.anchor:GetHeight()

	-- A fresh container is shown. `Apply` settles assistability before this loop runs, so it settled it
	-- on the container being replaced -- without this the replacement stays visible on a non-assistable
	-- unit until some later faction, flag or roster event happens to sweep again.
	ApplyAssistability(container, child)

	-- Recomputed, not carried over. The usual reason to be here is that the key this display fell back
	-- on has just been registered, so the new button resolved it properly. Keeping the stale set would
	-- make the next registration of the same key rebuild again.
	record.unresolved = UnresolvedMedia(config)

	reloadPending = true
end

--- Runs `callback` over the displays a spotlight has actually built.
---
--- Built, not configured: a display that is switched off has no frames, and half this file's callers
--- want the frames rather than the settings. Both keys are handed back because a caller with only the
--- record cannot say which display it is looking at.
---@param child SpotlightsUnitFrame
---@param callback fun(record: SpotlightsAuraDisplay, feature: SpotlightsAuraFeature, display: SpotlightsAuraKind)
local function ForEachDisplay(child, callback)
	local built = child.spotlightsAuras

	if not built then
		return
	end

	for i = 1, #FEATURES do
		local feature = FEATURES[i]
		local featureBuilt = built[feature.key]

		if featureBuilt then
			for j = 1, #DISPLAYS do
				local display = DISPLAYS[j]
				local record = featureBuilt[display.key]

				if record then
					callback(record, feature, display)
				end
			end
		end
	end
end

--- Applies the spacing of a live multi-aura group without rebuilding its frames.
---
--- `gap` is the group's flow-layout spacing, not a property of the protected aura button. The
--- container setter marks layout dirty and the next aura pass applies the new spacing.
---@param featureKey SpotlightsAuraFeatureKey
---@param displayKey SpotlightsAuraDisplayKey
---@param gap number
local function ApplyGroupLayout(featureKey, displayKey, gap)
	Private.SlotHeader.ForEachChild(function(child)
		ForEachDisplay(child, function(record, feature, display)
			if feature.key == featureKey and display.key == displayKey and feature.multiple then
				record.container:SetAuraGroupLayout(featureKey, { elementSpacing = gap })
			end
		end)
	end)
end

--- Brings every one of a spotlight's built containers in line with the current relationship.
---
--- The iterator only. What "in line" means lives in `ApplyAssistability`, which a rebuild calls for a
--- single replacement container without a record to iterate over yet.
---@param child SpotlightsUnitFrame
function Private.Auras.UpdateAssistability(child)
	ForEachDisplay(child, function(record)
		ApplyAssistability(record.container, child)
	end)
end

--- Revalidates every built spotlight after a global relationship or unit assignment change.
function Private.Auras.RefreshAssistability()
	Private.SlotHeader.ForEachChild(function(child)
		Private.Auras.UpdateAssistability(child)
	end)
end

--- Builds whatever a spotlight does not yet have. Out of combat only, idempotent.
---
--- **Called on first unit assignment, never at build time, and never for a display that is off.**
--- That is the whole of "as cheaply as possible": a forty-slot grid with five players carries five
--- spotlights' worth of aura frames rather than forty, each carrying one container per display the
--- user turned on rather than four. A spotlight with no unit builds nothing.
---
--- A feature switched off is skipped whole, so it costs nothing until it is switched back on -- at
--- which point this runs again and builds what it skipped. That is why the switch is cheap in both
--- directions: off hides what exists, on builds what does not.
---
--- Deferred rather than guarded, because `initializeFrame` anchors and sizes frames descended from a
--- protected unit button -- protected calls that combat-block. The sweep registered below picks the
--- work up when combat ends.
---@param child SpotlightsUnitFrame
local function EnsureDisplays(child)
	local auras = Config()

	if not auras or not child.unit then
		return
	end

	if Private.Events.DeferIfInCombat(DeferralKey.Auras) then
		return
	end

	local built = child.spotlightsAuras

	if not built then
		built = {}
		child.spotlightsAuras = built
	end

	for i = 1, #FEATURES do
		local feature = FEATURES[i]
		local featureConfig = auras[feature.key]
		local featureBuilt = built[feature.key]

		if not featureBuilt then
			featureBuilt = {}
			built[feature.key] = featureBuilt
		end

		for j = 1, #DISPLAYS do
			local display = DISPLAYS[j]
			local config = featureConfig[display.key]

			if featureConfig.enabled and DrawsDisplay(feature, display)
				and config.enabled and not featureBuilt[display.key] then
				-- Assigned after the call returns, so a display that failed to build leaves the
				-- spotlight retryable rather than marked done with nothing in it.
				featureBuilt[display.key] = CreateDisplay(child, feature, display, config)
			end
		end
	end
end

--- Re-applies the free half of every setting to one spotlight's existing displays.
---
--- Called from `SlotHeader.ApplyChildConfig` on a resize as well as from the sweep below, because a
--- bar is stored as a fraction of a spotlight it does not otherwise hear about.
---
--- Not combat-guarded, and that is the point of the anchor arrangement: every write here lands on a
--- frame of ours rather than on the protected unit button it hangs from. `UpdateTempMaxHealthLoss`
--- has been calling `SetPoint` and `SetShown` on regions of that same protected button since the
--- rewrite, on an event that fires throughout a fight. A display can therefore be moved, resized,
--- faded or hidden mid-combat. Building a *new* one still cannot be, which is what `EnsureDisplays`
--- defers and this does not.
---@param child SpotlightsUnitFrame
function Private.Auras.ApplyChild(child)
	local auras = Config()

	if not auras then
		return
	end

	local size = Private.FrameConfig.Get()

	ForEachDisplay(child, function(record, feature, display)
		local config = auras[feature.key][display.key]

		ApplyAnchor(record.anchor, child, display, config, size, auras[feature.key].enabled)

		-- After the anchor has moved, because the question is whether the *new* rect has broken
		-- something the button was built against. Queued rather than done here: this runs per
		-- spotlight inside a geometry pass, and a resize drag would otherwise rebuild every assigned
		-- display on every frame.
		if display.Invalidated and display.Invalidated(config, record) then
			RequestRebuild(feature.key, display.key)
		end
	end)
end

--- Builds one fake display of every kind, for one preview cell.
---
--- **The two things the preview layer is not allowed to reinvent**: the same `Create` the live path
--- uses, and an anchor that `StylePreviews` positions with the same `ApplyAnchor` -- so there is one
--- answer rather than two that can drift.
---
--- Every kind is built for every feature regardless of `enabled`, and `everything` is true, so a
--- toggle is a `SetShown` on something that already exists. Live displays cannot afford that, but a
--- preview is bounded by the visible grid and thrown away by a reload.
---
--- Both filters exist for the options panel's per-section preview, which shows one display of one
--- category beside the controls that edit it. The grid cells pass neither and get what the panel last
--- pointed the preview layer at.
---
--- A pooled feature gets `MAX_PREVIEW_AURAS` items **whatever its pool currently holds**, and none of
--- them is about a particular spell yet: which spell each shows is `StylePreviews`' answer, re-asked on
--- every restyle. Sizing the set to the pool instead is what made a preview go stale -- a spell
--- switched on afterwards had no item to appear in, and frames cannot be created here to give it one
--- without stranding the old set.
---@param parent Frame
---@param featureKey SpotlightsAuraFeatureKey? defaults to the previewed category
---@param displayKey SpotlightsAuraDisplayKey? every kind the category draws, when omitted
---@return SpotlightsAuraPreview[]
function Private.Auras.CreatePreviews(parent, featureKey, displayKey)
	local auras = Config()

	if not auras then
		return {}
	end

	featureKey = featureKey or previewFeatureKey

	---@type SpotlightsAuraPreview[]
	local previews = {}

	for i = 1, #FEATURES do
		local feature = FEATURES[i]

		if not featureKey or feature.key == featureKey then
			local slots = feature.multiple and MAX_PREVIEW_AURAS or 1

			for slotIndex = 1, slots do
				for j = 1, #DISPLAYS do
					local display = DISPLAYS[j]

					if DrawsDisplay(feature, display) and (not displayKey or display.key == displayKey) then
						local anchor = CreateFrame("Frame", nil, parent)

						previews[#previews + 1] = {
							anchor = anchor,
							regions = display.Create(anchor, auras[feature.key][display.key], feature.spellID, true),
							feature = feature,
							display = display,
							slotIndex = slotIndex,
						}
					end
				end
			end
		end
	end

	return previews
end

--- Re-applies every setting to a cell's previews, including the ones a live display cannot hear.
---
--- `ApplyAnchor` and `Style` are the live path's own functions, so what appears here is what will
--- ship — but nothing is registered or access-restricted, so the *frozen* half applies as freely as
--- the free half. A colour picker drags smoothly here while the real displays wait out their
--- debounce.
---
--- **A pooled feature's spell identities are decided here rather than at creation**, from the candidate
--- set as it stands at this call: item `n` is about the `n`th enabled spell, and an item the pool no
--- longer reaches is hidden. That is what carries a spell toggled in the Tracked pane into the preview
--- immediately, with no frame created and no live container replaced.
---
--- The items after the first are chained rather than centred around the configured point, because that
--- is what the live container does: `CustomAuraContainerLayoutDefaults` starts a group at the
--- container's top-left and grows right with `elementSpacing` between elements, and the container fills
--- the anchor `ApplyAnchor` has just placed. Centring put a two-icon preview half a display left of
--- where the two real ones land.
---@param previews SpotlightsAuraPreview[]
function Private.Auras.StylePreviews(previews)
	local auras = Config()

	if not auras then
		return
	end

	local size = Private.FrameConfig.Get()

	-- Both keyed by feature and both per call: the candidate set is walked once however many items read
	-- from it, and `previous` carries the item the next one hangs off. A pooled feature draws one kind
	-- of display, so the feature key alone identifies a chain.
	---@type table<string, integer[]>
	local candidates = {}

	---@type table<string, Frame>
	local previous = {}

	for i = 1, #previews do
		local preview = previews[i]
		local feature = preview.feature
		local display = preview.display
		local config = auras[feature.key][display.key]
		local spellID = feature.spellID

		if feature.multiple then
			local spellIDs = candidates[feature.key]

			if not spellIDs then
				spellIDs = CandidateIDs(feature.Candidates())
				candidates[feature.key] = spellIDs
			end

			spellID = spellIDs[preview.slotIndex]
		end

		-- The feature switch reaches the previews too, so the panel shows what the grid will: a
		-- category the user just switched off has nothing left to preview.
		ApplyAnchor(preview.anchor, preview.anchor:GetParent(), display, config, size,
			auras[feature.key].enabled)

		if feature.multiple then
			if spellID then
				local anchoredTo = previous[feature.key]

				if anchoredTo then
					preview.anchor:ClearAllPoints()
					PixelUtil.SetPoint(preview.anchor, "TOPLEFT", anchoredTo, "TOPRIGHT", config.gap or 0, 0)
				end

				previous[feature.key] = preview.anchor
			else
				-- A pool shorter than `MAX_PREVIEW_AURAS` leaves the tail items with no spell to be
				-- about, and an empty one leaves every item hidden -- which is the honest preview of a
				-- category tracking nothing.
				preview.anchor:Hide()
			end
		end

		-- Guarded on the spell rather than on the hook alone: an item with no spell keeps whatever it
		-- last showed, behind an anchor now hidden, and gets repainted if the pool grows back into it.
		if spellID and display.PreviewArt and preview.spellID ~= spellID then
			display.PreviewArt(preview.regions, spellID)

			preview.spellID = spellID
		end

		display.Style(preview.regions, preview.anchor, config)
		display.Preview(preview.regions, config)
	end
end

--- Every spotlight brought in line with the current settings: built where it should be, restyled
--- where it already was.
---
--- A sweep rather than a queue of pending frames. `EnsureDisplays` early-outs on a table lookup, and
--- a list of frames waiting for combat to end is one more thing that can disagree with reality after
--- a roster change.
---
--- The drain target for `DeferralKey.Auras`.
function Private.Auras.Apply()
	if Private.Events.DeferIfInCombat(DeferralKey.Auras) then
		return
	end

	local auras = Config()

	if not auras then
		return
	end

	Private.SlotHeader.ForEachChild(function(child)
		EnsureDisplays(child)
		Private.Auras.UpdateAssistability(child)
		Private.Auras.ApplyChild(child)
	end)

	-- After the free pass, and only for a batch the debounce has closed. `ApplyChild` can itself
	-- queue a rebuild -- a resize invalidating an inline icon -- so draining first would act on a
	-- list this call is still adding to.
	if not settled or not next(pending) then
		return
	end

	settled = false

	Private.SlotHeader.ForEachChild(function(child)
		ForEachDisplay(child, function(record, feature, display)
			if pending[feature.key .. "." .. display.key] then
				RebuildDisplay(child, feature, display, auras[feature.key][display.key], record)
			end
		end)
	end)

	table.wipe(pending)
end

Private.Events.RegisterHandler(DeferralKey.Auras, Private.Auras.Apply)

Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", Private.Auras.RefreshAssistability)
Private.Events.RegisterEvent("PLAYER_ENTERING_WORLD", Private.Auras.RefreshAssistability)

--- What the player casts to toggle Sense Power, which is **not** the ID the displays track. 361022 is
--- what the toggle puts on the allies it senses; 361021 is the toggle itself, and the only one of the
--- two that appears on an action bar.
local SENSE_POWER_CAST = 361021

local SENSE_POWER_KEY = "sensePower"
local SENSE_POWER_POPUP = "SPOTLIGHTS_SENSE_POWER"

--- How long after a loading screen to look.
---
--- Action bar contents and specialisation both arrive some frames after the screen lifts, and neither
--- has an event meaning "and now they are correct". Guessing short prompts against a bar the client
--- has not filled in yet, which is a wrong answer rather than a late one.
local TOGGLE_CHECK_DELAY = 3

--- The icon currently drawn for Sense Power on an action bar, or nil if it is not on one.
---
--- `FindSpellActionButtons` wants the **base** spell, which 361021 is, and answers with every slot
--- holding it — so the first slot with a texture is as good as any. It may return nothing, which the
--- caller has to distinguish from "on a bar and switched off".
---@return number? texture
local function SensePowerActionTexture()
	local slots = C_ActionBar.FindSpellActionButtons(SENSE_POWER_CAST)

	if not slots then
		return nil
	end

	for i = 1, #slots do
		local texture = C_ActionBar.GetActionTexture(slots[i])

		if texture then
			return texture
		end
	end

	return nil
end

---@param text string
local function PromptSensePower(text)
	-- Built at show time rather than at load, so the localisation table is filled by now. `OKAY` is
	-- the game's own string, one fewer thing to translate.
	StaticPopupDialogs[SENSE_POWER_POPUP] = {
		text = text,
		button1 = OKAY,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}

	StaticPopup_Show(SENSE_POWER_POPUP)
end

--- Tells an Augmentation Evoker when their cooldown displays cannot possibly work.
---
--- **The toggle has no state API.** It is not a shapeshift form, `GetPlayerAuraBySpellID` finds
--- nothing under the cast's own ID, and `IsCurrentAction` reads false either way — all three
--- measured. What *does* change is the icon the action bar draws: an action slot showing something
--- other than the spell's own texture is a toggle that is on.
---
--- Compared against `C_Spell.GetSpellTexture` rather than the active icon's file ID (132160 inactive,
--- 136116 active, observed). Hardcoding the active one would make an art change read as "permanently
--- switched off"; comparing to the base survives a change to either icon, because the mechanism being
--- tested is that they *differ*.
local function CheckSensePower()
	-- Group-gated at the one point every path passes through. The loading-screen and roster triggers
	-- guard themselves, but the specialisation-change event and the display toggle in `SetSetting`
	-- reach here directly -- so a respec or switch-on outside a group would prompt about displays that
	-- have no spotlight to draw on.
	--
	-- A group rather than a raid, because that is where the headers render: a party spotlight runs a
	-- Sense Power display exactly as a raid one does, so a party is a place the prompt is worth making.
	if not IsInGroup() then
		return
	end

	-- Narrower than the class gate the displays use: this reminder is about an ability only
	-- Augmentation has, and telling a Devastation Evoker to switch on a spell they do not own would be
	-- worse than saying nothing.
	if not Private.Utils.IsAugmentation() then
		return
	end

	local auras = Config()
	local sensePower = auras and auras[SENSE_POWER_KEY]

	-- Nothing to warn about if nothing is being tracked. A user who switched the feature off, or every
	-- one of its displays, has already answered the question this prompt asks.
	if not sensePower or not sensePower.enabled then
		return
	end

	if
		not (sensePower.bar.enabled or sensePower.icon.enabled or sensePower.square.enabled
			or sensePower.text.enabled)
	then
		return
	end

	local L = Private.L.Auras
	local texture = SensePowerActionTexture()

	if not texture then
		PromptSensePower(L.SensePowerMissing)

		return
	end

	if texture == C_Spell.GetSpellTexture(SENSE_POWER_CAST) then
		PromptSensePower(L.SensePowerInactive)
	end
end

--- The check, after a delay, which is what every *automatic* trigger uses.
---
--- Delayed because the things that trigger this rewrite an action bar — a loading screen, a
--- specialisation change — and none has a follow-up event meaning "and now the bars are correct".
--- Reading too early reports "not on a bar" about a bar the client has not filled in yet.
---
--- Switching a display on is the exception and stays immediate: the user has just acted, nothing
--- about their bars is in flux, and a prompt three seconds after a click reads as unrelated to it.
local function ScheduleSensePowerCheck()
	C_Timer.After(TOGGLE_CHECK_DELAY, CheckSensePower)
end

--- Whether the player was in a group the last time the roster changed.
---
--- What makes `GROUP_ROSTER_UPDATE` usable here. That event fires on every roster change — a join, a
--- leave, a role swap, a zone-in — and only the *edge* into a group is worth acting on. Without the
--- previous value there is no edge, and the check would run on every roster event.
local wasInGroup = false

-- Four moments where the answer can have changed without us asking.
--
-- Arriving somewhere, but only into a group. A loading screen is the most frequent event here by a
-- wide margin — every portal, every instance, every flight path — and Sense Power being off while
-- solo is not a problem anyone has.
Private.Events.RegisterEvent("LOADING_SCREEN_DISABLED", ScheduleSensePowerCheck)

-- Joining a group, which the loading-screen trigger cannot see: no screen is involved, and the group
-- simply forms around the player.
--
-- This also covers logging straight into one, where `IsInGroup` is still false when the loading
-- screen lifts because group information has not arrived yet. The edge fires when it does.
--
-- A party becoming a raid is deliberately *not* an edge: the player was already in a group, so the
-- prompt has already been made or already been suppressed by the same conditions.
Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	local inGroup = IsInGroup()
	local entered = inGroup and not wasInGroup

	wasInGroup = inGroup

	if entered then
		ScheduleSensePowerCheck()
	end
end)

-- Changing specialisation. Rare, deliberate, the moment a player *becomes* the specialisation this
-- matters to -- but the group gate still applies, enforced inside `CheckSensePower`.
Private.Events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(unit)
	if unit ~= "player" then
		return
	end

	SetFeatureMode()
	Private.AuraPreview.Rebuild()
	ScheduleSensePowerCheck()
end)

--- Writes one aura setting and asks for whichever pass it invalidated.
---
--- **The one entry point for changing anything**, and where the live/frozen split is enforced rather
--- than documented -- though not decided: the display kind classifies its own fields, and this asks.
--- So no caller has to know which kind of setting it is holding, and nothing here has to be revisited
--- when a display grows a field.
---
--- The nil test is a validity check. Every field has a non-nil default and `Private.Migration`'s
--- repair guarantees it, so a `nil` reading back means the caller named a field that does not exist.
---
--- A write of the value already stored does nothing, and for a frozen field that is the difference
--- between a leak and none: re-picking the current texture from a dropdown, or a panel refresh echoing
--- a widget's own value back, would otherwise cost a container and a button on every assigned spotlight
--- for no visible change. A caller that means "rebuild regardless" wants `RequestRebuild`.
---@param featureKey SpotlightsAuraFeatureKey
---@param displayKey SpotlightsAuraDisplayKey
---@param field string
---@param value any
---@return boolean applied
function Private.Auras.SetSetting(featureKey, displayKey, field, value)
	local auras = Config()
	local featureConfig = auras and auras[featureKey]
	local config = featureConfig and featureConfig[displayKey]

	if not config or config[field] == nil then
		return false
	end

	if config[field] == value then
		return true
	end

	config[field] = value

	local feature = FeatureByKey(featureKey)
	local display = DisplayByKey(displayKey)

	if field == "gap" and feature and feature.multiple then
		ApplyGroupLayout(featureKey, displayKey, value or 0)
	end

	-- Neither lookup can fail for a key the database holds a block for, so the fallback is about a
	-- caller inventing one: rebuilding a display that does not exist finds nothing and leaks nothing,
	-- where treating it as live would quietly promise an update the frame never gets.
	local invalidation = feature and display and display.Invalidation(feature, field) or "rebuild"

	if invalidation == "rebuild" then
		RequestRebuild(featureKey, displayKey)
	else
		Private.Events.Request(DeferralKey.Auras)
	end

	-- Switching a Sense Power display on is the moment to find out Sense Power itself is off. Either
	-- display counts: the toggle gates the aura, not the shape it is drawn in. `CheckSensePower` still
	-- applies the group gate, so a switch-on outside a group stays silent. Only ever a false-to-true
	-- transition, which falls out of the unchanged-value early-out above.
	if featureKey == SENSE_POWER_KEY and field == "enabled" and value then
		CheckSensePower()
	end

	return true
end

--- Whether a whole feature is switched on.
---
--- Answers `false` before the database has loaded rather than assuming the default, because the honest
--- reading of "nothing is loaded" is that nothing is being tracked -- and every caller either draws a
--- switch, which the migration corrects a moment later, or decides whether to build frames, which
--- must not happen against a database that is not there yet.
---@param featureKey SpotlightsAuraFeatureKey
---@return boolean
function Private.Auras.IsFeatureEnabled(featureKey)
	local auras = Config()
	local feature = auras and auras[featureKey]

	return feature ~= nil and feature.enabled == true
end

--- Switches a whole feature on or off, and lands it on every live display and preview.
---
--- Not routed through `SetSetting`: this is not a display setting. It sits a level above the bar and
--- the icon and overrides both, and it has no frozen half -- switching off is a `SetShown` on anchors
--- that already exist, and switching on is a build `EnsureDisplays` was already going to do. So
--- nothing here abandons a frame, and **nothing here arms the reload prompt**, which is what makes the
--- dot on the category strip free to click.
---@param featureKey SpotlightsAuraFeatureKey
---@param enabled boolean
---@return boolean applied
function Private.Auras.SetFeatureEnabled(featureKey, enabled)
	local auras = Config()
	local feature = auras and auras[featureKey]

	if not feature or feature.enabled == enabled then
		return false
	end

	feature.enabled = enabled

	-- The free path: `Apply` builds whatever the switch just made buildable and re-anchors the rest,
	-- next frame, or once combat ends.
	Private.Events.Request(DeferralKey.Auras)

	-- Switching Sense Power on is the moment to find out the ability itself is off, for the same
	-- reason a display's own switch is (see `SetSetting`).
	if featureKey == SENSE_POWER_KEY and enabled then
		CheckSensePower()
	end

	return true
end

--- Restores one display to fresh-install values, leaving the shared spell pool alone and the feature's
--- own switch where the user put it: a reset is about how a display looks, and silently switching a
--- category back on would undo a decision the button does not mention.
---
--- Per display rather than per feature because that is the unit the user edits -- the displays are
--- independent, configured one at a time, and a button that reset all of them would discard the ones
--- they were happy with.
---
--- Written through `SetSetting` field by field rather than swapping the block, so a reset takes the
--- same free/frozen routing every other write does: frozen fields coalesce into one rebuild, free ones
--- into one reapply, and the reload prompt arms as a manual edit would. Assigning the table directly
--- would strand the live display pointing at the old config, and skip the leak accounting a rebuild
--- owes.
---
--- Unchanged fields cost nothing: `SetSetting` early-outs when the stored value already matches.
---
--- `Private.Migration.DefaultAuraFeature` hands back a freshly built set every call, so the values
--- read here are never aliased to the database being written.
---@param featureKey SpotlightsAuraFeatureKey
---@param displayKey SpotlightsAuraDisplayKey
function Private.Auras.ResetDisplay(featureKey, displayKey)
	local defaults = Private.Migration.DefaultAuraFeature(featureKey)[displayKey]

	for field, value in pairs(defaults) do
		Private.Auras.SetSetting(featureKey, displayKey, field, value)
	end
end

--- Pushes the current candidate sets onto every display already built.
---
--- **The one thing in this file that changes a frozen-looking property without abandoning a frame.**
--- `includeSpellIDs` is handed to `AddAuraGroup`/`AddAuraSlot` at build time, so a changed spell list
--- looks like it belongs on the rebuild path -- but the container exposes candidate-filter setters,
--- which replace a live display's filters and re-run `UpdateAllAuras` themselves. `CustomAuraContainerInboundMixin`
--- is assembled from `CustomAuraContainerSharedMixin`, so it is ours to call, and it `securecopy`s and
--- validates what it is given.
---
--- The alternative, `RequestRebuild`, would apply just as immediately by building a second container
--- inside the same anchor and abandoning the first. One leaked container per display per toggle is
--- the debt `reloadPending` collects, and a list the user sits and ticks through would turn a
--- settings session into a reload prompt. Nothing here arms that prompt.
---
--- Not combat-guarded, on the same grounds as `SetUnit` in `OnUnitChanged`: this marks a container
--- dirty and refreshes it, and creates nothing. Only *creation* is a protected call.
---
--- Prescience is skipped rather than harmlessly refreshed. Its set is one spell and cannot change,
--- and `SetCandidateFilters` clears a slot's candidates on the way through -- so refreshing it would
--- drop an assigned aura and re-acquire it on the next `UNIT_AURA` for nothing.
function Private.Auras.RefreshCandidates()
	Private.SlotHeader.ForEachChild(function(child)
		ForEachDisplay(child, function(record, feature)
			if feature.multiple then
				local candidates = feature.Candidates()

				record.container:SetAuraGroupCandidateFilters(feature.key, { includeSpellIDs = candidates })
				record.container:SetAuraGroupMaxFrameCount(feature.key, #CandidateIDs(candidates))

				return
			end

			if feature.key ~= SENSE_POWER_KEY then
				return
			end

			record.container:SetAuraSlotCandidateFilters(feature.key, {
				includeSpellIDs = feature.Candidates(),
			})
		end)
	end)

	-- The previews take the same edit, since a pooled one is about whichever spells the filters just
	-- became. A restyle rather than a rebuild: the items already exist and only their spell identities
	-- have moved, and a rebuild per toggle would strand a set of frames per click of the list.
	Private.AuraPreview.Restyle()
end

--- Rebuilds the displays that a newly registered medium actually fixes, and no others.
---
--- Called by `Private.Media`'s LibSharedMedia callback, which fires once per key every time any addon
--- registers media -- in bulk during login, for keys we mostly do not care about.
---
--- **The filter is `record.unresolved`, not the stored setting.** Every display naming this key looks
--- like a candidate, but only the ones built *before* the registration are wearing a fallback because
--- of it; one built afterwards resolved it correctly, and rebuilding it abandons a container and arms
--- a reload prompt for nothing the user can see. That was the bug: a spotlight assigned early enough
--- to build its displays before another addon's login-time registration offered a reload every login.
---@param mediatype string
---@param key string
function Private.Auras.OnMediaRegistered(mediatype, key)
	local lookup = MediaKey(mediatype, key)

	Private.SlotHeader.ForEachChild(function(child)
		ForEachDisplay(child, function(record, feature, display)
			if record.unresolved[lookup] then
				RequestRebuild(feature.key, display.key)
			end
		end)
	end)
end

--- The tracked feature keys, for callers that need to walk the aura config block.
---
--- **Exists because `pairs` over `Private.DB.auras` is no longer a list of features.** That block
--- gained the pools' own tables -- `cooldowns`, `custom`, `defensives`, `defensiveCustom` -- beside the
--- features, and anything walking it whole finds a table with no `bar` and no `icon` and indexes nil,
--- which is how `Media.lua` broke. Answering with the keys is safer than every caller knowing them: a
--- feature added to `FEATURES` reaches those callers on its own.
---@return string[]
function Private.Auras.FeatureKeys()
	local keys = {}

	for i = 1, #FEATURES do
		keys[i] = FEATURES[i].key
	end

	return keys
end

--- Whether a feature pools several of the spotlighted player's auras into one display rather than
--- watching a single spell.
---
--- The options panel's question, and the only thing that makes the gap between icons mean anything:
--- a feature with one aura to draw has nothing to space it against.
---@param featureKey SpotlightsAuraFeatureKey
---@return boolean
function Private.Auras.IsPooled(featureKey)
	local feature = FeatureByKey(featureKey)

	return feature ~= nil and feature.multiple
end

--- Whether a feature draws a given kind of display, so the panel can leave out a section for one
--- nothing will ever render. See `DrawsDisplay`, which is what both build paths ask.
---@param featureKey SpotlightsAuraFeatureKey
---@param displayKey SpotlightsAuraDisplayKey
---@return boolean
function Private.Auras.HasDisplay(featureKey, displayKey)
	local feature = FeatureByKey(featureKey)

	if not feature then
		return false
	end

	local display = DisplayByKey(displayKey)

	return display ~= nil and DrawsDisplay(feature, display)
end

--- The shipped spell lists, for the options panel to draw rows from.
---
--- Handed out rather than copied, because the panel only reads them -- and grouped by class, which is
--- the one thing the flat candidate set throws away and the panel needs back.
---
--- Everything below is a wrapper over one pool operation. The pair exists so the options panel names a
--- pool by asking for it, rather than by knowing which saved table and which default rule it wants.
---@return table<integer, table<integer, boolean>>
function Private.Auras.Cooldowns()
	return COOLDOWNS
end

---@return table<integer, table<integer, boolean>>
function Private.Auras.Defensives()
	return DEFENSIVES
end

---@param spellID integer
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean
function Private.Auras.IsCooldownEnabled(spellID, custom)
	return IsPoolEnabled(POOLS.cooldown, spellID, custom)
end

---@param spellID integer
---@param enabled boolean
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean applied
function Private.Auras.SetCooldownEnabled(spellID, enabled, custom)
	return SetPoolEnabled(POOLS.cooldown, spellID, enabled, custom)
end

---@return integer[]
function Private.Auras.CustomCooldowns()
	return CustomPoolSpells(POOLS.cooldown)
end

---@param spellID integer
---@return boolean added false when it is already in the list
function Private.Auras.AddCustomCooldown(spellID)
	return AddCustomPoolSpell(POOLS.cooldown, spellID)
end

---@param spellID integer
---@return boolean removed
function Private.Auras.RemoveCustomCooldown(spellID)
	return RemoveCustomPoolSpell(POOLS.cooldown, spellID)
end

---@return boolean applied
function Private.Auras.ResetCooldowns()
	return ResetPool(POOLS.cooldown)
end

---@param spellID integer
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean
function Private.Auras.IsDefensiveEnabled(spellID, custom)
	return IsPoolEnabled(POOLS.defensive, spellID, custom)
end

---@param spellID integer
---@param enabled boolean
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean applied
function Private.Auras.SetDefensiveEnabled(spellID, enabled, custom)
	return SetPoolEnabled(POOLS.defensive, spellID, enabled, custom)
end

---@return integer[]
function Private.Auras.CustomDefensives()
	return CustomPoolSpells(POOLS.defensive)
end

---@param spellID integer
---@return boolean added false when it is already in the list
function Private.Auras.AddCustomDefensive(spellID)
	return AddCustomPoolSpell(POOLS.defensive, spellID)
end

---@param spellID integer
---@return boolean removed
function Private.Auras.RemoveCustomDefensive(spellID)
	return RemoveCustomPoolSpell(POOLS.defensive, spellID)
end

---@return boolean applied
function Private.Auras.ResetDefensives()
	return ResetPool(POOLS.defensive)
end

--- Whether the user should be offered a reload, because frames have been abandoned or are about to
--- be.
---
--- What keeps the prompt from appearing after a session of moving sliders: everything on the free
--- path leaves this false, and a user who never touched a texture or a colour has nothing to reclaim.
---
--- Two questions, because one does not cover it. `reloadPending` answers for rebuilds that have
--- happened; `pending` answers for the one still inside the debounce window, which is the change most
--- likely to have been the last one made. Without the second, changing a colour and closing within
--- `REBUILD_DELAY` would never prompt.
---
--- The cost of including `pending` is one false positive: a frozen setting changed on a *disabled*
--- display, closed within the same window, prompts for a rebuild that will find nothing. Waiting out
--- the timer makes it correct, and modelling which pending rebuilds will actually land is more
--- machinery than a spurious offer is worth.
---@return boolean
function Private.Auras.NeedsReload()
	return reloadPending or next(pending) ~= nil
end

--- Records that the user has been asked and answered, so they are not asked again until something
--- else is abandoned.
---
--- Called for **both** answers. "Reload now" makes it moot, and saying so anyway means the one code
--- path does not depend on the reload happening — a reload refused by a loading screen or a blocking
--- addon would otherwise leave the prompt armed forever.
function Private.Auras.AcknowledgeReload()
	reloadPending = false
end

--- Points a spotlight's containers at its unit, and builds them the first time.
---@param frame SpotlightsUnitFrame
---@param unit string?
function Private.Auras.OnUnitChanged(frame, unit)
	-- A released unit needs nothing done. The header hides the frame, and each container's own
	-- `OnHide` drops its `UNIT_AURA` registration and clears its auras -- so the displays stop without
	-- a call from us. `SetUnit` asserts on a non-string, so there is nothing to pass here anyway.
	if unit == nil then
		return
	end

	-- Before the creation attempt and outside its combat guard. `SetUnit` registers events and marks
	-- the container dirty; none of that is a protected call, so a roster change landing mid-combat
	-- still repoints existing displays at the right player. Only *creation* has to wait.
	ForEachDisplay(frame, function(record)
		record.container:SetUnit(unit)
	end)

	EnsureDisplays(frame)
	Private.Auras.UpdateAssistability(frame)
end
