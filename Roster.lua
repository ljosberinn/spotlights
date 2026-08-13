---@type string, Spotlights
local _, Private = ...

---@class SpotlightsRoster
Private.Roster = {}

--- guid -> the exact name `GetGroupRosterInfo` would have produced for that member; never a
--- reconstruction. SecureGroupHeaders indexes its tokenTable by that value
--- (SecureGroupHeaders.lua:293, :298-304, :479-486): bare name same-realm, Name-Realm cross-realm.
---@type table<string, string>
local nameByGuid = {}

---@type table<string, string>
local guidByName = {}

--- guid -> English class token, for display only. Allowed to be missing where the name maps are
--- not: the secure header matches on name, and a member whose class did not come back is still
--- assignable.
---@type table<string, string>
local classByGuid = {}

local scanned = 0
local skipped = 0

--- Records one member, or counts them as skipped.
---
--- Shared by both scans because the guarding is the whole substance of either: issecretvalue before
--- the nil checks, since comparing a secret is itself an error. Name and GUID are secret only when
--- unit identity is restricted, which means rated PvP -- for party members exactly as for raid ones.
--- Counting skips rather than erroring turns that into a reportable state -- see GetStats.
---@param name string?
---@param guid string?
---@param class string?
---@param secret boolean? identity restricted upstream, where the caller composed the name
local function Record(name, guid, class, secret)
	if secret or issecretvalue(name) or issecretvalue(guid) then
		skipped = skipped + 1

		return
	end

	if not name or not guid then
		return
	end

	nameByGuid[guid] = name
	guidByName[name] = guid

	-- Guarded separately: a secret class costs a colour, not a slot.
	if not issecretvalue(class) and class then
		classByGuid[guid] = class
	end

	scanned = scanned + 1
end

--- The name and class of one party member, composed the way `GetGroupRosterInfo` composes them for a
--- `PARTY` header (SecureGroupHeaders.lua:298-305) -- `UnitName`, suffixed with `-realm` only when
--- the realm is non-empty. Anything else and the header's nameList match finds nothing.
---
--- `player` is deliberately unreachable from here: the header walks index 0 only with `showPlayer`
--- set, and it is not, so offering the player as assignable would offer a name nothing can match.
---@param unit string
---@return string? name, string? class, boolean? secret
local function PartyMember(unit)
	local name, realm = UnitName(unit)

	-- The realm is *part of* the name here, unlike the class, so a secret realm makes the name
	-- unusable rather than merely uncoloured: storing the bare name would match a same-realm
	-- stranger. Reported rather than composed, so Record counts it as the skip it is.
	if issecretvalue(realm) then
		return nil, nil, true
	end

	if name and not issecretvalue(name) and realm and realm ~= "" then
		name = name .. "-" .. realm
	end

	-- Second return is the English class token; the first is localised and would key nothing.
	local _, class = UnitClass(unit)

	return name, class
end

--- Rescans the group. Plain table work, so legal in combat and cheap enough to run on every roster
--- event -- which lets a build blocked by combat run as one pass once combat ends.
---
--- The two branches mirror `GetGroupHeaderType` (SecureGroupHeaders.lua:261-287): a raid wins over a
--- party for the same group, and the party walk stops at `GetNumSubgroupMembers`, which excludes the
--- player. Solo scans nothing, because no header renders solo.
function Private.Roster.Rebuild()
	table.wipe(nameByGuid)
	table.wipe(guidByName)
	table.wipe(classByGuid)

	scanned = 0
	skipped = 0

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			-- Sixth return is `fileName`, the English class token -- not the fifth, which is the
			-- localised class name and would key nothing.
			local name, _, _, _, _, class = GetRaidRosterInfo(i)

			Record(name, UnitGUID("raid" .. i), class)
		end

		return
	end

	if not IsInGroup() then
		return
	end

	for i = 1, GetNumSubgroupMembers() do
		local unit = "party" .. i

		-- Mirrors the existence check the secure side makes before reading a party unit
		-- (SecureGroupHeaders.lua:300). GetNumSubgroupMembers is not a promise every index resolves.
		if UnitExists(unit) then
			local name, class, secret = PartyMember(unit)

			Record(name, UnitGUID(unit), class, secret)
		end
	end
end

