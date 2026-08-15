---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuras
Private.Auras = {}

--- Tracked aura displays: which spells a spotlight watches for, and what it draws when one lands.
---
--- Containers cannot be removed (`CustomAuraContainerInboundMixin` exposes `AddAuraSlot` and no
--- inverse), so a specialisation change hides old records and discards them from the active map
--- rather than tearing them down.

local DeferralKey = Private.Enum.DeferralKey

-- No `local Enum = Private.Enum` here, unlike the rest of the addon: this file needs the *game's*
-- `Enum` for `Enum.StatusBarInterpolation` below, and shadowing it would nil-index that call site.

--- Prescience's slot shows only the copy *we* applied, which `PLAYER` says.
local OWN_FILTER =
	AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful, AuraUtil.AuraFilters.Player)

--- Sense Power's slot pools the spotlighted player's own cooldowns, none of them cast by us, so
--- `PLAYER` would discard every one before `includeSpellIDs` was consulted. The spell-ID set narrows
--- instead, which no longer excludes another Evoker's Sense Power on the same unit.
local ANY_FILTER = AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful)

---@class SpotlightsAuraFeature
---@field key SpotlightsAuraFeatureKey indexes `SpotlightsAurasConfig`, and names the slot inside its container
---@field spellID integer the spell the display is *about*: its icon, and its preview
---@field filter string the aura filter string its slot parses with
---@field Candidates fun(): table<integer, true> every spell its slot may show, `spellID` included
---@field multiple boolean

--- Which pass a changed setting needs: a re-anchor on the next frame, or a replacement container once
--- the value stops moving.
---@alias SpotlightsAuraInvalidation "live" | "rebuild"

--- One kind of display, and the only place the difference between a bar, an icon, a square, a bare
--- countdown and a health-bar tint lives.
---
--- `config` is loose because the five kinds are configured by different shapes. The verbs are split
--- because a live display runs `Create`/`Style`/`Register` once and is then untouchable, while a
--- preview runs `Style` on every settings change -- sharing it is what makes a preview show what will
--- ship. `Create`'s `frame` is read only by `frameColor`, and is nilable because the grid preview's
--- stand-in spotlight has no health bar to tint.
---@class SpotlightsAuraKind
---@field key SpotlightsAuraDisplayKey
---@field Create fun(host: Frame|table, config: table, spellID: integer, everything: boolean, frame: SpotlightsUnitFrame?): SpotlightsAuraRegions
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

--- The game's Big Defensive flag covers personal and single-target external mitigation only, so the
--- group-wide effects it misses are added by hand and ship on.
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
---@return SpotlightsAurasConfig?
local function Config()
	return Private.DB and Private.DB.auras
end

--- One spell pool: a shipped catalogue grouped by class, sparse overrides over it, and the user's own
--- IDs beside it.
---
--- Cooldowns and defensives differ only in what a catalogue entry *means*, so that lives in
--- `DefaultEnabled` and every operation below is written once. They keep separate saved tables and
--- separate features; this is shared behaviour, not a merged pool.
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

--- The one place either table is reached by key. The nil case is the window before the migration and
--- `Repair` have run, which a slash command during login reaches.
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
--- Recomputed on every call rather than cached: this is what a slot's `includeSpellIDs` is built from,
--- so recomputing is what makes a toggle reach a live display.
---
--- Deliberately not narrowed to the watched unit's class -- a container is repointed at another player
--- on every roster change, so a per-class set would have to be recomputed in the right order relative
--- to `SetUnit`. An absent override means the shipped default, which is why a catalogue needs no
--- migration when it grows.
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

	-- Opposite default to the built-ins: an ID typed into a box is a guess, so it counts only once
	-- switched on.
	if custom then
		for spellID, enabled in pairs(custom) do
			if enabled then
				candidates[spellID] = true
			end
		end
	end

	return candidates
end

--- The asymmetry between the two lists lives here and nowhere else: a built-in is on unless it
--- deviates from its catalogue entry, and a custom entry is off unless switched on.
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
--- A built-in returning to its default is cleared rather than stored, so the override table holds only
--- the user's actual decisions and a spell added to a catalogue later stays at its shipped default. A
--- built-in the catalogue does not list is refused: an override on one could never reach a candidate
--- set.
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

		-- Not folded into `enabled ~= default and enabled or nil`: that stores nil when switching a
		-- default-on spell off, which reads as "default" downstream and leaves it enabled.
		if enabled == default then
			overrides[spellID] = nil
		else
			overrides[spellID] = enabled
		end
	end

	Private.Auras.RefreshCandidates()

	return true
end

--- The user's own spell IDs, sorted: `pairs` order would reshuffle the list whenever the panel
--- reopened.
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

--- Adds a spell the user typed in, switched on despite the custom default of off: adding one *is* the
--- act of asking for it. The default governs entries that arrived some other way.
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

--- Removes one of the user's own entries. No reload is owed, though this looks most like the case that
--- needs one: `SetCandidateFilters` drops every candidate and re-acquires from the next scan, so a slot
--- showing the removed spell empties on its own.
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

--- Puts every shipped spell back to its default, which is not the same as on -- some defensives ship
--- switched off. Clearing the override table *is* the reset, since it holds only the user's deviations.
---
--- The user's own entries are left alone: they have no shipped default to return to, so "default" for
--- one could only mean deleting it.
---@param pool SpotlightsAuraPool
---@return boolean applied
local function ResetPool(pool)
	local overrides = PoolTables(pool)

	-- Already the default state; refreshing every live display to say so would sweep the whole raid
	-- for no change.
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

--- The cooldown pool seeded with Sense Power, rather than a pool of its own. The defensive pool is
--- deliberately not in it.
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

--- Prescience is one spell from one caster, while Sense Power shares its slot with every major
--- cooldown the spotlighted player might have, cast by them rather than by us -- so a feature is no
--- longer a spell ID alone.
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

--- Both sets rather than the active `FEATURES`: a specialisation change swaps the set before the
--- options strip has corrected its selection against it, and the two disagree until it does.
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

--- How faint a preview bar's unfilled remainder is. Multiplied by the display's own opacity on top,
--- since it sits under the same anchor.
local TRACK_ALPHA = 0.35

--- How long a frozen setting has to stop changing before anything is rebuilt. A drag writes the
--- database every frame it moves, which without the debounce is sixty leaked containers per spotlight.
local REBUILD_DELAY = 0.4

--- Displays waiting on a rebuild, keyed `feature.display`.
---@type table<string, boolean>
local pending = {}

