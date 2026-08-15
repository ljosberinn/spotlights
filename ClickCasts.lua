---@type string, Spotlights
local _, Private = ...

---@class SpotlightsClickCasts
Private.ClickCasts = {}

--- Click bindings that cast a spell on a spotlight and do nothing anywhere else.
---
--- A binding is stored as the click the user **pressed** -- a button name plus the game's own modifier
--- bitfield -- and resolved to secure attributes at apply time rather than at bind time. That indirection
--- is the whole design: `SecureUnitButton_OnClick` rewrites an *interaction* click to that interaction's
--- default button before it reads `type` (`SecureTemplates.lua:863-865`), so which suffix a binding has to
--- occupy is the client's current answer rather than a fact about the button. Resolving late means moving
--- Target to another button in the game's own UI cannot leave a spotlight binding firing from a button
--- nobody chose.
---
--- We write `type*` and `spell*` and nothing else, on our own children. `unit` stays the header's, so no
--- Spotlights code ever holds the unit token -- see `SlotHeader.InitChild`.

local DeferralKey = Private.Enum.DeferralKey

--- What a button is called on screen. Built rather than written out because 28 of the 31 entries are
--- `BUTTON_n_STRING` and only the first three have names of their own.
---@type table<string, string>
local BUTTON_LABELS = {
	LeftButton = LEFT_BUTTON_STRING,
	RightButton = RIGHT_BUTTON_STRING,
	MiddleButton = MIDDLE_BUTTON_STRING,
}

for i = 4, 31 do
	BUTTON_LABELS["Button" .. i] = _G["BUTTON_" .. i .. "_STRING"]
end

---@return SpotlightsClickCast[]
local function Bindings()
	local db = Private.DB

	return db and db.clickCasts or {}
end

--- Whether a button suffix can carry a binding at all. `SecureButton_GetButtonSuffix` answers `""` for no
--- button and `"-<name>"` for one outside the 31 it knows (`SecureTemplates.lua:101-117`); neither can be
--- pasted into an attribute name that the click path will ever look up.
---@param suffix string
---@return boolean
local function IsUsableSuffix(suffix)
	return suffix ~= "" and string.sub(suffix, 1, 1) ~= "-"
end

--- The attribute prefix and suffix a binding occupies **right now**.
---
--- The suffix follows the interaction rewrite rather than the pressed button, so a binding made while
--- Target sits on right-click is read out of suffix 1 -- which is what a right-click resolves to for as
--- long as that remains true, and what it stops resolving to the moment the user moves Target back.
---@param binding SpotlightsClickCast
---@return string prefix, string suffix
local function Attribute(binding)
	local button = binding.button

	if C_ClickBindings.GetBindingType(button, binding.modifiers) == Enum.ClickBindingType.Interaction then
		button = C_ClickBindings.GetEffectiveInteractionButton(button, binding.modifiers)
	end

	return binding.prefix, SecureButton_GetButtonSuffix(button)
end

--- Sorts by the button's own suffix and then by modifiers, so the list reads left, right, middle and then
--- the extra buttons in number order instead of the alphabetical order the button *names* would give.
---@param left SpotlightsClickCast
---@param right SpotlightsClickCast
---@return boolean
local function Precedes(left, right)
	local leftButton = tonumber(SecureButton_GetButtonSuffix(left.button)) or 0
	local rightButton = tonumber(SecureButton_GetButtonSuffix(right.button)) or 0

	if leftButton ~= rightButton then
		return leftButton < rightButton
	end

	return left.modifiers < right.modifiers
end

--- Applies every binding to one child, and clears the attributes a removed one left behind. Out of combat
--- only, and safe to re-run: it is the same pass on a fresh child and on a settings change.
---
--- The written set is kept on the child because a binding's attribute *name* moves when the game's own
--- interaction buttons move, so "what this child currently holds" cannot be recomputed from the database
--- alone.
---@param child SpotlightsUnitFrame
function Private.ClickCasts.ApplyChild(child)
	local bindings = Bindings()

	---@type table<string, string>
	local attributes = {}

	for i = 1, #bindings do
		local binding = bindings[i]
		local prefix, suffix = Attribute(binding)
		local typeName = prefix .. "type" .. suffix

		-- Two bindings can resolve onto one suffix -- pressing the button an interaction was moved onto
		-- lands on that interaction's default -- and the earlier one in list order keeps it, so which of
		-- the two fires does not depend on the order `pairs` happens to write them in.
		if IsUsableSuffix(suffix) and not attributes[typeName] then
			attributes[typeName] = "spell"
			attributes[prefix .. "spell" .. suffix] = tostring(binding.spellID)
		end
	end

	local previous = child.spotlightsClickCasts

	if previous then
		for name in pairs(previous) do
			if not attributes[name] then
				-- Nils rather than blanks, so an unmodified binding that is removed hands left-click back to
				-- the `*type1` the template wrote: the wildcard is only shadowed while the specific
				-- attribute exists (`SecureTemplates.lua:249-252`).
				child:SetAttribute(name, nil)
			end
		end
	end

	for name, value in pairs(attributes) do
		child:SetAttribute(name, value)
	end

	child.spotlightsClickCasts = attributes
