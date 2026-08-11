---@type string, Spotlights
local _, Private = ...

---@class SpotlightsProfile
Private.Profile = {}

--- The export/import codec, lifted out of `Settings.lua` unchanged. Both the old panel's
--- `StaticPopup`s and the new Import/Export tab drive it from here, so neither has to reach into the
--- other's file to find it -- and the old panel keeps working once `Settings.lua` is deleted, at the
--- point where only this file remains.

local EXPORT_PREFIX = "SPOTLIGHTS!"

---@return table
local function CopyExportData()
	local db = Private.DB
	local payload = {}

	if not db then
		return payload
	end

	for key, value in pairs(db) do
		if key ~= "position" and key ~= "slots" then
			payload[key] = value
		end
	end

	return payload
end

---@return string
function Private.Profile.ExportString()
	return EXPORT_PREFIX ..
		C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(CopyExportData())))
end

--- Applies an export string. Roster and position are read from the *current* database rather than the
--- imported one -- deliberately: this codec's job is appearance and aura settings, and a slot list or a
--- frame position dragged into place is not something an import should be able to overwrite.
---@param text string
---@return boolean, string?
function Private.Profile.ImportString(text)
	if string.sub(text, 1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return false, "prefix"
	end

	local encoded = string.sub(text, #EXPORT_PREFIX + 1)
	local ok, payload = pcall(function()
		return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(encoded)))
	end)

	if not ok then
		return false, "decode"
	end

	if type(payload) ~= "table" then
		return false, "payload"
	end

	local current = Private.DB
	payload.slots = current and current.slots or {}
	payload.position = current and current.position or nil

	local migrated = Private.Migration.Run(payload)
	Private.DB = migrated
	SpotlightsSaved = migrated

	return true
end