--- Whether a rebuild has actually abandoned a container since the user was last asked about it. Set
--- where the leak happens rather than where it is requested: a rebuild that finds nothing owes no
--- reload, and offering one would ask the user to fix a problem they do not have.
local reloadPending = false

---@type FunctionContainer?
local rebuildTimer

--- Whether the debounce has expired, so `pending` is a settled batch rather than a gesture still in
--- progress. Separate from "is `pending` non-empty": `DeferralKey.Auras` is requested by the free path
--- too, and without this a free setting changed mid-drag would drain the drag's half-finished batch.
local settled = false

--- Queues a display for rebuilding once its settings stop moving. Restart-on-change, so a drag of any
--- length costs one rebuild at the end; the drain runs through `Apply`, which handles combat.
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

--- The formatter for the icon's countdown text, replacing the container's default, which always
--- renders a unit and so cannot produce the bare number this display wants
--- (`Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua:75-98`).
---
--- Ours, not Blizzard's: `AuraContainerInbound.GetDefaultAuraDurationFormatter` hands back the global
--- instance, and mutating that would change every aura display in the game.
---
--- `%.0f`/`%.1f` rather than `%d`, so the already-rounded value never trips an integer specifier. See
--- docs/notes/AuraDurationText.md for the breakpoint choice.
local DURATION_FORMATTER = C_StringUtil.CreateNumericRuleFormatter()

