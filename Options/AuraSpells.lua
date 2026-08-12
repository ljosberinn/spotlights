---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraSpells
Private.AuraSpells = {}

--- The catalogue of trackable spells, grouped the way the panel lists them.
---
--- `Private.Auras` owns the shipped tables and every write to the stored overrides; this file is the
--- reading of them a settings panel needs and the runtime does not. The candidate builders want one
--- flat set of spell IDs and do not care whose spells they are, while the panel lists them by class
--- with a count per class -- so the grouping the runtime throws away is rebuilt here rather than kept
--- in `Auras.lua` for a reader that only exists while the panel is open.
---
--- **The one place that knows which pool a category draws from.** Sense Power shares the cooldown pool
--- rather than having one of its own, Prescience and Shifting Sands have none at all, and that rule was
--- previously spelled out at each of the six call sites in `Settings.lua` that needed it. `FEATURE_POOLS`
--- is the whole of it now, and it is what lets both panels ask the same questions of a category without
--- either of them learning what a pool is.

--- The user's own spells, listed as a group of their own so the panel has somewhere to put them.
---
--- A string where the built-in groups are keyed by class file, which is what keeps the two from ever
--- colliding: no class is spelled like this.
local CUSTOM_KEY = "CUSTOM"

--- One class's spells, or the user's own.
---
--- `heading`, `r`, `g` and `b` are what the old panel's flat list draws for a class row, so a group *is*
--- the heading entry rather than something a heading is derived from -- which is also why the class
--- enable helpers below take a group: they are handed one by both panels.
---@class SpotlightsAuraSpellGroup
---@field key string the class file, or `CUSTOM`
---@field heading string the class name, localised by the client
---@field spellIDs integer[] ascending, so a list built from them cannot reshuffle between sessions
---@field r number
---@field g number
---@field b number
---@field custom boolean? set on the user's own group, whose entries are off by default rather than on

--- One side of the tracked-spell split: the shipped table, the stored overrides over it, and the user's
--- own list beside it.
---
--- A table rather than a branch per question. Six of the functions below differ only in which of two
--- sets of `Private.Auras` accessors they reach for, and written out each would restate the same
--- two-way choice six times -- which is exactly the shape `Settings.lua` had and the shape this file
--- exists to remove.
---
--- `groups` and `flat` are filled on first use and kept: the shipped tables cannot change while the
--- game is running. The *toggles* are read per call, never baked in here.
---@class SpotlightsAuraSpellPool
---@field spells table<integer, table<integer, boolean>> the shipped list, by class
---@field IsEnabled fun(spellID: integer, custom: boolean?): boolean
---@field SetEnabled fun(spellID: integer, enabled: boolean, custom: boolean?): boolean
---@field Custom fun(): integer[]
---@field AddCustom fun(spellID: integer): boolean
---@field RemoveCustom fun(spellID: integer): boolean
---@field Reset fun(): boolean
---@field groups SpotlightsAuraSpellGroup[]?
---@field flat table[]?

---@type table<string, SpotlightsAuraSpellPool>
local POOLS = {
	cooldowns = {
		spells = Private.Auras.Cooldowns(),
		IsEnabled = Private.Auras.IsCooldownEnabled,
		SetEnabled = Private.Auras.SetCooldownEnabled,
		Custom = Private.Auras.CustomCooldowns,
		AddCustom = Private.Auras.AddCustomCooldown,
		RemoveCustom = Private.Auras.RemoveCustomCooldown,
		Reset = Private.Auras.ResetCooldowns,
	},

	defensives = {
		spells = Private.Auras.Defensives(),
		IsEnabled = Private.Auras.IsDefensiveEnabled,
		SetEnabled = Private.Auras.SetDefensiveEnabled,
		Custom = Private.Auras.CustomDefensives,
		AddCustom = Private.Auras.AddCustomDefensive,
		RemoveCustom = Private.Auras.RemoveCustomDefensive,
		Reset = Private.Auras.ResetDefensives,
	},
}

