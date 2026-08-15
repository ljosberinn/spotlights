---@type string, Spotlights
local addonName, Private = ...

--- The General tab: where the grid sits, how big it is drawn and what it stacks against, beside the
--- interface odds and ends that belong to no other tab.

--- Narrower than the kit's 130 default, since a column half the panel wide has half the room for a control.
local COLUMN_LABEL_WIDTH = 100

--- A checkbox's label is a sentence where a slider's is a noun, and the column above would clip it.
local CHECKBOX_LABEL_WIDTH = 220

--- The floor is where a spotlight's name is still readable at the default 100x50. The ceiling is arbitrary;
--- `Container` re-clamps on every apply, so a grid scaled past the screen edge is pulled back.
local SCALE_MIN = 0.5
local SCALE_MAX = 2
local SCALE_STEP = 0.05

---@return SpotlightsPositionConfig?
local function Position()
	return Private.Container.GetPosition()
end

--- Built per call because this file loads before the localisation table is filled.
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

--- Recentres the grid, as `/spotlights recenter` does. Silent in combat rather than printing what the slash
--- command prints: combat closes the panel, so this is reachable only in the frame or two before that runs.
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

	-- The apply is deferred and keyed, so a drag costs one container pass per frame rather than one per
	-- event.
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

--- Stored inverted, since LibDBIcon's own field is `hide`, and pushed to the library rather than left for
--- the next login.
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