DURATION_FORMATTER:SetBreakpoints({
	{ threshold = 0, step = 0.1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%.1f" },
	{ threshold = 3, step = 1,   rounding = Enum.NumericRuleFormatRounding.Up,   format = "%.0f" },
})

--- `Create`'s asymmetry: a real display builds only the optional regions its config asks for, because
--- an unwanted region under an aura button can never be reclaimed, while a preview builds all of them
--- and lets `Style` decide what is shown. Hence `everything`.

--- Lifted clear of its host's frame level so it draws over the bar fill, the icon art and the cooldown
--- swipe rather than under whichever was created last.
---@param host Frame|table
---@return SpotlightsAuraBorder
local function CreateBorder(host)
	---@type SpotlightsAuraBorder
	local border = CreateFrame("Frame", nil, host, "BackdropTemplate")

	border:SetAllPoints()
	border:SetFrameLevel(host:GetFrameLevel() + 5)

	return border
end

--- `SetAllPoints` rather than an outset: a backdrop edge straddles the frame's boundary, so a border on
--- the display's own rect stays the size the settings report.
---
--- `None` hides rather than clears: `SetBackdrop` errors on a backdrop with neither a background nor an
--- edge, and LSM resolves `None` to an empty path.
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

--- The swipe and the countdown text, which an icon and a square draw identically.
---@param host Frame|table
---@param config SpotlightsAuraIconConfig|SpotlightsAuraSquareConfig
---@param regions SpotlightsAuraRegions
---@param everything boolean
local function CreateDuration(host, config, regions, everything)
	if config.showSwipe or everything then
		-- `CooldownFrameTemplate` carries `setAllPoints` and starts hidden, both wanted: `Shown` is a
		-- secret aspect from the moment `SetDurationCooldown` returns, so it could not be shown from
		-- here anyway.
		regions.swipe = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")

		regions.swipe:SetDrawEdge(false)

		-- Driven by an aura timer rather than a spell cooldown; Blizzard sets this on every aura-fed
		-- Cooldown it owns.
		regions.swipe:SetUseAuraDisplayTime(true)

		-- The cooldown's own numbers would sit under our duration text saying the same thing, a pixel
		-- out of alignment.
		regions.swipe:SetHideCountdownNumbers(true)
	end

	if config.showText or everything then
		-- Own layer above the swipe rather than *on* it: a Cooldown is a frame, so its shading draws
		-- above anything on the host whatever layer we ask for, and hanging the text off the swipe
		-- made switching the swipe off take the duration with it.
		local layer = CreateFrame("Frame", nil, host)

		layer:SetAllPoints()
		layer:SetFrameLevel(host:GetFrameLevel() + 6)

		regions.text = layer:CreateFontString(nil, "OVERLAY")
		regions.text:SetPoint("CENTER")
	end
end

--- The `SetShown` calls are no-ops on a live display, where a region exists only when wanted, and are
--- the point on a preview.
---@param regions SpotlightsAuraRegions
---@param config SpotlightsAuraIconConfig|SpotlightsAuraSquareConfig
local function StyleDuration(regions, config)
	if regions.swipe then
		regions.swipe:SetShown(config.showSwipe)
	end

	if regions.text then
		-- `OUTLINE` unconditionally: a duration sits over spell art, a coloured block or a swipe, and is
		-- illegible on any of them without it at every font and size.
		regions.text:SetFont(Private.Media.Font(config.font), config.fontSize, "OUTLINE")
		regions.text:SetShown(config.showText)
	end
end

--- Hands the swipe and the countdown to the aura button, after which neither is ours: the text gains
--- `Text`, `Alpha` and `VertexColor` as secret aspects the moment this returns.
---
--- The formatter is the only thing still ours to decide -- see `DURATION_FORMATTER`. Its options table
--- is copied in, so passing one shared formatter to every display is safe.
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

--- Fills a preview's swipe and countdown with a made-up moment. Re-armed on every restyle rather than
--- looped, so a preview runs down and stops if left alone.
---
--- **The swipe is guarded on the setting here rather than left to `Style`, because `SetCooldown` shows
--- the frame it arms** -- a swipe just switched off was hidden by `Style` and un-hidden one line later.
---@param regions SpotlightsAuraRegions
---@param config SpotlightsAuraIconConfig|SpotlightsAuraSquareConfig
local function PreviewDuration(regions, config)
	if regions.swipe and config.showSwipe then
		regions.swipe:SetCooldown(GetTime() - 8, 20)
	end

	-- No such guard needed: `SetText` on a hidden font string leaves it hidden. Fractional, because the
	-- sub-three-second decimal is the one part of the format a preview can show.
	if regions.text then
		regions.text:SetText("2.5")
	end
end

--- The inline icon is created only when the config wants one, unless `everything` says otherwise: a
--- texture under an aura button can never be reclaimed, and its toggle is frozen.
---@param host Frame|table
---@param config SpotlightsAuraBarConfig
---@param spellID integer
---@param everything boolean
---@return SpotlightsAuraRegions
local function CreateBar(host, config, spellID, everything)
	---@type SpotlightsAuraRegions
	local regions = { bar = CreateFrame("StatusBar", nil, host) }

	-- The unfilled remainder, preview-only: a `StatusBar` draws nothing where it is not filled and a
	-- preview's fill is a fixed two thirds, so without this the pane reports a bar a third narrower
	-- than the one being configured. On `host` rather than on the bar, so it draws under the fill.
	if everything then
		regions.barTrack = host:CreateTexture(nil, "BACKGROUND")
		regions.barTrack:SetAllPoints(regions.bar)
	end

	if config.showIcon or everything then
		regions.barIcon = host:CreateTexture(nil, "ARTWORK")

		-- The feature's own spell, which is what a preview wants -- it has no aura and no button. On a
		-- live display `RegisterBar` hands the texture over and the container repaints it per aura, so
		-- this shows for a fraction of a frame.
		regions.barIcon:SetTexture(C_Spell.GetSpellTexture(spellID))
		regions.barIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end

	-- Last, so it draws over the fill and the inline icon both.
	regions.border = CreateBorder(host)

	return regions
end

--- The bar is anchored rather than sized: it fills its host, which fills the container, which fills the
--- anchor, so the one rect anyone sets is the anchor's. A bar sized here would never resize again.
---
--- `SetStatusBarTexture` resolves the LibSharedMedia key when called, and on a live display it is never
--- called again -- so an addon supplying the user's chosen texture that loads after us needs a rebuild,
--- which is what `Private.Media`'s registration callback is for.
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

	-- **Before `RegisterBar`**: from the moment `SetDurationBar` returns the bar carries
	-- `SecretAspect.BarValue` and the container owns its fill.
	bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")

	-- Same ordering rule. `SetReverseFill` rather than the equivalent `SetFillStyle`, to read next to
	-- the orientation above.
	bar:SetReverseFill(config.reverseFill)

	bar:ClearAllPoints()

	-- Same material and colour as the fill, faint, so it reads as this bar's remainder rather than as a
	-- second bar behind it.
	if regions.barTrack then
		regions.barTrack:SetTexture(path)
		regions.barTrack:SetVertexColor(config.r, config.g, config.b, TRACK_ALPHA)
	end

	if icon then
		-- No-op on a live display, where the region exists only when wanted; the preview is the caller
		-- this is for.
		icon:SetShown(config.showIcon)
	end

	-- **The one measurement here that a resize invalidates.** A square needs one dimension told to it
	-- and there is no anchor for "as wide as I am tall", so the icon is squared against the size the
	-- display has now -- frozen on a live display until a rebuild, re-measured on a preview.
	--
	-- Two branches rather than computed points, because the vertical case transposes three separate
	-- things: which points each region pins, which way `iconSide` reads, and which dimension squares.
	if config.showIcon and icon then
		icon:ClearAllPoints()

		if vertical then
			-- `iconSide` keeps its `LEFT`/`RIGHT` storage in both orientations: the pair means one end
			-- of the bar and the other, and a vertical bar's ends are its top and bottom.
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
--- **The only way a display can name what it is showing.** Sense Power's slot pools the whole cooldown
--- list beside its own spell, so a static icon would put a bar tracking `Recklessness` under the Sense
--- Power icon.
---
--- The cost is that `AuraContainerUtil.SetIconTextureForAura` finishes with
--- `SetTexture(secretwrap(icon))`, so the texture's contents are no longer ours to read or repaint.
--- Neither is something we do.
---
--- No empty state to handle: `ApplyAuraInstance` runs `ApplyIcon` immediately before `ApplyVisibility`,
--- so the `QUESTION_MARK_ICON` fallback is set and concealed in the same pass.
---@param button table
---@param icon Texture
local function SetAuraIcon(button, icon)
	button:SetIcon(icon)
end

--- Hands the bar and the inline icon to the aura button. No `SetMinMaxValues` and no `SetValue`, here
--- or ever: `SetDurationBar` adds `SecretAspect.BarValue`, and from this point the container drives the
--- fill with a duration object we never see the contents of.
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

--- Fills a preview bar with a made-up fraction -- plain numbers, because nothing about a preview is
--- secret. Two thirds rather than full, so the bar reads as a countdown in progress.
---@param regions SpotlightsAuraRegions
---@param _ SpotlightsAuraBarConfig the settings, which a bar's fake fill has no reason to consult
local function PreviewBar(regions, _)
	regions.bar:SetMinMaxValues(0, 1)
	regions.bar:SetValue(0.65)
end

--- **Not `SetAuraIcon`**, which would make the texture's contents secret and its identity the
--- container's to decide. A preview has no button, so its art is the only thing saying which spell it
--- is about, and has to follow the candidate set the user edits while looking at it.
---@param regions SpotlightsAuraRegions
---@param spellID integer
local function PreviewBarArt(regions, spellID)
	if regions.barIcon then
		regions.barIcon:SetTexture(C_Spell.GetSpellTexture(spellID))
	end
end

--- Everything here fills its host, so the display's size is the anchor's and stays live. The texture is
--- the *preview's* icon and only incidentally a live display's first frame: a preview never reaches
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

	-- The border every icon file ships with, cropped off as every icon display in the game does.
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

--- No spell art and therefore **no `SetIcon`**, which is the whole difference from an icon: this says an
--- aura is up and how long is left, nothing about which one. That is what makes it readable at a size
--- where an icon is not.
---
--- The block is a plain colour texture rather than a LibSharedMedia one, which keeps this display off
--- the media-registration rebuild path -- see `UnresolvedMedia`, which finds nothing here but the
--- border.
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

--- `SetColorTexture` rather than a white texture tinted by `SetVertexColor`, and three channels not
--- four -- opacity is the anchor's, which is what keeps it live.
---@param regions SpotlightsAuraRegions
---@param _ Frame the anchor, which a square has no use for because it is sized directly by config
---@param config SpotlightsAuraSquareConfig
local function StyleSquare(regions, _, config)
	local block = regions.block --[[@as Texture]]

	block:SetColorTexture(config.r, config.g, config.b)

	StyleDuration(regions, config)
	StyleBorder(regions, config)
end

--- **Not `CreateDuration`.** That builds a swipe and a font string from `showSwipe`/`showText`, and this
--- display has neither field: the text is not an option on it, it *is* it.
---
--- The font string sits on a layer above the border for the reason the icon's sits above the swipe -- a
--- border is a child frame, so a thick edge would otherwise cut into the number it surrounds.
---@param host Frame|table
---@return SpotlightsAuraRegions
local function CreateText(host)
	local layer = CreateFrame("Frame", nil, host)

	layer:SetAllPoints()
	layer:SetFrameLevel(host:GetFrameLevel() + 6)

	---@type SpotlightsAuraRegions
	local regions = { text = layer:CreateFontString(nil, "OVERLAY") }

	-- Centred in the rect `Size` derives from the font size, which is all that rect is for.
	regions.text:SetPoint("CENTER")

	regions.border = CreateBorder(host)

	return regions
end

--- **`SetTextColor` has to happen here and can never happen again.** `SetDurationText` adds `Text`,
--- `Alpha` and `VertexColor` to the font string's secret aspects the moment it returns, and
--- `InitializeFrame` runs this immediately before it -- so this display's colour picker is a rebuild.
---
--- No `SetShown`: on the other two kinds the countdown is an option, here it is the display, and being
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

--- The one region a health-bar tint is made of: a colour over the bar, parented under the button and
--- anchored outside it.
---
--- **The only kind whose drawn region is not inside the anchor's rect**, because nothing of ours may
--- know an aura is up. `CustomAuraButtonPrivateMixin:ApplyVisibility` is
--- `self:SetShown(secretwrap(auraData ~= nil))`, so a plain child region of the button appears and
--- disappears with the aura on its own. Inbound regions must be descendants of the button, but anchors
--- may point anywhere (`Blizzard_AuraContainerUtil.lua:265`).
---
--- **Not `SetVertexColorFromBoolean` on the bar's own texture.** That stamps `VertexColor` and `Alpha`
--- onto whatever it is called on permanently (`SimpleRegionAPIDocumentation.lua:134-145`), and the
--- health bar's texture is written by ordinary code on every class-colour update and every fade -- so
--- the first plain write after the stamp would be a tainted write to a secret aspect. See
--- `docs/issues/AuraContainerNotes.md`.
---
--- **Anchored to the bar rather than to its fill, which is correctness rather than preference.** The
--- fill's rect is the health value, so it is legitimately zero-wide, and `SetAllPoints` against a region
--- with no rect silently falls back to the parent instead of erroring. Unrecoverable here: the button's
--- access restriction lands the moment `initializeFrame` returns, so a wrong anchor can never be
--- corrected. See docs/notes/AuraFrameColorTint.md.
---
--- No region at all without a spotlight: the grid preview's host has no health bar, and the honest
--- answer is to draw nothing rather than tint the host.
---@param host Frame|table
---@param _ SpotlightsAuraFrameColorConfig styling is `StyleFrameColor`'s, as on every other kind
---@param __ integer the spell, which a display drawing no art has nothing to do with
---@param ___ boolean `everything`, which has no optional region to decide
---@param frame SpotlightsUnitFrame? the spotlight whose health bar is tinted, absent in the grid preview
---@return SpotlightsAuraRegions
local function CreateFrameColor(host, _, __, ___, frame)
	if not frame then
		return {}
	end

	---@type SpotlightsAuraRegions
	local regions = { tint = host:CreateTexture(nil, "ARTWORK") }

	regions.tint:SetAllPoints(frame.healthBar)

	return regions
end

--- `SetColorTexture` for the square's reason, and three channels not four -- opacity is the anchor's,
--- which is what makes the tint's strength draggable against a real raid.
---
--- No `StyleBorder`: there is no rect of this display's own for an edge to go around.
---@param regions SpotlightsAuraRegions
---@param _ Frame the anchor, whose rect this display deliberately ignores
---@param config SpotlightsAuraFrameColorConfig
local function StyleFrameColor(regions, _, config)
	local tint = regions.tint

	-- Absent in the grid preview, which has no health bar for `Create` to have anchored one to.
	if not tint then
		return
	end

	tint:SetColorTexture(config.r, config.g, config.b)
end

--- What every kind's anchor carries, and therefore what stays live on all five: the anchor is a plain
--- frame of ours above the aura button's access restriction, so everything `ApplyAnchor` writes reaches
--- a built display for free.
---
--- `point`, `x` and `y` mean nothing to the health-bar tint, whose region is anchored to the health bar
--- instead. Classified regardless, because `Invalidation` has to answer for every field of every block.
---@type table<string, SpotlightsAuraInvalidation>
local ANCHOR_INVALIDATION = {
	enabled = "live",
	alpha = "live",
	point = "live",
	x = "live",
	y = "live",
}

--- The border, which no kind can change after the fact: a backdrop belongs to a frame under the aura
--- button.
---
--- `borderA` is classified with the other three channels because all four reach that backdrop through
--- one `SetBackdropBorderColor`. Left out, an alpha write took the live path and changed nothing but the
--- preview.
---@type table<string, SpotlightsAuraInvalidation>
local BORDER_INVALIDATION = {
	borderTexture = "rebuild",
	borderSize = "rebuild",
	borderR = "rebuild",
	borderG = "rebuild",
	borderB = "rebuild",
	borderA = "rebuild",
}

--- The swipe and the countdown, shared by the icon and the square. All four decide which regions exist
--- under the button, or what the font string sitting there is made of.
---@type table<string, SpotlightsAuraInvalidation>
local DURATION_INVALIDATION = {
	showSwipe = "rebuild",
	showText = "rebuild",
	font = "rebuild",
	fontSize = "rebuild",
}

--- One kind's classification, merged from the groups it shares with the others and the fields that are
--- its own. Every field of that kind's config block has to appear in exactly one table handed in.
---
--- `Invalidation` answers `rebuild` for a field it does not find, which is the safe direction -- a
--- setting wrongly rebuilt still lands, one wrongly called live is silently dropped below the access
--- restriction -- but it costs a container per assigned spotlight, so an omission is a bug rather than
--- a default worth relying on.
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

--- A bar's own half, all built into regions under the button. Width and height are the anchor's, so a
--- bar resizes live.
local BAR_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, {
	width = "live",
	height = "live",
	texture = "rebuild",
	r = "rebuild",
	g = "rebuild",
	b = "rebuild",
	orientation = "rebuild",
	reverseFill = "rebuild",
	showIcon = "rebuild",
	iconSide = "rebuild",
})

