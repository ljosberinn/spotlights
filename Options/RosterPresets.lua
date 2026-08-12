---@type string, Spotlights
local _, Private = ...

---@class SpotlightsRosterPresets
Private.RosterPresets = {}

--- The Presets block under the raid list: a saved slot layout per raid composition, and the four
--- things that can be done with one.
---
--- A preset is a **slot list and nothing else**. Appearance, auras and the grid's position are the
--- same whichever raid is in front of you; who is in the grid is exactly what is not, and rebuilding
--- twenty slots by hand for the second composition of the night is the problem this block exists for.
---
--- Applying one replaces the grid outright rather than merging into it. A merge would have to answer
--- what happens to a slot the preset does not name, and there is no answer that is not a guess -- a
--- preset is a whole arrangement, not a set of edits.
---
--- Nothing here writes a slot itself: applying goes through `Private.Registry.SetSlots`, like every
--- other front-end onto the slot list.

--- What a text box in this column costs. Shorter than the Import/Export tab's 130, because the block
--- shares its column with the raid list and every pixel it takes is a raid member the list stops
--- showing -- and a preset string is read by selecting it, not by reading it.
local BOX_HEIGHT = 70

--- The longest name a preset may be given. `hasEditBox` enforces it in the dialog, so a name is never
--- truncated after the fact; 32 is what Blizzard's own layout naming allows.
local MAX_NAME_LETTERS = 32

--- Registered at click time by whoever raised them, so the localisation table is filled by then --
--- and shared keys deliberately, as every other prompt in this panel: `StaticPopup_Show` reuses the
--- dialog already on screen for a key, where a second key would stack a second identical one.
local NAME_POPUP = "SPOTLIGHTS_PRESET_NAME"
local OVERWRITE_POPUP = "SPOTLIGHTS_PRESET_OVERWRITE"
local DELETE_POPUP = "SPOTLIGHTS_PRESET_DELETE"

--- Shared with the Import/Export tab, which raises the same dialog about the same failure. The two
--- reasons that are specific to a preset are said in the *detail* the dialog is formatted with.
local IMPORT_ERROR_POPUP = "SPOTLIGHTS_IMPORT_ERROR"

--- Which preset the dropdown is on. Transient, like the search box on the Tracked sub-tab: it is a
--- position in a list rather than a setting, and a preset selected in one session says nothing about
--- what the next one is for.
---@type string?
local selected

--- Which box, if either, is open under the buttons. `nil` is the resting state: neither string is
--- something the user needs in front of them until they ask for it, and both are as tall as several
--- raid members.
---@type "import" | "export" | nil
local box

--- What has been pasted into the import box, for the same reason the Import/Export tab keeps its own:
--- there is nothing in the database to read it back from between a paste and the click.
local pending = ""

---@return SpotlightsPresets
local function Presets()
	local db = Private.DB

	return db and db.presets or {}
end

--- The preset names in a stable order.
---
--- Sorted rather than `pairs`, which is the same reason the class rail sorts its groups: a map's
--- iteration order can differ between sessions, and a list that reshuffles itself is a list nobody
--- can find anything in twice.
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

--- The selection, corrected first.
---
--- Re-read rather than trusted, because a preset can go while it is selected -- the user deletes it,
--- or an import replaces the database under the panel. A selection pointing at nothing would dim the
--- buttons that act on it and show an empty export box, which reads as a broken preset rather than as
--- no preset.
---@return string?
local function Selected()
	local presets = Presets()

	if selected and not presets[selected] then
		selected = Names()[1]
	end

	return selected
end

--- The current grid as a preset stores it: kinds and names, no GUIDs.
---
--- See `SpotlightsPresets`. The GUID belongs to the raid the preset was saved in, and keeping one
--- would only give `SetSlots` a stale answer to prefer over the name.
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

