---@type string, Spotlights
local _, Private = ...

---@class SpotlightsProfile
Private.Profile = {}

--- The export/import codec, in a file of its own because two tabs drive it: Import/Export carries a whole
--- profile and the Roster tab's presets carry a slot list.

--- The preset prefix *extends* the profile's, so the two cannot drift apart when one is edited. The price
--- is that a preset string passes the profile's prefix test too, so `ImportString` refuses one by hand --
--- applying either kind as the other is silently destructive.
local EXPORT_PREFIX = "SPOTLIGHTS!"
local PRESET_PREFIX = EXPORT_PREFIX .. "PRESET!"

--- A sanity bound rather than a product limit -- the grid has no cap of its own -- so a hand-made string
--- cannot ask the panel to build an arbitrarily long list.
local MAX_PRESET_SLOTS = 200

--- The dialog caps what is typed and this caps what arrives in a string that never went through it, so the
--- two have to be the same number. 32 is what Blizzard's own layout naming allows.
Private.Profile.MAX_PRESET_NAME_LETTERS = 32

---@param prefix string
---@param payload table
---@return string
local function Encode(prefix, payload)
	return prefix ..
		C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(payload)))
end

--- The inverse, reporting *which* step refused: the wrong kind of string, a damaged one, and one that
--- decoded to something that was never ours are three different mistakes.
---@param prefix string
---@param text string
---@return table? payload, string? reason
local function Decode(prefix, text)
	if string.sub(text, 1, #prefix) ~= prefix then
		return nil, "prefix"
	end

	local encoded = string.sub(text, #prefix + 1)
	local ok, payload = pcall(function()
		return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(encoded)))
	end)

	if not ok then
		return nil, "decode"
	end

	if type(payload) ~= "table" then
		return nil, "payload"
	end

	return payload
end

--- The keys an export never carries, and what an import installs in their place.
---
--- One list read by both sides: `CopyExportData` skips these keys and `ImportString` overwrites them, so a
--- hand-made string that carries one cannot land it either. Functions rather than names, because what each
--- falls back to differs when there is no current database.
---@type table<string, fun(current: SpotlightsDB?): any>
local NOT_EXPORTED = {
	--- This account's own arrangements rather than settings.
	---
	--- WARNING: `slots` falls back to a table and not to nil. `Migration.Run` reads a missing slot list as
	--- data it cannot use and answers with a fresh database, which would turn an import into a wipe.
	slots = function(current)
		return current and current.slots or {}
	end,

	presets = function(current)
		return current and current.presets or {}
	end,

	--- GUIDs of people this account groups with, which mean nothing to whoever the string is sent to.
	favorites = function(current)
		return current and current.favorites or {}
	end,

	position = function(current)
		return current and current.position
	end,

	--- This install's chrome, and worse than merely pointless to import: LibDBIcon keeps the *table* it was
	--- registered with (`Init.lua`), so installing the payload's would leave the library writing to a table
	--- the database no longer holds until a reload -- and Reload Later is a button we offer.
	minimap = function(current)
		return current and current.minimap
	end,
}

---@return table
local function CopyExportData()
	local db = Private.DB
	local payload = {}

	if not db then
		return payload
	end

	for key, value in pairs(db) do
		if not NOT_EXPORTED[key] then
			payload[key] = value
		end
	end

	return payload
end

---@return string
function Private.Profile.ExportString()
	return Encode(EXPORT_PREFIX, CopyExportData())
end

--- Applies an export string. Everything in `NOT_EXPORTED` is taken from the *current* database: this
--- codec's job is appearance and aura settings, not a slot list or a position dragged into place.
---@param text string
---@return boolean, string?
function Private.Profile.ImportString(text)
	--- Refused up front, because a preset string starts with the profile's prefix too and `Decode` tests one
	--- prefix at a time. Reported as the wrong kind of string, not the damaged one `PRESET!` would decode to.
	if string.sub(text, 1, #PRESET_PREFIX) == PRESET_PREFIX then
		return false, "prefix"
	end

	local payload, reason = Decode(EXPORT_PREFIX, text)

	if not payload then
		return false, reason
	end

	--- Refused rather than migrated, with its own reason because it is the one refusal the user can act on.
	--- `Migration.Run` would take its from-the-future branch and install a payload still stamped with a
	--- version this build has no step for, so `for target = version + 1, CurrentVersion` would skip that
	--- step for the life of the account once a build carrying it arrives. That branch stays as it is: it is
	--- right about a *saved* database, and only wrong about a stranger's payload.
	if type(payload.version) == "number" and payload.version > Private.Migration.CurrentVersion then
		return false, "version"
	end

	-- Nil-guarded defensively only: `Private.DB` is assigned in `EventUtil.ContinueOnAddOnLoaded`
	-- (`Init.lua`), before any panel exists.
	local current = Private.DB

	for key, Local in pairs(NOT_EXPORTED) do
		payload[key] = Local(current)
	end

	local migrated = Private.Migration.Run(payload)
	Private.DB = migrated
	SpotlightsSaved = migrated

	return true
end

--- A preset as a string: the slot list and the name it was saved under, under its own prefix. The name is a
--- suggestion and not a key -- the library it lands in may already hold it, and the importer can rename.
---
--- Slot names and kinds only: the GUIDs a slot carries are one raid's answer to "who is this", and
--- `SetSlots` resolves the names against whatever raid the preset lands in.
---@param name string
---@param slots SpotlightsSlot[]
---@return string
function Private.Profile.ExportPresetString(name, slots)
	---@type SpotlightsPresetPayload
	local payload = { name = name, slots = {} }

	for i = 1, #slots do
		local slot = slots[i]

		payload.slots[i] = slot.kind == "player" and { kind = "player", name = slot.name } or { kind = "blank" }
	end

	return Encode(PRESET_PREFIX, payload)
end

--- Reads a preset string back, or says why it would not.
---
--- Validated element by element, because a pasted string is whatever the clipboard held. Anything that is
--- not a player with a name is stored as a spacer, which is what the grid does with such a slot anyway.
---
--- A bare slot array -- what this format encoded before it carried a name -- is refused. That format never
--- shipped, and reading it would mean a nameless branch through the naming dialog forever.
---@param text string
---@return SpotlightsPresetPayload? preset, string? reason
function Private.Profile.ImportPresetString(text)
	local payload, reason = Decode(PRESET_PREFIX, text)

	if not payload then
		return nil, reason
	end

	local name = type(payload.name) == "string" and strtrim(payload.name) or nil

	-- Counted in letters, not bytes, so the bound and the dialog's `maxLetters` mean the same thing in
	-- a language whose letters cost more than one byte.
	if
		not name
		or name == ""
		or strlenutf8(name) > Private.Profile.MAX_PRESET_NAME_LETTERS
		or type(payload.slots) ~= "table"
	then
		return nil, "payload"
	end

	--- An empty list is refused: in the dropdown it is indistinguishable from "clear the grid", and
	--- selecting a preset is the one action here with no confirmation in front of it.
	if #payload.slots == 0 or #payload.slots > MAX_PRESET_SLOTS then
		return nil, "payload"
	end

	---@type SpotlightsSlot[]
	local slots = {}

	for i = 1, #payload.slots do
		local slot = payload.slots[i]

		if type(slot) ~= "table" then
			return nil, "payload"
		end

		slots[i] = slot.kind == "player" and type(slot.name) == "string"
			and { kind = "player", name = slot.name }
			or { kind = "blank" }
	end

	return { name = name, slots = slots }
end
