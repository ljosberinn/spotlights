---@type string, Spotlights
local _, Private = ...

---@class SpotlightsAuraSpells
Private.AuraSpells = {}

--- The catalogue of trackable spells, grouped the way the panel lists them.
---
--- `Private.Auras` owns the shipped tables and every write to the stored overrides; the grouping it throws
--- away is rebuilt here rather than kept there for a reader that only exists while the panel is open.
---
--- **The one place that knows which pool a category draws from**: `FEATURE_POOLS` is the whole of that
--- rule, which lets the tracked pane ask the same questions of every category.

--- Keyed as a string where the built-in groups are keyed by class file, so the two cannot collide.
local CUSTOM_KEY = "CUSTOM"

--- One class's spells, or the user's own. A group *is* the heading entry a class row draws, which is why
--- the enable helpers below take one.
---@class SpotlightsAuraSpellGroup
---@field key string the class file, or `CUSTOM`
---@field heading string the class name, localised by the client
---@field spellIDs integer[] ascending, so a list built from them cannot reshuffle between sessions
---@field r number
---@field g number
---@field b number
---@field custom boolean? set on the user's own group, whose entries are off by default rather than on

--- One side of the tracked-spell split: the shipped table, the stored overrides over it, and the user's own
--- list beside it. A table rather than a branch per question, since six functions below differ only in
--- which set of `Private.Auras` accessors they reach for.
---
--- `groups` is filled on first use and kept, because the shipped tables cannot change while the game is
--- running. The *toggles* are read per call, never baked in here.
---@class SpotlightsAuraSpellPool
---@field spells table<integer, table<integer, boolean>> the shipped list, by class
---@field IsEnabled fun(spellID: integer, custom: boolean?): boolean
---@field SetEnabled fun(spellID: integer, enabled: boolean, custom: boolean?): boolean
---@field Custom fun(): integer[]
---@field AddCustom fun(spellID: integer): boolean
---@field RemoveCustom fun(spellID: integer): boolean
---@field Reset fun(): boolean
---@field groups SpotlightsAuraSpellGroup[]?

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
--- Sense Power fills its one slot from every enabled major cooldown, so it shares the cooldown pool --
--- `SensePowerCandidates` reads the same overrides. Prescience and Shifting Sands are absent on purpose:
--- one spell each, so a category with no entry here has no tracked list at all.
---@type table<SpotlightsAuraFeatureKey, SpotlightsAuraSpellPool>
local FEATURE_POOLS = {
	sensePower = POOLS.cooldowns,
	cooldownAuras = POOLS.cooldowns,
	defensiveAuras = POOLS.defensives,
}

--- The class groups, sorted by localised class name rather than left in `pairs` order, which could come out
--- differently between two sessions.
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

		-- Pruning the shipped list is expected, and an empty class would advertise a group with nothing in
		-- it.
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

--- The user's own spells as a group, rebuilt on every call: the one group whose contents change while the
--- panel is open. Uncoloured, because it is not a class.
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

--- Every group in a category, classes first and the user's own last. The custom group is listed even while
--- empty, alone among the groups, since it is where the first spell would be added.
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

--- Takes a spell the user typed in, and answers whether it was new. `false` covers both refusals -- no pool
--- to add to, and an ID already in the list -- which the panel treats alike.
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

--- Restores a category's tracked list to what it ships as.
---@param featureKey SpotlightsAuraFeatureKey
---@return boolean applied
function Private.AuraSpells.Reset(featureKey)
	local pool = FEATURE_POOLS[featureKey]

	return pool ~= nil and pool.Reset()
end

--- Whether a spell answers to what was typed in the search box. Matched against the ID as text as well as
--- the name, since a pasted number is as likely as a name -- and an uncached name is nil, which would
--- otherwise make a spell unfindable.
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

--- The spells in a group the query admits, which is what the pane beside the rail lists. A query naming the
--- *group* admits all of it, since no spell is called "Warrior" and an empty pane would read as a class
--- with nothing in it.
---
--- The group's own array is handed back where nothing is filtered, so **the result must not be mutated** --
--- it is the cached shipped list.
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

--- Switches a run of spells on or off, for the pane's bulk actions. Takes the IDs rather than the group, so
--- "Enable all" acts on what the filter left showing.
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

--- Whether a group is worth listing for what was typed: its own name, or any spell in it. Both, because a
--- query naming a spell would otherwise empty the rail it was typed into.
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
