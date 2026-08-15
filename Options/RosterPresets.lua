---@type string, Spotlights
local _, Private = ...

---@class SpotlightsRosterPresets
Private.RosterPresets = {}

--- The Presets block under the Unrostered list: a saved slot layout per raid composition, and the four
--- things that can be done with one.
---
--- A preset is a **slot list and nothing else** -- appearance, auras and position are the same whichever
--- raid is in front of you. Applying one replaces the grid outright, because a merge would have to guess
--- what happens to a slot the preset does not name.
---
--- Nothing here writes a slot itself: applying goes through `Private.Registry.SetSlots`.

--- Less than half the Import/Export tab's 160, because every pixel this block takes is a raid member the
--- Unrostered list above it stops showing.
local BOX_HEIGHT = 70

--- Registered at click time so the localisation table is filled by then, and keyed as sparsely as every
--- other prompt here: `StaticPopup_Show` reuses the dialog already on screen for a key.
local NAME_POPUP = "SPOTLIGHTS_PRESET_NAME"
local OVERWRITE_POPUP = "SPOTLIGHTS_PRESET_OVERWRITE"
local DELETE_POPUP = "SPOTLIGHTS_PRESET_DELETE"

--- Shared with the Import/Export tab, which raises the same dialog about the same failure. The two
--- reasons that are specific to a preset are said in the *detail* the dialog is formatted with.
local IMPORT_ERROR_POPUP = "SPOTLIGHTS_IMPORT_ERROR"

--- Which preset the dropdown is on. Transient, like the Tracked sub-tab's search box: a position in a list
--- rather than a setting.
---@type string?
local selected

--- Which box, if either, is open under the buttons. `nil` is the resting state.
---@type "import" | "export" | nil
local box

--- What has been pasted into the import box: there is nothing in the database to read it back from between
--- a paste and the click.
local pending = ""

---@return SpotlightsPresets
local function Presets()
	local db = Private.DB

	return db and db.presets or {}
end

