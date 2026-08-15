---@type string, Spotlights
local _, Private = ...

---@class SpotlightsFavorites
Private.Favorites = {}

--- The players the grid rebuilds itself around in every group. The sweep that acts on this list lives in
--- `Private.Registry`, beside the other two; what this file owns is the list itself and the one way to
--- reach a favourite who is not in the group to be clicked on.

--- Shared with every other confirmation, as `Options/Roster.lua` does: the dialog is registered at call
--- time by whoever raised it, and a second key would stack a second identical prompt.
local CLEAR_POPUP = "SPOTLIGHTS_FAVORITES_CLEAR"

---@return SpotlightsFavoriteMap?
local function Map()
	return Private.DB and Private.DB.favorites
end

---@param guid string?
---@return boolean
function Private.Favorites.IsFavorite(guid)
	local favorites = Map()

	return (guid and favorites and favorites[guid]) ~= nil
end

--- Stars or unstars a player, and acts on the grid at once, so a star fills the grid already on screen
--- rather than waiting for the next roster event.
---
--- Takes any GUID, including one whose player is not in the group: that is the whole point of the list, and
--- the stored name is display-only. What lands in a slot is always the roster's own spelling, which the
--- sweep reads fresh.
---@param guid string
---@return boolean favorited
function Private.Favorites.Toggle(guid)
	local favorites = Map()

	if not favorites then
		return false
	end

	if favorites[guid] then
		favorites[guid] = nil
	else
		favorites[guid] = Private.Roster.GetName(guid) or UNKNOWN
	end

	-- The GUID is handed over so a re-star offers again: unstarring alone leaves the sweep's handled entry
	-- behind, and a favourite is only ever offered once per group.
	Private.Registry.EnforceFavorites(guid)

	return favorites[guid] ~= nil
end

--- Every favourite as `{ guid, name }`, sorted by name so a list of twenty does not reshuffle between calls.
---@return { guid: string, name: string }[]
function Private.Favorites.List()
	local favorites = Map()
	local list = {}

	if not favorites then
		return list
	end

	-- `pairs` is legal because every key here came from a roster scan or a context menu, both of which drop
	-- the secret ones before we ever see them.
	for guid, name in pairs(favorites) do
		list[#list + 1] = { guid = guid, name = name }
	end

	table.sort(list, function(a, b)
		return a.name < b.name
	end)

	return list
end

--- Empties the list. Removes no slot: unstarring never has, and a clear is unstarring in bulk.
---@return boolean cleared
function Private.Favorites.Clear()
	local favorites = Map()

	if not favorites or not next(favorites) then
		return false
	end

	table.wipe(favorites)

	return true
end

--- Asks first: the list is persistent state built one click at a time, and nothing else can rebuild it.
local function ConfirmClear()
	local L = Private.L.Favorites

	StaticPopupDialogs[CLEAR_POPUP] = {
		text = L.ClearPrompt,
		button1 = L.ClearConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Private.Favorites.Clear()
			Private.Options.Refresh()
		end,
	}

	StaticPopup_Show(CLEAR_POPUP)
end

--- The only way to reach a favourite who is not in the group: both Roster panes list group members, so a
--- favourite who is offline has no row to unstar.
Private.SlashCommands.Register("favorites", "Favorites", function(args)
	local L = Private.L.Favorites

	if string.lower(string.match(args, "^%s*(.-)%s*$")) == "clear" then
		ConfirmClear()

		return
	end

	local list = Private.Favorites.List()

	if #list == 0 then
		Private.Utils.Print(L.Empty)

		return
	end

	Private.Utils.Printf(L.ListHeader, #list)

	for i = 1, #list do
		local entry = list[i]
		local token = Private.Roster.GetToken(entry.guid)

		-- The absence wording is the slot listing's, which says the same thing about the same GUID.
		Private.Utils.Printf(L.ListEntry, entry.name, token or Private.L.Registry.Absent)
	end

	Private.Utils.Print(L.ClearHint)
end)