--- An icon's own half is its dimensions and the spacing between pooled copies: the art is the button's.
--- `gap` is the group's flow-layout spacing, which `ApplyGroupLayout` writes to a live container.
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
--- anchor's alpha and does not: `SetDurationText` adds `VertexColor` to the font string's secret
--- aspects, so a colour written after the build is dropped below the access restriction.
---
--- `fontSize` owes a re-anchor as well as a rebuild, since `Size` derives the rect from it -- but that
--- comes free: draining a rebuild runs `ApplyChild` first, which is where `ApplyAnchor` reads the size.
local TEXT_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, {
	font = "rebuild",
	fontSize = "rebuild",
	r = "rebuild",
	g = "rebuild",
	b = "rebuild",
})

--- A health-bar tint's own half is the tint's colour. It has no size fields at all: the drawn region is
--- anchored to the health bar and the anchor's rect is a placeholder.
local FRAME_COLOR_INVALIDATION = Classification(ANCHOR_INVALIDATION, BORDER_INVALIDATION, {
	r = "rebuild",
	g = "rebuild",
	b = "rebuild",
})

--- How wide and how tall a bare countdown's anchor is, per point of font size. Derived rather than
--- measured, because the font string's `Text` is secret from the moment the display is registered; four
--- ems fits the widest thing the formatter produces.
---
--- Nothing is clipped to this rect -- the string is centred in it and draws past it if it has to --
--- which keeps the anchor's nine points meaning what they mean on every other display.
local TEXT_WIDTH_PER_POINT, TEXT_HEIGHT_PER_POINT = 4, 1.4

