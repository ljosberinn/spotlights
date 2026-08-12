---@type string, Spotlights
local _, Private = ...

---@class SpotlightsProfile
Private.Profile = {}

--- The export/import codec, lifted out of `Settings.lua` unchanged. Both the old panel's
--- `StaticPopup`s and the new Import/Export tab drive it from here, so neither has to reach into the
--- other's file to find it -- and the old panel keeps working once `Settings.lua` is deleted, at the
--- point where only this file remains.

--- The two kinds of string this codec produces, and why neither can be mistaken for the other: a
--- preset string does not start with the profile's prefix, and a profile string does not start with
--- the preset's. Both checks are a plain prefix test, so the pair only has to disagree on their
--- eleventh character -- which they do.
---
--- A profile carries settings and a preset carries a slot list, and applying either as the other
--- would be silently destructive: a preset imported as a profile is a database with no settings in
--- it, and a profile imported as a preset is a preset of nothing.
local EXPORT_PREFIX = "SPOTLIGHTS!"
local PRESET_PREFIX = "SPOTLIGHTSPRESET!"

--- The maximum number of slots a preset string may carry, which is a sanity bound rather than a
--- product limit: the grid has no cap of its own, and this exists so a hand-made string cannot ask
--- the panel to build an arbitrarily long list.
local MAX_PRESET_SLOTS = 200

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

---@return table
local function CopyExportData()
	local db = Private.DB
	local payload = {}

	if not db then
		return payload
	end

	--- Presets are left out for the same reason the slots and the position are: they are this
	--- account's own arrangements rather than settings, and a profile shared with a guild would carry
	--- someone else's raid compositions into every install that imported it.
	for key, value in pairs(db) do
		if key ~= "position" and key ~= "slots" and key ~= "presets" then
			payload[key] = value
		end
	end

	return payload
end

---@return string
function Private.Profile.ExportString()
	return Encode(EXPORT_PREFIX, CopyExportData())
end

--- Applies an export string. Roster and position are read from the *current* database rather than the
--- imported one -- deliberately: this codec's job is appearance and aura settings, and a slot list or a
--- frame position dragged into place is not something an import should be able to overwrite.
---@param text string
---@return boolean, string?
function Private.Profile.ImportString(text)
	local payload, reason = Decode(EXPORT_PREFIX, text)

	if not payload then
		return false, reason
	end

	local current = Private.DB
	payload.slots = current and current.slots or {}
	payload.position = current and current.position or nil

	-- Kept for the same reason the slots are: the preset library is this account's, and an import is
	-- about settings. Dropping it would delete a shelf of saved layouts the user never offered up.
	payload.presets = current and current.presets or {}

	local migrated = Private.Migration.Run(payload)
	Private.DB = migrated
	SpotlightsSaved = migrated

	return true
end

--- A preset as a string: the slot list alone, under its own prefix.
---
--- Names and kinds only. The GUIDs a slot carries are one raid's answer to "who is this", and a
--- string meant to be pasted into someone else's client has no business claiming them -- `SetSlots`
--- resolves the names against whatever raid the preset lands in.
---@param slots SpotlightsSlot[]
---@return string
function Private.Profile.ExportPresetString(slots)
	local payload = {}

	for i = 1, #slots do
		local slot = slots[i]

		payload[i] = slot.kind == "player" and { kind = "player", name = slot.name } or { kind = "blank" }
	end

	return Encode(PRESET_PREFIX, payload)
end

--- Reads a preset string back, or says why it would not.
---
--- Validated element by element rather than trusted, because this is the one input to the panel that
--- came from outside it: a pasted string is whatever the clipboard held. Anything that is not a
--- player with a name is stored as a spacer, which is what the grid does with such a slot anyway.
---@param text string
---@return SpotlightsSlot[]? slots, string? reason
function Private.Profile.ImportPresetString(text)
	local payload, reason = Decode(PRESET_PREFIX, text)

	if not payload then
		return nil, reason
	end

	--- An empty list is refused rather than stored. A preset of nothing is indistinguishable from
	--- "clear the grid" once it is in the dropdown, and selecting one is the one action here that has
	--- no confirmation in front of it.
	if #payload == 0 or #payload > MAX_PRESET_SLOTS then
		return nil, "payload"
	end

	---@type SpotlightsSlot[]
	local slots = {}

	for i = 1, #payload do
		local slot = payload[i]

		if type(slot) ~= "table" then
			return nil, "payload"
		end

		slots[i] = slot.kind == "player" and type(slot.name) == "string"
			and { kind = "player", name = slot.name }
			or { kind = "blank" }
	end

	return slots
end