end

--- Deferred because it is a protected call on every frame it touches. The panel refuses to open in combat,
--- but an import and a zone change do not.
local function Apply()
	if Private.Events.DeferIfInCombat(DeferralKey.ClickCasts) then
		return
	end

	Private.SlotHeader.ForEachChild(Private.ClickCasts.ApplyChild)
end

Private.Events.RegisterHandler(DeferralKey.ClickCasts, Apply)

--- Requests that pass. For a binding that changed, and for anything that changes which suffix one resolves
--- to.
function Private.ClickCasts.Request()
	Private.Events.Request(DeferralKey.ClickCasts)
end

--- Not a binding-changed event -- the client has none, and `CLICKBINDINGS_SET_HIGHLIGHTS_SHOWN` is about
--- the spellbook highlight. It does bracket the game's own Click Bindings window opening and closing, which
--- is where an interaction moves from, and the pass it triggers is idempotent.
Private.Events.RegisterEvent("CLICKBINDINGS_SET_HIGHLIGHTS_SHOWN", Private.ClickCasts.Request)

--- The bindings in display order. The stored array *is* that order -- `Store` keeps it sorted -- so callers
--- may index it directly, but must not reorder or mutate it.
---@return SpotlightsClickCast[]
function Private.ClickCasts.Get()
	return Bindings()
end

--- What a click reads as on screen: "Shift + Left Click", or just the button when nothing is held.
---
--- `CLICK_BINDINGS_BINDING_TEXT_FORMAT` and `GetStringFromModifiers` are the game's own, so a Spotlights
--- row and a row in the client's Click Bindings window spell the same combination the same way.
---@param binding SpotlightsClickCast
---@return string
function Private.ClickCasts.Describe(binding)
	local button = BUTTON_LABELS[binding.button] or binding.button
	local modifiers = GetStringFromModifiers(binding.modifiers)

	if modifiers == "" then
		return button
	end

	return string.format(CLICK_BINDINGS_BINDING_TEXT_FORMAT, modifiers, button)
end

--- The name of whatever the game's own click bindings run for a combination, for the two prompts and the
--- row notes that have to say it out loud.
---@param button string
---@param modifiers number
---@return string?
local function ProfileActionName(button, modifiers)
	local profile = C_ClickBindings.GetProfileInfo()

	for i = 1, #profile do
		local info = profile[i]

		if info.button == button and info.modifiers == modifiers then
			if info.type == Enum.ClickBindingType.Macro then
				return (GetMacroInfo(info.actionID))
			end

			-- Through the override, as the client's own list does: a talent that replaces a spell replaces
			-- the name the user would recognise with it.
			local spellInfo = C_Spell.GetSpellInfo(C_SpellBook.FindSpellOverrideByID(info.actionID))

			return spellInfo and spellInfo.name
		end
	end

	return nil
end

--- What the game itself does with a combination, and what to call it.
---
--- The interaction is read back from the button the click resolves to rather than looked up in the profile:
--- an interaction left on its default button is **absent from `GetProfileInfo` entirely**
--- (`Blizzard_ClickBindingUI.lua:125-138`), and an interaction's effective button is its default, so the
--- two the game has are told apart by which one that is.
---@param button string
---@param modifiers number
---@return ClickBindingType type, string? label what the game has bound there, absent when nothing is
function Private.ClickCasts.GameBinding(button, modifiers)
	local bindingType = C_ClickBindings.GetBindingType(button, modifiers)

	if bindingType == Enum.ClickBindingType.Interaction then
		local effective = C_ClickBindings.GetEffectiveInteractionButton(button, modifiers)

		return bindingType, effective == "RightButton" and CLICK_BINDING_OPEN_MENU or CLICK_BINDING_TARGET_UNIT
	end

	if bindingType == Enum.ClickBindingType.None then
		return bindingType, nil
	end

	return bindingType, ProfileActionName(button, modifiers)
end

--- Stores a binding, replacing whichever one already claims that button and modifier prefix.
---
--- Keyed on the prefix rather than the modifier bitfield because the prefix is what the secure lookup
--- reads: a modifier the client counts and `SecureButton_GetModifierPrefix` does not would otherwise store
--- two rows that fire as one.
---@param binding SpotlightsClickCast
---@return boolean stored
function Private.ClickCasts.Store(binding)
	local db = Private.DB

	if not db or not IsUsableSuffix(SecureButton_GetButtonSuffix(binding.button)) then
		return false
	end

	local bindings = db.clickCasts
	local index = #bindings + 1

	for i = 1, #bindings do
		if bindings[i].button == binding.button and bindings[i].prefix == binding.prefix then
			index = i

			break
		end
	end

	bindings[index] = binding

	table.sort(bindings, Precedes)
	Private.ClickCasts.Request()

	return true
end

--- Drops the binding at a list position, the panel's rows being that list.
---@param index integer
function Private.ClickCasts.Remove(index)
	local db = Private.DB

	if not db or not db.clickCasts[index] then
		return
	end

	table.remove(db.clickCasts, index)
	Private.ClickCasts.Request()
end