--- The anchor's rect for a health-bar tint, a placeholder rather than a size. **The one kind where the
--- anchor's rect is not the display's rect**, which `Invalidated` and `builtWidth`/`builtHeight` assume
--- the opposite of. The drawn region follows the health bar, so this rect is never looked at. Not zero,
--- because `SetSize(0, 0)` means "take your size from your anchors".
local FRAME_COLOR_ANCHOR_SIZE = 1

--- The five displays a feature can draw. `Size` is a function rather than a flag because the kinds have
--- different config shapes.
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

		-- The inline icon and nothing else: it was squared against one axis at build time and sits below
		-- the access restriction, so a resize leaves it a rectangle only a new button can fix. Which
		-- axis is the orientation's answer.
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
		-- inside `initializeFrame`, below the access restriction, while a single-aura icon's button
		-- fills the anchor and `ApplyAnchor` resizes it live.
		Invalidation = function(feature, field)
			if feature.multiple and (field == "width" or field == "height") then
				return "rebuild"
			end

			return ICON_INVALIDATION[field] or "rebuild"
		end,

		-- No `Invalidated`: everything under an icon's button fills it, at every size.
	},
	{
		key = "square",
		Create = CreateSquare,
		Style = StyleSquare,
		Register = RegisterDuration,
		Preview = PreviewDuration,

		-- No `PreviewArt`: a block draws no spell art.

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

		-- `RegisterDuration` unchanged: it hands over whichever of the swipe and the countdown exist, and
		-- this display has only the second.
		Register = RegisterDuration,

		-- Likewise `PreviewDuration`: with no `showSwipe` field here, what is left is the sample number
		-- this display is entirely made of.
		Preview = PreviewDuration,

		-- No `PreviewArt`: a number draws no spell art.

		Size = function(config)
			return config.fontSize * TEXT_WIDTH_PER_POINT, config.fontSize * TEXT_HEIGHT_PER_POINT
		end,

		Invalidation = function(_, field)
			return TEXT_INVALIDATION[field] or "rebuild"
		end,

		-- No `Invalidated`. The rect is the font size's answer rather than the spotlight's, so a resize
		-- cannot break anything the button was built against.
	},
	{
		key = "frameColor",
		Create = CreateFrameColor,
		Style = StyleFrameColor,

		-- `RegisterDuration` and `PreviewDuration` unchanged: both branch on regions this kind has none
		-- of, so both are no-ops here.
		Register = RegisterDuration,
		Preview = PreviewDuration,

		-- No `PreviewArt`: a colour draws no spell art.

		Size = function()
			return FRAME_COLOR_ANCHOR_SIZE, FRAME_COLOR_ANCHOR_SIZE
		end,

		Invalidation = function(_, field)
			return FRAME_COLOR_INVALIDATION[field] or "rebuild"
		end,

		-- No `Invalidated`. The drawn region is anchored to the health bar rather than sized against the
		-- anchor, so a spotlight resize moves it rather than breaking it.
	},
}

--- A pooled feature draws icons only. A column of duration bars over one spotlight is unreadable, and
--- the square, the bare countdown and the tint carry no spell art -- several side by side would say only
--- that *some* number of things are up, where a pooled feature is about which cooldown landed.
---
--- The tint is the strongest case: two pooled cooldowns tinting the same bar would stack two colours
--- with nothing able to arbitrate, since neither display knows the other is showing.
---@param feature SpotlightsAuraFeature
---@param display SpotlightsAuraKind
---@return boolean
local function DrawsDisplay(feature, display)
	return not feature.multiple or display.key == "icon"
end

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

