---@type string, Spotlights
local _, Private = ...

---@class SpotlightsLoadCondition
Private.LoadCondition = {}

--- Whether the player's spec currently passes the load condition. `nil` until the first evaluation --
--- deliberately distinct from `true` or `false`, since Reevaluate must publish on that first pass whatever
--- it lands on, and starting from either boolean would swallow one of the two possible outcomes as "no
--- change".
---@type boolean?
local active

--- The current answer, independent of what was last published.
---@return boolean
local function Evaluate()
	local specID = PlayerUtil.GetCurrentSpecID()

	-- Fails open: nil is no spec chosen yet, and 0 is the field's documented default for a level with no
	-- specialization. Neither is a spec the player has actually chosen to deny.
	if not specID or specID == 0 then
		return true
	end

	local db = Private.DB

	-- Fails open before the migration has run, on the same grounds: nothing has been denied yet.
	if not db then
		return true
	end

	return not db.loadCondition.disabledSpecs[specID]
end

--- Re-evaluates and, only on a change, publishes it to `Container` and `Minimap`. Kept to this one call
--- site so every consumer of the inert transition hooks here rather than risking a second copy that could
--- drift apart.
function Private.LoadCondition.Reevaluate()
	local result = Evaluate()

	if result == active then
		return
	end

	active = result

	Private.Container.SetInert(not active)
	-- Init.lua's data object exists only from ADDON_LOADED onward; this first runs at PLAYER_LOGIN, which
	-- always follows, so it is safe to call unconditionally.
	Private.Minimap.SetInert(not active)
end

--- Whether Spotlights should be doing anything right now. Reads the cache Reevaluate maintains, so the
--- sweeps elsewhere can call it freely; fails open for the window before the first PLAYER_LOGIN pass has
--- run, on the same grounds as Evaluate's own fail-open branches.
---@return boolean
function Private.LoadCondition.IsActive()
	if active == nil then
		return true
	end

	return active
end

--- The picker's choices: every class with its specialisations, sorted by localised class name so the order
--- does not reshuffle between sessions -- mirrors `Options/AuraSpells.lua`'s `BuiltinGroups`, including its
--- fallback for a class `C_CreatureInfo.GetClassInfo` answers nil for.
---@return SpotlightsNestedChoiceGroup[]
function Private.LoadCondition.SpecChoices()
	---@type SpotlightsNestedChoiceGroup[]
	local choices = {}
	local sex = UnitSex("player")

	for _, classID in pairs(Constants.UICharacterClasses) do
		local info = C_CreatureInfo.GetClassInfo(classID)
		local color = info and RAID_CLASS_COLORS[info.classFile]
		local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0

		-- A class that reports zero specs would advertise a group whose "every spec selected" test passes
		-- over an empty list -- permanently checked, with nothing for a click to do.
		if numSpecs > 0 then
			---@type { specID: integer, name: string }[]
			local specs = {}

			for index = 1, numSpecs do
				local specID, specName = GetSpecializationInfoForClassID(classID, index, sex)

				if specID then
					specs[#specs + 1] = { specID = specID, name = specName }
				end
			end

			choices[#choices + 1] = {
				classFile = info and info.classFile or tostring(classID),
				className = info and info.className or tostring(classID),
				r = color and color.r or 1,
				g = color and color.g or 1,
				b = color and color.b or 1,
				specs = specs,
			}
		end
	end

	table.sort(choices, function(left, right)
		return left.className < right.className
	end)

	return choices
end

Private.Events.RegisterEvent("PLAYER_LOGIN", Private.LoadCondition.Reevaluate)
Private.Events.RegisterEvent("PLAYER_ENTERING_WORLD", Private.LoadCondition.Reevaluate)
Private.Events.RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", Private.LoadCondition.Reevaluate)
