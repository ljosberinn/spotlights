---@type string, Spotlights
local _, Private = ...

---@class SpotlightsProfile
Private.Profile = {}

--- The export/import codec, in a file of its own because two tabs drive it: Import/Export carries a
--- whole profile and the Roster tab's presets carry a slot list, and neither should have to reach into
--- the other's file to find the encoder they share.

--- The two kinds of string this codec produces. The preset prefix *extends* the profile's rather than
--- sitting beside it, so a preset string reads as a Spotlights string first and a preset second, and
--- the two cannot drift apart when one of them is edited.
---
--- The price of that nesting is that a preset string passes the profile's prefix test as well as its
--- own, so `ImportString` refuses one by hand before it decodes anything. Applying either kind as the
--- other would be silently destructive: a preset imported as a profile is a database with no settings
--- in it, and a profile imported as a preset is a preset of nothing.
local EXPORT_PREFIX = "SPOTLIGHTS!"
local PRESET_PREFIX = EXPORT_PREFIX .. "PRESET!"

--- The maximum number of slots a preset string may carry, which is a sanity bound rather than a
--- product limit: the grid has no cap of its own, and this exists so a hand-made string cannot ask
--- the panel to build an arbitrarily long list.
local MAX_PRESET_SLOTS = 200

--- The longest name a preset may carry. Kept here rather than beside the dialog that enforces it,
--- because the two have to be the same number: the dialog caps what is typed, and this caps what
--- arrives in a string that never went through the dialog. 32 is what Blizzard's own layout naming
--- allows.
Private.Profile.MAX_PRESET_NAME_LETTERS = 32

---@param prefix string
---@param payload table
---@return string
local function Encode(prefix, payload)
	return prefix ..
		C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(payload)))
end

--- The inverse, reporting *which* step refused rather than a bare failure: the three answers are
--- three different mistakes -- the wrong kind of string, a damaged one, and one that decoded to
--- something that was never ours.
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
--- One list read by both sides on purpose: `CopyExportData` skips these keys and `ImportString`
--- overwrites them, so a hand-made string that carries one cannot land it either. Kept as functions of
--- the current database rather than a set of names, because what they fall back to differs when there
--- is no current database to read.
---@type table<string, fun(current: SpotlightsDB?): any>
local NOT_EXPORTED = {
	--- This account's own arrangements rather than settings: a profile shared with a guild would carry
	--- someone else's raid compositions into every install that imported it.
	---
	--- WARNING: `slots` falls back to a table and not to nil. `Migration.Run` reads a missing slot list
	--- as data it cannot use and answers with a fresh database, which would turn an import into a wipe.
	slots = function(current)
		return current and current.slots or {}
	end,

	presets = function(current)
		return current and current.presets or {}
	end,

	position = function(current)
		return current and current.position
	end,

	--- This install's chrome rather than a setting worth sharing, which is the argument `presets` is
	--- left out on. Aliasing makes it worse than merely pointless: LibDBIcon keeps the *table* it was
	--- registered with (`Init.lua`), so installing the payload's would leave the library writing to a
	--- table the database no longer holds, and the imported `hide` unread because nothing re-registers.
	--- Until the reload -- and Reload Later is a button we offer.
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

--- Applies an export string. Everything in `NOT_EXPORTED` is taken from the *current* database rather
--- than the imported one -- deliberately: this codec's job is appearance and aura settings, and a slot
--- list or a frame position dragged into place is not something an import should be able to overwrite.
---@param text string
---@return boolean, string?
function Private.Profile.ImportString(text)
	--- Refused up front, because a preset string starts with the profile's prefix too: `Decode` tests
	--- one prefix at a time and cannot know the pair. Reported as the wrong kind of string rather than
	--- as a damaged one, which is what the leftover `PRESET!` would otherwise decode to.
	if string.sub(text, 1, #PRESET_PREFIX) == PRESET_PREFIX then
		return false, "prefix"
	end

	local payload, reason = Decode(EXPORT_PREFIX, text)

	if not payload then
		return false, reason
	end

	--- Refused rather than migrated, and this is the one refusal the user can do something about --
	--- hence its own reason, and a message telling them to update.
	---
	--- `Migration.Run` would take its from-the-future branch and hand the payload back *still* stamped
	--- with a version this build has no step for. Installing that makes `for target = version + 1,
	--- CurrentVersion` skip the missing step for the life of the account, once a build that has it
	--- arrives. The payload may also carry fields this build's `Repair` will not touch and its code will
	--- not understand, so there is nothing worth salvaging by importing it anyway.
	---
	--- The branch in `Run` stays as it is: it is right about a *saved* database, which is this user's own
	--- data and must not be downgraded. It is only wrong about a stranger's payload.
	if type(payload.version) == "number" and payload.version > Private.Migration.CurrentVersion then
		return false, "version"
	end

	-- Nil-guarded defensively only. `Private.DB` is assigned inside `EventUtil.ContinueOnAddOnLoaded`
	-- (`Init.lua`), before any panel exists and before a slash command can run, so there is no moment
	-- at which the Import button is clickable and this is nil.
	local current = Private.DB

	for key, Local in pairs(NOT_EXPORTED) do
		payload[key] = Local(current)
	end

	local migrated = Private.Migration.Run(payload)
	Private.DB = migrated
	SpotlightsSaved = migrated

	return true
end

--- A preset as a string: the slot list and the name it was saved under, under its own prefix.
---
--- The name travels so that the arrangement its author labelled arrives labelled. It is a suggestion
--- and not a key -- the library it lands in may already hold that name, and the importer is shown it
--- and can rename before anything is stored.
---
--- Slot names and kinds only. The GUIDs a slot carries are one raid's answer to "who is this", and a
--- string meant to be pasted into someone else's client has no business claiming them -- `SetSlots`
--- resolves the names against whatever raid the preset lands in.
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
--- Validated element by element rather than trusted, because this is the one input to the panel that
--- came from outside it: a pasted string is whatever the clipboard held. Anything that is not a
--- player with a name is stored as a spacer, which is what the grid does with such a slot anyway.
---
--- A payload that is a bare slot array -- what this format encoded before it carried a name -- is
--- refused as a payload the panel does not understand. That format never shipped, and reading it
--- would mean a nameless branch through the naming dialog for the rest of the addon's life.
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

	--- An empty list is refused rather than stored. A preset of nothing is indistinguishable from
	--- "clear the grid" once it is in the dropdown, and selecting one is the one action here that has
	--- no confirmation in front of it.
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