--- Everything a settings change gets for free: position, size, fade and on/off, all written to the
--- **anchor** -- a plain frame of ours above the aura button's access restriction, and therefore the
--- only part of a display that can still be told anything after it is built.
---
--- `point` is validated like a saved grid position: `SetPoint` errors on one it does not recognise, and
--- this runs inside a roster pass where that would take every later spotlight with it. The size floor
--- guards a damaged database, not user input -- `SetSize(0, 0)` means "take your size from your
--- anchors", which with a single anchor point is undefined rather than empty.
---
--- `featureEnabled` is the feature's own switch, which the display's cannot override. Hiding the anchor
--- takes the container under it down too, and a hidden container drops its `UNIT_AURA` registration in
--- `OnHide` -- so a switched-off feature stops being *told* about auras, not just drawing them.
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
--- **Every irreversible decision in this addon is made here.** The button the container hands back is
--- access-restricted the instant `initializeFrame` returns and the restriction reaches every
--- descendant, so texture, colour, inline icon and swipe are settled for the frame's lifetime. A slot
--- cannot be removed and its key cannot be reused, so a changed setting means another container.
---
--- The container is pinned by **opposing corners**, which is load-bearing: a container holding only
--- slots contributes nothing to its own flow layout, whose pass ends in
--- `CustomAuraContainerFlowLayoutMixin` calling `container:SetSize(1, 1)`. Two opposed anchors leave
--- neither axis for that to decide, which makes the anchor's rect the display's.
---
--- Called with an anchor already at its final size, so `initializeFrame` can read a height that means
--- something -- the bar's inline icon needs one to be square.
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

	-- `SetUnit` asserts on a non-string, and a spotlight keeps its displays after the header releases
	-- it, so a rebuild can hit a frame holding nobody. `OnUnitChanged` points it at the next one.
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

		-- Clicks already pass through (`ForbiddenAspect.AlwaysPropagateInput` on the AuraButton
		-- intrinsic). Motion is ours, and must be off or the aura tooltip replaces the unit tooltip on
		-- every hover.
		button:SetMouseMotionEnabled(false)

		-- Styling has to precede registration: it sets `Shown` on the optional regions, and
		-- `SetDurationCooldown` makes that aspect secret the moment it returns. `everything` is false,
		-- so only the regions this config asks for exist -- an unwanted one could never be reclaimed.
		local regions = display.Create(button, config, spellID or feature.spellID, false, child)

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
--- Recorded because it is a fact about a moment that cannot be recovered: `Fetch` falls back to a
--- default for an unregistered key and to the user's real choice for a registered one, and once the
--- button exists the texture reads back secret. This makes a late registration cheap -- only displays
--- that actually fell back need a new button, where matching the *stored* key would rebuild ones that
--- already had it right.
---
--- The nil checks below are the honest test: "this display has no font" and "this display's font is
--- unregistered" are the same answer here.
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
--- **A privacy gate, not a cosmetic one.** Blizzard deliberately skips identity candidate filters for
--- non-assistable units, so a container left visible on one would parse and display helpful auras these
--- displays exist to hide. Every path that puts a container on screen passes through here.
---
--- Not folded into `ApplyAnchor`: user enablement belongs to the anchor, assistability to the
--- container's lifetime, and a rebuild replaces the container while keeping the anchor.
---@param container SpotlightsAuraContainer
---@param child SpotlightsUnitFrame
local function ApplyAssistability(container, child)
	local unit = child.unit

	container:SetShown(unit ~= nil and UnitCanAssist("player", unit))
end

--- Replaces a display's container and button with a fresh pair styled from the current settings.
---
--- **The only way a frozen setting reaches a live spotlight.** A slot key is scoped to its container, so
--- a second container inside the same anchor may register the same key with different styling;
--- `CustomAuraContainerTemplate` is declared `allowUntaintedCreation="true"`, so building one from our
--- code is sanctioned. The old container is hidden, which drops its `UNIT_AURA` registration in its own
--- `OnHide`.
---
--- Inside the existing **anchor**, not beside it: the anchor is the display's identity everywhere else
--- in this file. It leaks by construction -- WoW cannot destroy a frame, so the old container and its
--- button stay for the session, which is the debt the reload prompt exists to reclaim.
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

	-- `Apply` settled assistability on the container being *replaced*, so without this the fresh one
	-- stays visible on a non-assistable unit until some later sweep.
	ApplyAssistability(container, child)

	-- Recomputed, not carried over: the usual reason to be here is that the fallen-back key has just
	-- been registered, and a stale set would rebuild again on that key's next registration.
	record.unresolved = UnresolvedMedia(config)

	reloadPending = true
end

--- Runs `callback` over the displays a spotlight has actually **built** -- a display that is switched
--- off has no frames. Both keys are handed back because a record alone does not say which display it is.
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

--- `gap` is the group's flow-layout spacing rather than a property of the protected aura button, so the
--- container setter marks layout dirty and the next aura pass applies it -- no rebuild.
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

--- The iterator only; what "in line" means lives in `ApplyAssistability`, which a rebuild calls for a
--- single replacement container with no record to iterate over yet.
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
--- **Called on first unit assignment, never at build time, and never for a display that is off**, so a
--- forty-slot grid with five players carries five spotlights' worth of aura frames rather than forty. A
--- feature switched off is skipped whole and costs nothing until it is switched back on, at which point
--- this runs again and builds what it skipped.
---
--- Deferred rather than guarded, because `initializeFrame` anchors and sizes frames descended from a
--- protected unit button -- protected calls that combat-block.
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

--- Re-applies the free half of every setting to one spotlight's existing displays. Called from
--- `SlotHeader.ApplyChildConfig` on a resize as well as from the sweep below, because a bar is stored
--- as a fraction of a spotlight it does not otherwise hear about.
---
--- Not combat-guarded, and that is the point of the anchor arrangement: every write here lands on a
--- frame of ours rather than on the protected unit button it hangs from, so a display can be moved,
--- resized, faded or hidden mid-combat. Building a *new* one cannot be, which `EnsureDisplays` defers.
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

		-- After the anchor has moved, since the question is whether the *new* rect broke something the
		-- button was built against. Queued rather than done here: a resize drag would otherwise rebuild
		-- every assigned display on every frame.
		if display.Invalidated and display.Invalidated(config, record) then
			RequestRebuild(feature.key, display.key)
		end
	end)
end

--- Builds one fake display of every kind, for one preview cell.
---
--- **The two things the preview layer is not allowed to reinvent**: the same `Create` the live path
--- uses, and an anchor `StylePreviews` positions with the same `ApplyAnchor`.
---
--- Every kind is built regardless of `enabled`, and `everything` is true, so a toggle is a `SetShown` on
--- something that already exists. Live displays cannot afford that; a preview is bounded by the visible
--- grid and thrown away by a reload.
---
--- A pooled feature gets `MAX_PREVIEW_AURAS` items **whatever its pool currently holds**, with which
--- spell each shows left to `StylePreviews`. Sizing the set to the pool is what made a preview go stale
--- -- a spell switched on afterwards had no item to appear in.
---@param parent Frame|SpotlightsUnitFrame a real spotlight in the panel's panes, a stand-in in the grid
---@param featureKey SpotlightsAuraFeatureKey? defaults to the previewed category
---@param displayKey SpotlightsAuraDisplayKey? every kind the category draws, when omitted
---@return SpotlightsAuraPreview[]
function Private.Auras.CreatePreviews(parent, featureKey, displayKey)
	local auras = Config()

	if not auras then
		return {}
	end

	featureKey = featureKey or previewFeatureKey

	-- `healthBar` is the whole of what the tint needs, so its presence is the honest test for whether
	-- the host is a real spotlight: the panel's panes use a mini one, the grid's cells a stand-in.
	local frame = parent.healthBar and parent --[[@as SpotlightsUnitFrame]] or nil

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
							regions = display.Create(anchor, auras[feature.key][display.key], feature.spellID, true,
								frame),
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

