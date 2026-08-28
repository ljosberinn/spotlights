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

--- Recentres the grid, as `/spotlights recenter` does, refusal in combat included. Says so rather than
--- returning silently: a setting that lands late is one thing, a button that does nothing reads as broken.
local function Recenter()
	if InCombatLockdown() then
		Private.Utils.Print(Private.L.Mover.CombatRefused)

		return
	end

	Private.Container.Recenter()
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

---@param specID integer
---@return boolean
local function IsSpecEnabled(specID)
	local db = Private.DB

	-- Fails open on the same grounds as `LoadCondition.Evaluate`: no database yet means nothing has been
	-- denied yet.
	return not db or not db.loadCondition.disabledSpecs[specID]
end

--- Ticks or unticks every spec in `specIDs` at once, which is what lets a class row, a submenu's bulk
--- buttons and the root's bulk buttons all go through one setter.
---@param specIDs integer[]
---@param selected boolean
local function SetSpecsEnabled(specIDs, selected)
	local db = Private.DB

	if not db then
		return
	end

	local disabledSpecs = db.loadCondition.disabledSpecs

	for i = 1, #specIDs do
		-- `nil` rather than `false`: the block is a denylist, and `false` would claim a shape the field
		-- does not have.
		disabledSpecs[specIDs[i]] = selected and nil or true
	end

	Private.LoadCondition.Reevaluate()
	Private.Options.Refresh()
end

--- What the closed dropdown reads: the two names for its ends, and a localised count between them --
--- never the list of spec names `CollectSelectionData`'s default translator would produce.
---@return string
local function LoadConditionSelectionText()
	local db = Private.DB
	local disabledSpecs = db and db.loadCondition.disabledSpecs

	-- Fails open on the same grounds as `IsSpecEnabled`: no database yet means nothing is denied.
	if not disabledSpecs then
		return ALL_SPECS
	end

	local groups = Private.LoadCondition.SpecChoices()
	local total = 0
	local enabled = 0

	for i = 1, #groups do
		local specs = groups[i].specs

		for j = 1, #specs do
			total = total + 1

			if not disabledSpecs[specs[j].specID] then
				enabled = enabled + 1
			end
		end
	end

	if enabled == 0 then
		return NONE
	end

	-- Keyed on the counts agreeing, not on whether `disabledSpecs` has any entry: a stale entry naming a
	-- spec no longer live must not read as a partial disable.
	if enabled == total then
		return ALL_SPECS
	end

	return string.format(Private.L.Settings.LoadConditionCount, enabled, total)
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

	local loadCondition = Private.Node.Grid(page, {
		Private.Controls.SubHeading(page, L.LoadConditionHeading),

		Private.Controls.NestedMultiselectDropdown(page, L.LoadCondition, Private.LoadCondition.SpecChoices,
			IsSpecEnabled, SetSpecsEnabled, LoadConditionSelectionText, nil, L.LoadConditionTooltip),
	}, 1, COLUMN_LABEL_WIDTH)

	return Private.Node.Split(page, placement, Private.Node.Column(page, { interface, loadCondition }))
end

Private.Options.Builders.general = BuildGeneral