--- Stores a preset under a name and selects it, closing whatever box was open.
---
--- Selecting it is the confirmation: the dropdown reads back what was just saved, so a name that was
--- typed and a name that was stored are visibly the same thing.
---@param name string
---@param slots SpotlightsSlot[]
local function Store(name, slots)
	local db = Private.DB

	if not db then
		return
	end

	db.presets[name] = slots
	selected = name
	box = nil
	pending = ""

	Private.Options.Refresh()
end

---@param name string
---@param slots SpotlightsSlot[]
local function ConfirmOverwrite(name, slots)
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
			Store(name, slots)
		end,
	}

	StaticPopup_Show(OVERWRITE_POPUP)
end

--- Asks for a name, then stores the slots under it.
---
--- One dialog for both callers -- saving the grid and naming an imported string -- because they ask
--- the same question about different slots, and the accept handler is registered with the slots it is
--- about rather than handed them through the dialog's `data`.
---
--- An existing name is a second prompt rather than a refusal: overwriting a preset is what the user
--- means most of the time they type a name they have used, and refusing it would leave them renaming
--- around their own library.
---@param slots SpotlightsSlot[]
local function PromptName(slots)
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
			ConfirmOverwrite(name, slots)

			return
		end

		Store(name, slots)
	end

	StaticPopupDialogs[NAME_POPUP] = {
		text = L.PresetSavePrompt,
		button1 = L.PresetSave,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
		hasEditBox = true,
		maxLetters = MAX_NAME_LETTERS,

		OnShow = function(dialog)
			-- Nothing to save under no name, so the button says so until there is one.
			dialog:GetButton1():Disable()
			dialog:GetEditBox():SetFocus()
		end,

		-- Blizzard's own handler for exactly this: it enables the accept button once the box holds
		-- something.
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

--- Deletes the selected preset, after asking.
---
--- Confirmed for the reason the roster's own clear is: it discards an arrangement that took a raid
--- night to lay out, and the button sits beside three that are not destructive at all. The prompt
--- says the grid itself is untouched, since "delete" next to a list of slots could mean either.
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

			-- Dropped rather than moved along: `Selected` picks the first remaining preset on the next
			-- pass, and choosing a neighbour here would silently arm Delete over whatever was beside
			-- what was just deleted.
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

--- Reads the pasted string and, if it is a preset, asks what to call it.
---
--- Named on arrival rather than carrying a name inside the string: a preset string is a slot list, and
--- a name that travelled with it would collide with the library it lands in without the user ever
--- seeing the name they were given.
---
--- Nothing is applied to the grid. An import fills the shelf; selecting is what puts a preset in play.
local function DoImport()
	local slots, reason = Private.Profile.ImportPresetString(strtrim(pending))

	if not slots then
		ShowImportError(reason)

		return
	end

	PromptName(slots)
end

--- Opens one of the two boxes, or closes the one that is open.
---
--- A toggle rather than two states, because both buttons are also the way out: the box takes a third
--- of the column and the user who opened it by accident should not have to find something else to
--- click.
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

		--- No label: the section header above already says what the dropdown lists, and this column is
		--- 250 wide -- a label column here would leave a dropdown too narrow to read a name in.
		Private.Node.OnlyWhen(Private.Controls.Dropdown(page, nil, Choices, Selected, function(name)
			selected = name

			-- Selecting *is* applying, which is what makes the block worth having: the alternative is a
			-- second click on an Apply button that could never mean anything else.
			Private.Registry.SetSlots(Presets()[name] or {})
			Private.Options.Refresh()
		end), HasPresets),

		Private.Controls.ButtonRow(page, {
			{
				label = L.PresetSave,
				enabled = HasSlots,
				onClick = function()
					PromptName(Snapshot())
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

			return name and Private.Profile.ExportPresetString(Presets()[name]) or ""
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

		-- Silent at zero: the body already says there is nothing here, and "0 saved" in the header
		-- would say it twice in the one place a collapsed section has to be brief.
		return count > 0 and string.format(L.PresetsCount, count) or nil
	end, body, false)
end