--- Re-applies every setting to a cell's previews, including the ones a live display cannot hear:
--- nothing here is registered or access-restricted, so the *frozen* half applies as freely as the free
--- half and a colour picker drags smoothly while the real displays wait out their debounce.
---
--- **A pooled feature's spell identities are decided here rather than at creation**, from the candidate
--- set as it stands at this call: item `n` is about the `n`th enabled spell, and an item the pool no
--- longer reaches is hidden. That is what carries a Tracked-pane toggle into the preview immediately.
---
--- Items after the first are chained rather than centred around the configured point, because that is
--- what the live container does -- `CustomAuraContainerLayoutDefaults` starts a group at the container's
--- top-left and grows right. Centring put a two-icon preview half a display left of the real ones.
---@param previews SpotlightsAuraPreview[]
function Private.Auras.StylePreviews(previews)
	local auras = Config()

	if not auras then
		return
	end

	local size = Private.FrameConfig.Get()

	-- Both per call: the candidate set is walked once however many items read from it, and `previous`
	-- carries the item the next one hangs off. A pooled feature draws one kind of display, so the
	-- feature key alone identifies a chain.
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
				-- about; an empty one hides them all, which is the honest preview of a category
				-- tracking nothing.
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

--- Every spotlight brought in line with the current settings, and the drain target for
--- `DeferralKey.Auras`.
---
--- A sweep rather than a queue of pending frames: `EnsureDisplays` early-outs on a table lookup, and a
--- list of frames waiting for combat to end is one more thing that can disagree with reality after a
--- roster change.
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

--- Set by the prompt's second button, and cleared by nothing: a reload or a relog is the whole of its
--- lifetime, which is what the button says.
local sensePowerIgnored = false

--- How long after a loading screen to look. Action bar contents and specialisation both arrive some
--- frames after the screen lifts and neither has an event meaning "and now they are correct", so a
--- shorter guess prompts against a bar the client has not filled in yet.
local TOGGLE_CHECK_DELAY = 3

--- The icon currently drawn for Sense Power on an action bar, or nil if it is not on one.
---
--- `FindSpellActionButtons` wants the **base** spell, which 361021 is, and answers with every slot
--- holding it. Returning nothing is a case the caller has to distinguish from "on a bar and switched
--- off".
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
	-- Built at show time rather than at load, so the localisation table is filled by now.
	StaticPopupDialogs[SENSE_POWER_POPUP] = {
		text = text,
		button1 = OKAY,
		button2 = Private.L.Auras.SensePowerIgnore,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		-- The legacy click path sends button 2 to `OnCancel` and never looks at `OnButton2`, which needs
		-- `selectCallbackByIndex` no other prompt in the addon sets.
		OnCancel = function()
			sensePowerIgnored = true
		end,
		preferredIndex = 3,
	}

	StaticPopup_Show(SENSE_POWER_POPUP)
end

--- Tells an Augmentation Evoker when their cooldown displays cannot possibly work.
---
--- **The toggle has no state API.** It is not a shapeshift form, `GetPlayerAuraBySpellID` finds nothing
--- under the cast's own ID, and `IsCurrentAction` reads false either way -- all three measured. What
--- *does* change is the icon the action bar draws.
---
--- Compared against `C_Spell.GetSpellTexture` rather than the active icon's file ID, because the
--- mechanism being tested is that the two *differ*: hardcoding the active one would make an art change
--- read as "permanently switched off".
local function CheckSensePower()
	-- Ahead of every other gate, and here rather than in `PromptSensePower`, so a check already scheduled
	-- by `C_Timer.After` when the button was clicked finds the flag set and does no action bar scan.
	if sensePowerIgnored then
		return
	end

	-- Group-gated at the one point every path passes through: the specialisation-change event and the
	-- display toggle in `SetSetting` reach here directly, so a respec or switch-on outside a group would
	-- prompt about displays that have no spotlight to draw on.
	--
	-- A group rather than a raid, because that is where the headers render.
	if not IsInGroup() then
		return
	end

	-- Narrower than the class gate the displays use: telling a Devastation Evoker to switch on a spell
	-- they do not own would be worse than saying nothing.
	if not Private.Utils.IsAugmentation() then
		return
	end

	local auras = Config()
	local sensePower = auras and auras[SENSE_POWER_KEY]

	-- A user who switched the feature off, or every one of its displays, has already answered the
	-- question this prompt asks.
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

--- The check, after a delay, which is what every *automatic* trigger uses: the things that trigger this
--- rewrite an action bar and none has a follow-up event meaning "and now the bars are correct".
---
--- Switching a display on is the exception and stays immediate -- the user has just acted, and a prompt
--- three seconds after a click reads as unrelated to it.
local function ScheduleSensePowerCheck()
	C_Timer.After(TOGGLE_CHECK_DELAY, CheckSensePower)
end

--- Whether the player was in a group the last time the roster changed, which is what makes
--- `GROUP_ROSTER_UPDATE` usable here: only the *edge* into a group is worth acting on, and without the
--- previous value there is no edge.
local wasInGroup = false

-- Arriving somewhere, but only into a group.
Private.Events.RegisterEvent("LOADING_SCREEN_DISABLED", ScheduleSensePowerCheck)

-- Joining a group, which the loading-screen trigger cannot see: no screen is involved. This also covers
-- logging straight into one, where `IsInGroup` is still false when the screen lifts because group
-- information has not arrived yet.
--
-- A party becoming a raid is deliberately *not* an edge: the player was already in a group.
Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	local inGroup = IsInGroup()
	local entered = inGroup and not wasInGroup

	wasInGroup = inGroup

	if entered then
		ScheduleSensePowerCheck()
	end
end)

-- Changing specialisation, the moment a player *becomes* the one this matters to. The group gate still
-- applies, enforced inside `CheckSensePower`.
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
--- than decided: the display kind classifies its own fields and this asks, so nothing here needs
--- revisiting when a display grows a field.
---
--- The nil test is a validity check -- every field has a non-nil default the migration's repair
--- guarantees, so a nil reading back means the caller named a field that does not exist.
---
--- A write of the value already stored does nothing, and for a frozen field that is the difference
--- between a leak and none: re-picking the current texture from a dropdown would otherwise cost a
--- container per assigned spotlight. A caller meaning "rebuild regardless" wants `RequestRebuild`.
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

	-- The fallback is about a caller inventing a key: rebuilding a display that does not exist finds and
	-- leaks nothing, where treating it as live would promise an update no frame ever gets.
	local invalidation = feature and display and display.Invalidation(feature, field) or "rebuild"

	if invalidation == "rebuild" then
		RequestRebuild(featureKey, displayKey)
	else
		Private.Events.Request(DeferralKey.Auras)
	end

	-- Switching a Sense Power display on is the moment to find out Sense Power itself is off; the toggle
	-- gates the aura, not the shape it is drawn in. Only ever a false-to-true transition, which falls
	-- out of the unchanged-value early-out above.
	if featureKey == SENSE_POWER_KEY and field == "enabled" and value then
		CheckSensePower()
	end

	return true