--- The preset names in a stable order: `pairs` can differ between sessions, and a list that reshuffles
--- itself is one nobody can find anything in twice.
---@return string[]
local function Names()
	local names = {}

	for name in pairs(Presets()) do
		names[#names + 1] = name
	end

	table.sort(names)

	return names
end

---@return { value: any, label: string }[]
local function Choices()
	local names = Names()
	local choices = {}

	for i = 1, #names do
		choices[i] = { value = names[i], label = names[i] }
	end

	return choices
end

--- The selection, corrected first: a preset can go while it is selected, by a delete or by an import
--- replacing the database under the panel.
---
--- Dropped rather than moved to a neighbour, since the grid still holds what it held and naming any
--- remaining preset would claim an arrangement that was never applied.
---@return string?
local function Selected()
	local presets = Presets()

	if selected and not presets[selected] then
		selected = nil
	end

	return selected
end

--- The current grid as a preset stores it: kinds and names, no GUIDs. See `SpotlightsPresets` -- a GUID
--- belongs to the raid the preset was saved in, and would give `SetSlots` a stale answer to prefer.
---@return SpotlightsSlot[]
local function Snapshot()
	local slots = Private.Registry.GetSlots()
	local copy = {}

	for i = 1, #slots do
		local slot = slots[i]

		copy[i] = slot.kind == "player" and { kind = "player", name = slot.name } or { kind = "blank" }
	end

	return copy
end

--- Stores a preset under a name, closing whatever box was open.
---
--- Saving the grid selects what was stored, which is the confirmation. An import does not: it fills the
--- shelf and touches nothing else, so a selection would name an arrangement the grid does not have -- and
--- an import landing *on* the selected preset drops the selection for the same reason.
---@param name string
---@param slots SpotlightsSlot[]
---@param selecting boolean
local function Store(name, slots, selecting)
	local db = Private.DB

	if not db then
		return
	end

	db.presets[name] = slots

	if selecting then
		selected = name
	elseif selected == name then
		selected = nil
	end

	box = nil
	pending = ""

	Private.Options.Refresh()
end

---@param name string
---@param slots SpotlightsSlot[]
---@param selecting boolean
local function ConfirmOverwrite(name, slots, selecting)
	local L = Private.L.Settings

	StaticPopupDialogs[OVERWRITE_POPUP] = {
		text = string.format(L.PresetOverwritePrompt, name),
		button1 = L.PresetOverwriteConfirm,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			Store(name, slots, selecting)
		end,
	}

	StaticPopup_Show(OVERWRITE_POPUP)
end

--- Asks for a name, then stores the slots under it.
---
--- One dialog for both callers -- saving the grid and naming an imported string -- with the accept handler
--- registered against the slots it is about rather than handed them through the dialog's `data`. An
--- existing name is a second prompt rather than a refusal.
---
--- `suggested` is the name an imported string carried, and changes only the question the dialog asks.
--- `selecting` is carried rather than derived from it: the two happen to agree today but are about
--- different things.
---@param slots SpotlightsSlot[]
---@param selecting boolean
---@param suggested string?
local function PromptName(slots, selecting, suggested)
	local L = Private.L.Settings

	--- Typed loosely because the dialog is Blizzard's: `GetEditBox` and `GetButton1` come from
	--- `GameDialogMixin`, which the annotations do not describe.
	---@param dialog any
	local function Accept(dialog)
		local name = strtrim(dialog:GetEditBox():GetText())

		if name == "" then
			return
		end

		if Presets()[name] then
			ConfirmOverwrite(name, slots, selecting)

			return
		end

		Store(name, slots, selecting)
	end

	StaticPopupDialogs[NAME_POPUP] = {
		text = suggested and string.format(L.PresetImportNamePrompt, suggested) or L.PresetSavePrompt,
		button1 = L.PresetSave,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		hasEditBox = true,
		-- The codec's bound, so a typed name and an arriving one are held to the one limit, enforced as the
		-- user types rather than truncated after the fact.
		maxLetters = Private.Profile.MAX_PRESET_NAME_LETTERS,

		OnShow = function(dialog)
			local editBox = dialog:GetEditBox()

			-- Filled with the imported name and selected, so accepting keeps it and typing replaces it.
			editBox:SetText(suggested or "")
			editBox:HighlightText()
			editBox:SetFocus()

			dialog:GetButton1():SetEnabled(suggested ~= nil)
		end,

		-- Blizzard's own handler: it enables the accept button once the box holds something.
		EditBoxOnTextChanged = StaticPopup_StandardNonEmptyTextHandler,

		---@param editBox any
		EditBoxOnEnterPressed = function(editBox)
			local dialog = editBox:GetParent()

			if dialog:GetButton1():IsEnabled() then
				Accept(dialog)
				dialog:Hide()
			end
		end,

		OnAccept = Accept,
	}

	StaticPopup_Show(NAME_POPUP)
end

--- Deletes the selected preset, after asking: it discards an arrangement that took a raid night to lay out,
--- from a button sitting beside three that are not destructive. The prompt says the grid itself is
--- untouched, since "delete" next to a list of slots could mean either.
local function ConfirmDelete()
	local L = Private.L.Settings
	local name = Selected()

	if not name then
		return
	end

	StaticPopupDialogs[DELETE_POPUP] = {
		text = string.format(L.PresetDeletePrompt, name),
		button1 = L.PresetDelete,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnAccept = function()
			local db = Private.DB

			if not db then
				return
			end

			db.presets[name] = nil

			-- Said here as well as in `Selected`, which would drop it next pass anyway: a neighbour picked to
			-- fill the gap would silently arm Delete over whatever sat beside what was deleted.
			selected = nil
			box = nil

			Private.Options.Refresh()
		end,
	}

	StaticPopup_Show(DELETE_POPUP)
end

---@param reason string?
local function ShowImportError(reason)
	local L = Private.L.Settings
	local details = reason == "prefix" and L.PresetImportErrorPrefix
		or reason == "decode" and L.ImportErrorDecode
		or L.PresetImportErrorPayload

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

--- Reads the pasted string and, if it is a preset, offers the name it arrived under.
---
--- A prompt rather than a straight store, because the author's name can collide with one in this account's
--- library and a preset stored under a name nobody was shown is one nobody can find. Nothing is applied to
--- the grid -- an import fills the shelf; selecting is what puts a preset in play.
local function DoImport()
	local preset, reason = Private.Profile.ImportPresetString(strtrim(pending))

	if not preset then
		ShowImportError(reason)

		return
	end

	PromptName(preset.slots, false, preset.name)
end

--- Opens one of the two boxes, or closes the one that is open. A toggle, so the button that opened a box
--- taking a third of the column is also the way out of it.
---@param kind "import" | "export"
local function ToggleBox(kind)
	box = box ~= kind and kind or nil

	Private.Options.Refresh()
end

--- The block.
---@param page Frame
---@return SpotlightsNode
function Private.RosterPresets.Build(page)
	local L = Private.L.Settings

	local function HasPresets()
		return next(Presets()) ~= nil
	end

	local function HasSlots()
		return #Private.Registry.GetSlots() > 0
	end

	local function HasSelection()
		return Selected() ~= nil
	end

	local body = Private.Node.Column(page, {
		Private.Node.OnlyWhen(Private.Controls.Paragraph(page, L.PresetsNone), function()
			return not HasPresets()
		end),

		--- No label: the section header says what the dropdown lists, and a label column would leave a
		--- dropdown too narrow to read a name in at this column's 250.
		Private.Node.OnlyWhen(Private.Controls.Dropdown(page, nil, Choices, Selected, function(name)
			selected = name

			-- Selecting *is* applying: an Apply button beside it could never mean anything else.
			Private.Registry.SetSlots(Presets()[name] or {})
			Private.Options.Refresh()
		end, nil, L.PresetNoneSelected), HasPresets),

		Private.Controls.ButtonRow(page, {
			{
				label = L.PresetSave,
				enabled = HasSlots,
				onClick = function()
					PromptName(Snapshot(), true)
				end,
			},
			{
				label = L.PresetDelete,
				destructive = true,
				enabled = HasSelection,
				onClick = ConfirmDelete,
			},
		}),

		Private.Controls.ButtonRow(page, {
			{
				label = L.Import,
				onClick = function()
					ToggleBox("import")
				end,
			},
			{
				label = L.Export,
				enabled = HasSelection,
				onClick = function()
					ToggleBox("export")
				end,
			},
		}),

		Private.Node.OnlyWhen(Private.Controls.TextArea(page, BOX_HEIGHT, function()
			local name = Selected()

			return name and Private.Profile.ExportPresetString(name, Presets()[name]) or ""
		end), function()
			return box == "export" and HasSelection()
		end),

		Private.Node.OnlyWhen(Private.Controls.TextArea(page, BOX_HEIGHT, function()
			return pending
		end, function(value)
			pending = value
		end), function()
			return box == "import"
		end),

		Private.Node.OnlyWhen(Private.Controls.ActionButton(page, L.PresetImportAdd, DoImport), function()
			return box == "import"
		end),
	})

	return Private.Node.Section(page, function()
		return L.PresetsHeading
	end, function()
		local count = #Names()

		-- Silent at zero: the body already says there is nothing here.
		return count > 0 and string.format(L.PresetsCount, count) or nil
	end, body, false)
end