--- The name for a GUID, and whether it came from the group roster.
---
--- Only a roster-sourced name may be written back into a slot: GetPlayerInfoByGUID returns name and
--- realm separately, so rebuilding `Name-Realm` from them is a synthesis the header will not match.
--- The cache answer is for display and diagnostics only.
---@param guid string
---@return string? name, boolean fromRoster
function Private.Roster.GetName(guid)
	local name = nameByGuid[guid]

	if name then
		return name, true
	end

	-- The client name cache answers for players not in the group -- what a slot assigned to someone
	-- offline needs to describe itself. It carries no secret annotation.
	local _, _, _, _, _, cachedName, realm = GetPlayerInfoByGUID(guid)

	if not cachedName then
		return nil, false
	end

	if realm and realm ~= "" then
		return cachedName .. "-" .. realm, false
	end

	return cachedName, false
end

---@param name string
---@return string? guid
function Private.Roster.GetGuid(name)
	return guidByName[name]
end

--- The English class token for a GUID, or nil.
---
--- Roster first, then the client's name cache, which answers for someone not in the group -- so a
--- slot assigned to an absent player still carries their colour.
---
--- Unlike `GetName`, the two sources need not be distinguished: a class token is only read to pick
--- a colour, never written back, so a cached answer is as good as a scanned one.
---@param guid string
---@return string? class
function Private.Roster.GetClass(guid)
	local class = classByGuid[guid]

	if class then
		return class
	end

	-- Second return is `englishClass`; the first is localised and would key nothing.
	local _, englishClass = GetPlayerInfoByGUID(guid)

	return englishClass
end

--- The assigned role for a GUID, as `UnitGroupRolesAssigned` spells it, or nil.
---
--- Not cached beside the class, and could not be: the role comes off a *unit*, so it only exists for
--- someone currently in the group. A slot configured for an absent player has no role to show, which
--- is a state the options list draws rather than an answer worth reconstructing.
---
--- `NONE` is folded into nil. A member who has not picked a role and a member who is not there are
--- the same thing to a caller that draws an icon for one.
---
--- Secret-guarded even though a secret GUID never reaches the roster maps: this one may be handed a
--- GUID out of the database, and a slot's player could be in a rated match where unit identity is
--- restricted. Comparing a secret is itself an error, so the test comes before the comparison.
---@param guid string
---@return string? role
function Private.Roster.GetRole(guid)
	local token = UnitTokenFromGUID(guid)
	local role = token and UnitGroupRolesAssigned(token)

	if not role or issecretvalue(role) or role == "NONE" then
		return nil
	end

	return role
end

--- GUID -> unit token in O(1), so nothing here needs a name-scan loop.
---
--- Ours and clean, unlike a token read off a secure child's `unit` attribute: that one is tainted,
--- and GameTooltip:GetUnit() then returns a secret so third-party tooltip hooks bail.
---@param guid string
---@return string? token
function Private.Roster.GetToken(guid)
	return UnitTokenFromGUID(guid)
end

--- Resolves free-typed input to the exact name the header will match against.
---
--- Case-insensitive, and matches the bare name of a cross-realm member, so `/spotlights add bob`
--- finds `Bob-Silvermoon`. What gets stored is always the scan's own spelling.
---@param input string
---@return string? name, string? guid
function Private.Roster.Resolve(input)
	if input == "" then
		return nil
	end

	local wanted = string.lower(input)

	-- pairs is legal here because Rebuild drops every entry whose name or GUID was secret, so all
	-- these keys are plain strings. A table that may hold secret keys needs secureexecuterange.
	for name, guid in pairs(guidByName) do
		if string.lower(name) == wanted then
			return name, guid
		end
	end

	-- Second pass so an exact match wins: with both `Bob` and `Bob-Silvermoon` in the group,
	-- `/spotlights add bob` must mean the former.
	for name, guid in pairs(guidByName) do
		local bare = string.match(name, "^([^%-]+)")

		if bare and string.lower(bare) == wanted then
			return name, guid
		end
	end

	return nil
end

--- Every scanned group member as `{ guid, name }`, sorted by name.
---
--- A sorted copy rather than the live map: a hash-order list of thirty names reshuffles on every
--- rebuild and becomes unusable to click in.
---
--- No class, deliberately: `GetClass` answers for any GUID, so carrying it here too would be a
--- second path to the same value that goes stale differently.
---@return { guid: string, name: string }[]
function Private.Roster.List()
	local list = {}

	for guid, name in pairs(nameByGuid) do
		list[#list + 1] = { guid = guid, name = name }
	end

	table.sort(list, function(a, b)
		return a.name < b.name
	end)

	return list
end

Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", Private.Roster.Rebuild)

--- How many members the last scan could read, and how many it skipped because their identity
--- was secret. A nonzero skip count is the rated-PvP case.
---@return integer scanned, integer skipped
function Private.Roster.GetStats()
	return scanned, skipped
end