--- Which pool each category's tracked list comes from.
---
--- Sense Power watches one slot but fills it from every enabled major cooldown, which is why it shares
--- the cooldown pool rather than having a list of its own -- `SensePowerCandidates` reads the same
--- overrides. Prescience and Shifting Sands are one spell each and are absent on purpose: there is
--- nothing for a user to choose, so a category with no entry here has no tracked list at all.
---@type table<SpotlightsAuraFeatureKey, SpotlightsAuraSpellPool>
local FEATURE_POOLS = {
	sensePower = POOLS.cooldowns,
	cooldownAuras = POOLS.cooldowns,
	defensiveAuras = POOLS.defensives,
}

--- The class groups, in the order the panel lists them.
---
--- Sorted by the localised class name rather than left in `pairs` order, which is what the old panel
--- used and is no order at all: the same list could come out differently between two sessions. A rail
--- the user searches by typing a class name is worth being able to scan alphabetically, and the flat
--- list built from these groups inherits the same order.
---@param pool SpotlightsAuraSpellPool
---@return SpotlightsAuraSpellGroup[]
local function BuiltinGroups(pool)
	if pool.groups then
		return pool.groups
	end

	---@type SpotlightsAuraSpellGroup[]
	local groups = {}

	for _, classID in pairs(Constants.UICharacterClasses) do
		local spells = pool.spells[classID]

		-- A class with nothing left in the shipped list gets no group. Pruning that list is expected,
		-- and an empty class would advertise a group with nothing in it.
		if spells then
			local info = C_CreatureInfo.GetClassInfo(classID)
			local color = info and RAID_CLASS_COLORS[info.classFile]
			local spellIDs = {}

			for spellID in pairs(spells) do
				spellIDs[#spellIDs + 1] = spellID
			end

			table.sort(spellIDs)

			groups[#groups + 1] = {
				key = info and info.classFile or tostring(classID),
				heading = info and info.className or tostring(classID),
				spellIDs = spellIDs,
				r = color and color.r or 1,
				g = color and color.g or 1,
				b = color and color.b or 1,
			}
		end
	end

	table.sort(groups, function(left, right)
		return left.heading < right.heading
	end)

	pool.groups = groups

	return groups
end

--- The user's own spells as a group, rebuilt on every call.
---
--- The one group that cannot be cached: its contents are whatever has been typed in, and it changes
--- while the panel is open. Uncoloured, because it is not a class and a colour would imply one.
---@param pool SpotlightsAuraSpellPool
---@return SpotlightsAuraSpellGroup
local function CustomGroup(pool)
	return {
		key = CUSTOM_KEY,
		heading = Private.L.Settings.AuraCustomCooldowns,
		spellIDs = pool.Custom(),
		r = 1,
		g = 1,
		b = 1,
		custom = true,
	}
end

--- Whether a category has a tracked spell list at all.
---@param featureKey SpotlightsAuraFeatureKey
---@return boolean
function Private.AuraSpells.HasSpells(featureKey)
	return FEATURE_POOLS[featureKey] ~= nil
end

--- Every group in a category, classes first and the user's own last.
---
--- The custom group is listed even while it is empty, alone among the groups. It is where a spell is
--- added, so hiding it until it has one would leave no way to add the first.
---@param featureKey SpotlightsAuraFeatureKey
---@return SpotlightsAuraSpellGroup[]
function Private.AuraSpells.Groups(featureKey)
	local pool = FEATURE_POOLS[featureKey]

	if not pool then
		return {}
	end

	local builtin = BuiltinGroups(pool)
	local groups = {}

	for i = 1, #builtin do
		groups[i] = builtin[i]
	end

	groups[#groups + 1] = CustomGroup(pool)

	return groups
end

--- One group by key, for a caller holding a selection rather than a group.
---@param featureKey SpotlightsAuraFeatureKey
---@param key string?
---@return SpotlightsAuraSpellGroup?
function Private.AuraSpells.Group(featureKey, key)
	if not key then
		return nil
	end

	local groups = Private.AuraSpells.Groups(featureKey)

	for i = 1, #groups do
		if groups[i].key == key then
			return groups[i]
		end
	end

	return nil
end

--- The old panel's rows: a class heading, then that class's spells, for every class that has any.
---
--- Built once and kept, since neither the shipped table nor the order it is listed in can change while
--- the game is running.
---@param featureKey SpotlightsAuraFeatureKey
---@return table[]
function Private.AuraSpells.Entries(featureKey)
	local pool = FEATURE_POOLS[featureKey]

	if not pool then
		return {}
	end

	if pool.flat then
		return pool.flat
	end

	local groups = BuiltinGroups(pool)
	local entries = {}

	for i = 1, #groups do
		local group = groups[i]

		entries[#entries + 1] = group

		for j = 1, #group.spellIDs do
			entries[#entries + 1] = { spellID = group.spellIDs[j] }
		end
	end

	pool.flat = entries

	return entries
end

--- The user's own rows, which are whatever they have added.
---@param featureKey SpotlightsAuraFeatureKey
---@return { spellID: integer }[]
function Private.AuraSpells.CustomEntries(featureKey)
	local pool = FEATURE_POOLS[featureKey]
	local entries = {}

	if not pool then
		return entries
	end

	local spellIDs = pool.Custom()

	for i = 1, #spellIDs do
		entries[i] = { spellID = spellIDs[i] }
	end

	return entries
end

---@param featureKey SpotlightsAuraFeatureKey
---@param spellID integer
---@param custom boolean? whether `spellID` is a user-added entry rather than a shipped one
---@return boolean
function Private.AuraSpells.IsEnabled(featureKey, spellID, custom)
	local pool = FEATURE_POOLS[featureKey]

	return pool ~= nil and pool.IsEnabled(spellID, custom)
end

---@param featureKey SpotlightsAuraFeatureKey
---@param spellID integer
---@param enabled boolean
---@param custom boolean?
---@return boolean applied
function Private.AuraSpells.SetEnabled(featureKey, spellID, enabled, custom)
	local pool = FEATURE_POOLS[featureKey]

	return pool ~= nil and pool.SetEnabled(spellID, enabled, custom)
end

--- Takes a spell the user typed in, and answers whether it was new.
---
--- `false` covers both refusals -- a category with no pool to add to, and an ID already in the list -- and
--- the panel treats them the same way: the number stays in the box, so it is still there to look at.
---@param featureKey SpotlightsAuraFeatureKey
---@param spellID integer
---@return boolean added
function Private.AuraSpells.AddCustom(featureKey, spellID)
	local pool = FEATURE_POOLS[featureKey]

	return pool ~= nil and pool.AddCustom(spellID)
end

---@param featureKey SpotlightsAuraFeatureKey
---@param spellID integer
---@return boolean removed
function Private.AuraSpells.RemoveCustom(featureKey, spellID)
	local pool = FEATURE_POOLS[featureKey]

	return pool ~= nil and pool.RemoveCustom(spellID)
end

--- How much of a group is switched on, for the count beside its name.
---@param featureKey SpotlightsAuraFeatureKey
---@param group SpotlightsAuraSpellGroup
---@return integer enabled, integer total
function Private.AuraSpells.Counts(featureKey, group)
	local pool = FEATURE_POOLS[featureKey]

	if not pool then
		return 0, 0
	end

	local enabled = 0

	for i = 1, #group.spellIDs do
		if pool.IsEnabled(group.spellIDs[i], group.custom) then
			enabled = enabled + 1
		end
	end

	return enabled, #group.spellIDs
end

--- Whether every spell in a group is on, which is what a group-level checkbox shows.
---
--- `nil` rather than `false` for a category with no pool, because the old panel's list draws the
--- checkbox only where this answers at all.
---@param featureKey SpotlightsAuraFeatureKey
---@param group SpotlightsAuraSpellGroup
---@return boolean?
function Private.AuraSpells.IsGroupEnabled(featureKey, group)
	local pool = FEATURE_POOLS[featureKey]

	if not pool then
		return nil
	end

	for i = 1, #group.spellIDs do
		if not pool.IsEnabled(group.spellIDs[i], group.custom) then
			return false
		end
	end

	return true
end

---@param featureKey SpotlightsAuraFeatureKey
---@param group SpotlightsAuraSpellGroup
---@param enabled boolean
function Private.AuraSpells.SetGroupEnabled(featureKey, group, enabled)
	local pool = FEATURE_POOLS[featureKey]

	if not pool then
		return
	end

	for i = 1, #group.spellIDs do
		pool.SetEnabled(group.spellIDs[i], enabled, group.custom)
	end
end

--- Restores a category's tracked list to what it ships as.
---@param featureKey SpotlightsAuraFeatureKey
---@return boolean applied
function Private.AuraSpells.Reset(featureKey)
	local pool = FEATURE_POOLS[featureKey]

	return pool ~= nil and pool.Reset()
end

--- Whether a spell answers to what was typed in the search box.
---
--- Matched against the ID as text as well as the name, because a spell is as likely to be looked up by
--- the number the user pasted in from somewhere as by what the client calls it -- and because a name
--- the client has not cached yet is nil, which would otherwise make a spell unfindable until something
--- else asked for it.
---@param spellID integer
---@param query string lowercased by the caller, which owns the box the text came from
---@return boolean
function Private.AuraSpells.SpellMatches(spellID, query)
	if string.find(tostring(spellID), query, 1, true) then
		return true
	end

	local name = C_Spell.GetSpellName(spellID)

	return name ~= nil and string.find(name:lower(), query, 1, true) ~= nil
end

--- The spells in a group the query admits, which is what the pane beside the rail lists.
---
--- A query naming the *group* admits all of it. The rail lists a class whose name was typed, and a pane
--- that then showed none of its spells -- no spell is called "Warrior" -- would read as a class with
--- nothing in it rather than as the class that was just asked for.
---
--- The group's own array is handed back where nothing is filtered, so **the result must not be mutated**:
--- it is the cached shipped list, and a caller reordering it would reorder every later pass with it.
---@param group SpotlightsAuraSpellGroup
---@param query string lowercased by the caller
---@return integer[]
function Private.AuraSpells.MatchingSpells(group, query)
	if query == "" or string.find(group.heading:lower(), query, 1, true) then
		return group.spellIDs
	end

	local matches = {}

	for i = 1, #group.spellIDs do
		if Private.AuraSpells.SpellMatches(group.spellIDs[i], query) then
			matches[#matches + 1] = group.spellIDs[i]
		end
	end

	return matches
end

--- Switches a run of spells on or off in one write each, for the pane's bulk actions.
---
--- Takes the IDs rather than the group, which is the whole point: "Enable all" acts on what the filter
--- left showing, so a bulk action does what the list in front of the user says it will.
---@param featureKey SpotlightsAuraFeatureKey
---@param spellIDs integer[]
---@param enabled boolean
---@param custom boolean?
function Private.AuraSpells.SetSpellsEnabled(featureKey, spellIDs, enabled, custom)
	local pool = FEATURE_POOLS[featureKey]

	if not pool then
		return
	end

	for i = 1, #spellIDs do
		pool.SetEnabled(spellIDs[i], enabled, custom)
	end
end

--- Whether a group is worth listing for what was typed: its own name, or any spell in it.
---
--- Both, because the rail is the only list on screen while the search is being typed and a query that
--- named a spell would otherwise empty it.
---@param group SpotlightsAuraSpellGroup
---@param query string
---@return boolean
function Private.AuraSpells.GroupMatches(group, query)
	if query == "" or string.find(group.heading:lower(), query, 1, true) then
		return true
	end

	for i = 1, #group.spellIDs do
		if Private.AuraSpells.SpellMatches(group.spellIDs[i], query) then
			return true
		end
	end

	return false
end