end

--- Answers `false` before the database has loaded rather than assuming the default: every caller either
--- draws a switch, which the migration corrects a moment later, or decides whether to build frames,
--- which must not happen against a database that is not there yet.
---@param featureKey SpotlightsAuraFeatureKey
---@return boolean
function Private.Auras.IsFeatureEnabled(featureKey)
	local auras = Config()
	local feature = auras and auras[featureKey]

	return feature ~= nil and feature.enabled == true
end

--- Switches a whole feature on or off, and lands it on every live display and preview.
---
--- Not routed through `SetSetting`: this sits a level above the bar and the icon and has no frozen half
--- -- off is a `SetShown` on anchors that already exist, on is a build `EnsureDisplays` was going to do
--- anyway. So nothing here abandons a frame, and **nothing here arms the reload prompt**, which is what
--- makes the dot on the category strip free to click.
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

	-- The free path: `Apply` builds what the switch made buildable and re-anchors the rest.
	Private.Events.Request(DeferralKey.Auras)

	-- Switching Sense Power on is the moment to find out the ability itself is off, for a display's own
	-- switch's reason (see `SetSetting`).
	if featureKey == SENSE_POWER_KEY and enabled then
		CheckSensePower()
	end

	return true
end

--- Restores one display to fresh-install values, leaving the shared spell pool alone and the feature's
--- own switch where the user put it -- silently switching a category back on would undo a decision the
--- button does not mention.
---
--- Written through `SetSetting` field by field rather than swapping the block, so a reset takes the same
--- free/frozen routing every other write does and the reload prompt arms as a manual edit would.
--- Assigning the table directly would strand the live display pointing at the old config.
---
--- `Private.Migration.DefaultAuraFeature` hands back a freshly built set every call, so nothing read
--- here is aliased to the database being written.
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
--- `includeSpellIDs` is handed over at build time, but the container also exposes candidate-filter
--- setters, which replace a live display's filters and re-run `UpdateAllAuras` themselves.
--- `CustomAuraContainerInboundMixin` is assembled from `CustomAuraContainerSharedMixin`, so it is ours
--- to call, and it `securecopy`s and validates what it is given. Nothing here arms the reload prompt.
---
--- Not combat-guarded, on the same grounds as `SetUnit` in `OnUnitChanged`: this marks a container
--- dirty and refreshes it, and creates nothing. Only *creation* is a protected call.
---
--- Prescience is skipped rather than harmlessly refreshed: `SetCandidateFilters` clears a slot's
--- candidates on the way through, so refreshing a one-spell set would drop an assigned aura and
--- re-acquire it on the next `UNIT_AURA` for nothing.
---
--- See docs/notes/AuraRebuildVsFilters.md for the rejected `RequestRebuild` path.
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

	-- A restyle rather than a rebuild: the preview items already exist and only their spell identities
	-- moved.
	Private.AuraPreview.Restyle()
end

--- Rebuilds the displays a newly registered medium actually fixes, and no others. Called by
--- `Private.Media`'s LibSharedMedia callback, which fires once per key in bulk during login.
---
--- **The filter is `record.unresolved`, not the stored setting.** Only displays built *before* the
--- registration are wearing a fallback because of it; one built afterwards resolved it correctly, and
--- rebuilding it abandons a container and arms a reload prompt for nothing the user can see. That was
--- the bug -- a spotlight assigned early enough offered a reload every login.
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

--- The tracked feature keys. **Exists because `pairs` over `Private.DB.auras` is no longer a list of
--- features**: that block gained the pools' own tables beside them, so anything walking it whole finds
--- a table with no `bar` and no `icon` and indexes nil, which is how `Media.lua` broke.
---@return string[]
function Private.Auras.FeatureKeys()
	local keys = {}

	for i = 1, #FEATURES do
		keys[i] = FEATURES[i].key
	end

	return keys
end

--- Whether a feature pools several of the spotlighted player's auras into one display. The only thing
--- that makes the gap between icons mean anything: one aura has nothing to space it against.
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

--- The shipped spell lists, handed out rather than copied because the panel only reads them, and
--- grouped by class -- the one thing the flat candidate set throws away and the panel needs back.
---
--- Everything below is a wrapper over one pool operation, so the options panel names a pool rather than
--- knowing which saved table and default rule it wants.
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

--- Whether the user should be offered a reload, because frames have been abandoned or are about to be.
--- Everything on the free path leaves this false.
---
--- Two questions, because one does not cover it: `reloadPending` answers for rebuilds that have
--- happened, `pending` for the one still inside the debounce window -- without which changing a colour
--- and closing within `REBUILD_DELAY` would never prompt.
---
--- The cost is one false positive: a frozen setting changed on a *disabled* display and closed within
--- the same window prompts for a rebuild that will find nothing.
---@return boolean
function Private.Auras.NeedsReload()
	return reloadPending or next(pending) ~= nil
end

--- Records that the user has been asked and answered. Called for **both** answers, so the code path
--- does not depend on the reload happening -- one refused by a loading screen or a blocking addon would
--- otherwise leave the prompt armed forever.
function Private.Auras.AcknowledgeReload()
	reloadPending = false
end

--- Points a spotlight's containers at its unit, and builds them the first time.
---@param frame SpotlightsUnitFrame
---@param unit string?
function Private.Auras.OnUnitChanged(frame, unit)
	-- A released unit needs nothing done: each container's own `OnHide` drops its `UNIT_AURA`
	-- registration and clears its auras. `SetUnit` asserts on a non-string anyway.
	if unit == nil then
		return
	end

	-- Before the creation attempt and outside its combat guard: `SetUnit` registers events and marks
	-- the container dirty, neither a protected call, so a roster change landing mid-combat still
	-- repoints existing displays. Only *creation* has to wait.
	ForEachDisplay(frame, function(record)
		record.container:SetUnit(unit)
	end)

	EnsureDisplays(frame)
	Private.Auras.UpdateAssistability(frame)
end
