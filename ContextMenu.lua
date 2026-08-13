---@type string, Spotlights
local _, Private = ...

---@class SpotlightsContextMenu
Private.ContextMenu = {}

--- "Spotlight this player" on the unit dropdown, added via `Menu.ModifyMenu` -- the sanctioned way
--- in, which lets addons insert elements without tainting surrounding element handlers
--- (`11_0_0_MenuImplementationGuide.lua`).
---
--- Not the `menu-function` attribute: that is invoked through `self:ExecuteAttribute` and runs with
--- the taint of whoever *stored* it, breaking every protected entry in its menu. This file adds a
--- menu entry; it does not supply a menu. Our entry does nothing protected (a table write plus a
--- deferred request), so the taint question is only about surrounding entries, which `ModifyMenu`
--- keeps clean.

--- The unit-popup types worth adding the entry to.
---
--- A tag is `MENU_UNIT_<which>` (`UnitPopupShared.lua:106`). `SecureTemplates.lua:300-307` picks
--- `RAID_PLAYER` for anyone in a raid, which our frames and Blizzard's raid frames produce; `RAID`
--- comes from roster-style lists; `SELF`, `PARTY`, `TARGET`, `FOCUS` cover the rest.
---
--- Deliberately not exhaustive: `BOSS`, `OTHERPET`, `FRIEND` and the rest cannot name a raid
--- member, and registering for them would run our filter on every menu in the game to reject it.
local MENU_TAGS = {
	"SELF",
	"PARTY",
	"RAID",
	"RAID_PLAYER",
	"TARGET",
	"FOCUS",
}

--- The GUID this menu is about, if it is someone we can actually spotlight.
---
--- Gated on our own roster map rather than `UnitInRaid`: the map (`Private.Roster.Rebuild`) guards
--- every entry with `issecretvalue`, so anything in it is a group member with a readable name, in a
--- party as much as in a raid -- whereas `UnitInRaid` returns a raid *index*, which
--- `CompactUnitFrame` treats as a secret hazard, and answers nothing at all in a party.
--- The entry then appears exactly when the assignment would succeed (`Registry.AssignByGuid`
--- applies the same `fromRoster` test).
---@param unit string?
---@return string? guid
local function ResolveGuid(unit)
	if not unit then
		return nil
	end

	local guid = UnitGUID(unit)

	-- Before any comparison, including against nil. A secret reaching `==` throws.
	if guid == nil or issecretvalue(guid) then
		return nil
	end

	local name, fromRoster = Private.Roster.GetName(guid)

	if not name or not fromRoster then
		return nil
	end

	return guid
end

--- Appends our section to one unit menu.
---@param rootDescription table
---@param contextData table?
local function Append(rootDescription, contextData)
	local guid = ResolveGuid(contextData and contextData.unit)

	if not guid then
		return
	end

	local L = Private.L.ContextMenu
	local slot = Private.Registry.SlotOf(guid)

	rootDescription:CreateDivider()
	rootDescription:CreateTitle(L.Title)

	if slot then
		rootDescription:CreateButton(L.Remove, function()
			Private.Registry.Unassign(slot)
		end)

		return
	end

	rootDescription:CreateButton(L.Add, function()
		-- Re-resolved rather than captured: the menu may have been open across a roster change, and
		-- assigning a GUID that has since left the raid would store a slot the header cannot match.
		local current = ResolveGuid(contextData and contextData.unit)

		if current then
			Private.Registry.AssignByGuid(current)
		end
	end)
end

for i = 1, #MENU_TAGS do
	Menu.ModifyMenu("MENU_UNIT_" .. MENU_TAGS[i], function(_, rootDescription, contextData)
		Append(rootDescription, contextData)
	end)
end
