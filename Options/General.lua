---@type string, Spotlights
local addonName, Private = ...

--- The General tab: where the grid sits, how big it is drawn and what it stacks against, beside the
--- interface odds and ends that belong to no other tab.
---
--- Two columns rather than one list, because the two halves answer different questions and neither is
--- long enough to be a tab of its own.

--- What the label column costs in a ~350px half of the panel. Narrower than the kit's 130 default: a
--- column half the panel wide has half the room for a control, and the two rows that carry one here
--- are a slider and a dropdown.
local COLUMN_LABEL_WIDTH = 100

--- What a checkbox spends on its caption instead. A checkbox's label is a sentence where a slider's is
--- a noun, and clipping it to the column above would lose the half that says what the box does.
local CHECKBOX_LABEL_WIDTH = 220

--- Half size to double, in twentieths.
---
--- The floor is where a spotlight's name is still readable at the default 100x50; below it the frame is
--- a coloured bar. The ceiling is arbitrary in the same way every slider's is, and the clamp that
--- matters is the screen one -- `Container` re-clamps on every apply, so a grid scaled past the edge is
--- pulled back rather than lost.
local SCALE_MIN = 0.5
local SCALE_MAX = 2
local SCALE_STEP = 0.05

---@return SpotlightsPositionConfig?
local function Position()
	return Private.Container.GetPosition()
end

--- The strata list as the dropdown wants it, built per call because the labels are localised and this
--- file loads before the localisation table is filled.
---@return { value: any, label: string }[]
local function StrataChoices()
	local L = Private.L.Settings
	local order = Private.Enum.FrameStrataOrder
	local choices = {}

	for i = 1, #order do
		choices[i] = { value = order[i], label = L.Strata[order[i]] }
	end

	return choices
end

--- Recentres the grid, as `/spotlights recenter` does.
---
--- Silent in combat rather than printing what the slash command prints: the user is looking at the
--- panel, and the panel is closed by combat the moment it starts -- so this is only reachable in the
--- frame or two where a pull has begun and the close has not run yet.
local function Recenter()
	local position = Position()

	if not position or InCombatLockdown() then
		return
	end

	position.point, position.x, position.y = "CENTER", 0, 0

	Private.Container.Request()
end

---@return number
local function GetScale()
	local position = Position()

	return position and position.scale or 1
end

---@param value number
local function SetScale(value)
	local position = Position()

	if not position then
		return
	end

	position.scale = value

	-- Every drag frame comes through here, and the apply is deferred and keyed, so a drag costs one
	-- container pass per frame rather than one per event.
	Private.Container.Request()
end

---@return FrameStrata
local function GetStrata()
	local position = Position()

	return position and position.strata or "LOW"
end

---@param value FrameStrata
local function SetStrata(value)
	local position = Position()

	if not position then
		return
	end

	position.strata = value

	Private.Container.Request()
end

---@return boolean
local function GetMinimapShown()
	local minimap = Private.DB and Private.DB.minimap

	return minimap and not minimap.hide or false
end

--- Stored inverted -- LibDBIcon's own field is `hide` -- and pushed to the library rather than left for
--- the next login, since the button is what the user is looking at while they click this.
---@param value boolean
local function SetMinimapShown(value)
	local minimap = Private.DB and Private.DB.minimap

	if not minimap then
		return
	end

	minimap.hide = not value

	local icon = LibStub("LibDBIcon-1.0")

	if value then
		icon:Show(addonName)
	else
		icon:Hide(addonName)
	end
end

---@param page Frame
---@return SpotlightsNode
local function BuildGeneral(page)
	local L = Private.L.Settings

	local placement = Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.PlacementHeading),

		Private.Controls.Checkbox(page, L.UnlockFrames, Private.Mover.IsUnlocked,
			Private.Mover.SetUnlocked, nil, true, CHECKBOX_LABEL_WIDTH),

		Private.Controls.ActionButton(page, L.Recenter, Recenter),
		Private.Controls.Slider(page, L.Scale, SCALE_MIN, SCALE_MAX, SCALE_STEP, GetScale, SetScale),

		-- A table rather than a function: the strata are ours and fixed, where a media list is not.
		Private.Controls.Dropdown(page, L.FrameStrata, StrataChoices(), GetStrata, SetStrata),
	}, 1, COLUMN_LABEL_WIDTH)

	local interface = Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.InterfaceHeading),

		Private.Controls.Checkbox(page, L.ShowMinimapButton, GetMinimapShown, SetMinimapShown, nil, true,
			CHECKBOX_LABEL_WIDTH),

		Private.Controls.Paragraph(page, L.SlashHint),
	}, 1, COLUMN_LABEL_WIDTH)

	return Private.Node.Split(page, placement, interface)
end

Private.Options.Builders.general = BuildGeneral
