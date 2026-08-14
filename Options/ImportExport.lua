---@type string, Spotlights
local _, Private = ...

--- The Import/Export tab: two in-place boxes rather than the pair of `StaticPopup`s a button opens. The
--- codec itself lives in `Options/Profile.lua`, which the Roster tab's presets share.

--- Re-judged against the 610px window rather than scaled with it: two boxes, two headings, two buttons
--- and the gaps between them still leave room over at 160, and a box a profile string does not fill is
--- an empty tab rather than a generous one.
local EXPORT_HEIGHT = 160
local IMPORT_HEIGHT = 160

--- What the user pasted, since it is not a setting -- there is nothing in the database to read it back
--- from between a paste and the Import click, and nothing to forget it once the tab is left and
--- returned to.
local pending = ""

--- One key per prompt across the whole panel, the same rule `Panel.lua`'s `AURA_RELOAD_POPUP` follows:
--- `StaticPopup_Show` reuses the dialog already on screen for a given key, so a second key would stack
--- two identical dialogs.
local IMPORT_ERROR_POPUP = "SPOTLIGHTS_IMPORT_ERROR"
local IMPORT_RELOAD_POPUP = "SPOTLIGHTS_IMPORT_RELOAD"

---@param reason string?
local function ShowImportError(reason)
	local L = Private.L.Settings
	local details = reason == "prefix" and L.ImportErrorPrefix
		or reason == "decode" and L.ImportErrorDecode
		or reason == "version" and L.ImportErrorVersion
		or L.ImportErrorPayload

	StaticPopupDialogs[IMPORT_ERROR_POPUP] = {
		text = string.format(L.ImportError, details),
		button1 = ACCEPT,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show(IMPORT_ERROR_POPUP)
end

---@param importBox SpotlightsTextAreaNode
local function DoImport(importBox)
	local success, reason = Private.Profile.ImportString(strtrim(pending))

	if not success then
		ShowImportError(reason)

		return
	end

	pending = ""
	importBox:SetText("")

	local L = Private.L.Settings

	StaticPopupDialogs[IMPORT_RELOAD_POPUP] = {
		text = L.ImportReloadPrompt,
		button1 = L.ReloadNow,
		button2 = L.ReloadLater,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		OnAccept = ReloadUI,
	}
	StaticPopup_Show(IMPORT_RELOAD_POPUP)
end

---@param page Frame
---@return SpotlightsNode
local function BuildImportExport(page)
	local L = Private.L.Settings

	---@type SpotlightsTextAreaNode
	local exportBox

	---@type SpotlightsTextAreaNode
	local importBox

	exportBox = Private.Controls.TextArea(page, EXPORT_HEIGHT, Private.Profile.ExportString)
	importBox = Private.Controls.TextArea(page, IMPORT_HEIGHT, function()
		return pending
	end, function(value)
		pending = value
	end)

	return Private.Node.Column(page, {
		Private.Controls.SubHeading(page, L.Export),
		exportBox,
		Private.Controls.ActionButton(page, L.Copy, function()
			exportBox:Highlight()
		end),

		Private.Controls.SubHeading(page, L.Import),
		importBox,
		Private.Controls.ActionButton(page, L.Import, function()
			DoImport(importBox)
		end),
	})
end

Private.Options.Builders.importExport = BuildImportExport
