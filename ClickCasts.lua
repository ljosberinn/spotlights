---@type string, Spotlights
local _, Private = ...

---@class SpotlightsClickCasts
Private.ClickCasts = {}

--- Click and key bindings that cast a spell on a spotlight and do nothing anywhere else.
---
--- A mouse binding is stored as the click the user **pressed** -- a button name plus the game's own modifier
--- bitfield -- and resolved to secure attributes at apply time rather than at bind time. That indirection
--- is the whole design: `SecureUnitButton_OnClick` rewrites an *interaction* click to that interaction's
--- default button before it reads `type` (`SecureTemplates.lua:863-865`), so which suffix a binding has to
--- occupy is the client's current answer rather than a fact about the button. Resolving late means moving
--- Target to another button in the game's own UI cannot leave a spotlight binding firing from a button
--- nobody chose.
---
--- A key press is not a click on a unit frame, so it cannot use that route at all. Keys are stored as a
--- binding chord and dispatched through a per-spotlight proxy button -- see `EnsureKeyProxy`.
---
--- We write `type*` and `spell*` on our own children and their proxies. `unit` stays the header's, so no
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

local PROXY_ATTRIBUTE = "spotlightsKeyProxy"
local KEYS_ATTRIBUTE = "spotlightsKeyBindings"

---@return SpotlightsClickCast[]
local function Bindings()
	local db = Private.DB

	return db and db.clickCasts or {}
end

--- The chord a row binds, or nil for a mouse row. Type-checked because stored rows are validated where they
--- are read (`Migration.lua:576-579`).
---@param binding SpotlightsClickCast
---@return string?
local function KeyOf(binding)
	local key = binding.key

	if type(key) ~= "string" or key == "" then
		return nil
	end

	return key
end

--- Whether a button suffix can carry a binding at all. `SecureButton_GetButtonSuffix` answers `""` for no
--- button and `"-<name>"` for one outside the 31 it knows (`SecureTemplates.lua:101-117`); neither can be
--- pasted into an attribute name that the click path will ever look up.
---@param suffix string
---@return boolean
local function IsUsableSuffix(suffix)
	return suffix ~= "" and string.sub(suffix, 1, 1) ~= "-"
end

--- The attribute prefix and suffix a mouse binding occupies **right now**.
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

--- The chord is folded into the button name rather than left to the attribute prefix, so `SHIFT-F10` and
--- `F10` are independent of what `SecureButton_GetModifierPrefix` reports at delivery time. Punctuation is
--- escaped rather than dropped because `-` and `=` are key names too; a chord is upper case, so the escape
--- cannot collide inside one.
---@param key string
---@return string
local function VirtualButton(key)
	return "spotlights" .. string.gsub(key, "%W", function(char)
		return "x" .. string.byte(char)
	end)
end

--- Sorts mouse bindings by the button's own suffix and then by modifiers, so the list reads left, right,
--- middle and then the extra buttons in number order instead of the alphabetical order the button *names*
--- would give. Keys sort after every one of them, in chord order: a key has no suffix to interleave on.
---@param left SpotlightsClickCast
---@param right SpotlightsClickCast
---@return boolean
local function Precedes(left, right)
	local leftKey = KeyOf(left)
	local rightKey = KeyOf(right)

	if (leftKey ~= nil) ~= (rightKey ~= nil) then
		return rightKey ~= nil
	end

	if leftKey and rightKey then
		return leftKey < rightKey
	end

	local leftButton = tonumber(SecureButton_GetButtonSuffix(left.button)) or 0
	local rightButton = tonumber(SecureButton_GetButtonSuffix(right.button)) or 0

	if leftButton ~= rightButton then
		return leftButton < rightButton
	end

	return left.modifiers < right.modifiers
end

--- Its own frame because `SecureHandlerWrapScript` requires one that is *explicitly* protected
--- (`SecureHandlers.lua:622`), which the slot headers are not.
local handler = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")

--- Bound on hover because an override binding is global: one set out of combat would fire on whichever slot
--- the header last assigned. Space separates the fields because it cannot appear in a chord, and returning
--- nothing is required -- `false` out of a wrapped `OnEnter` suppresses the unit tooltip it wraps
--- (`SecureHandlers.lua:296`).
local ENTER_SNIPPET = string.format([[
	local proxy = self:GetAttribute("%s")
	local keys = self:GetAttribute("%s")

	if proxy and keys then
		for key, button in gmatch(keys, "(%%S+) (%%S+)") do
			self:SetBindingClick(true, key, proxy, button)
		end
	end
]], PROXY_ATTRIBUTE, KEYS_ATTRIBUTE)

local LEAVE_SNIPPET = [[
	self:ClearBindings()
]]

local proxies = 0

--- The button a key binding's click lands on, one per spotlight. Out of combat only, and idempotent.
---
--- **It exists because press cannot be had on the child.** `SecureUnitButton_OnClick` calls
--- `OnActionButtonClick` directly (`SecureTemplates.lua:887`) and so never consults `useOnKeyDown`, and the
--- only other lever is `RegisterForClicks`, where adding `AnyDown` would fire every real mouse click twice.
---@param child SpotlightsUnitFrame
---@return SpotlightsClickCastProxy
local function EnsureKeyProxy(child)
	local existing = child.spotlightsKeyProxy

	if existing then
		return existing
	end

	proxies = proxies + 1

	local proxy = CreateFrame(
		"Button",
		"SpotlightsClickCastProxy" .. proxies,
		child,
		"SecureActionButtonTemplate"
	) --[[@as SpotlightsClickCastProxy]]

	-- It must never take a click meant for the spotlight underneath it.
	proxy:SetSize(1, 1)
	proxy:SetPoint("TOPLEFT", child, "TOPLEFT")
	proxy:EnableMouse(false)

	-- So `SecureButton_GetModifiedUnit` reads the header's unit and no Spotlights code holds the token.
	proxy:SetAttribute("useparent-unit", true)

	proxy:SetAttribute("useOnKeyDown", true)

	-- Both edges, because which one a wheel click arrives as is undocumented; `useOnKeyDown` makes the
	-- release a no-op either way (`SecureTemplates.lua:812-818`).
	proxy:RegisterForClicks("AnyDown", "AnyUp")

	child.spotlightsKeyProxy = proxy
	child:SetAttribute(PROXY_ATTRIBUTE, proxy:GetName())

	-- Wrapped rather than inheriting `SecureHandlerEnterLeaveTemplate`, which declares its own OnEnter and
	-- OnLeave and would take the template's unit tooltip with it.
	SecureHandlerWrapScript(child, "OnEnter", handler, ENTER_SNIPPET)
	SecureHandlerWrapScript(child, "OnLeave", handler, LEAVE_SNIPPET)

	-- No OnLeave fires for a spotlight hidden under the cursor, and the header reassigns that slot's `unit`
	-- on its next update.
	SecureHandlerWrapScript(child, "OnHide", handler, LEAVE_SNIPPET)

	return proxy
end

--- Writes an attribute set onto a frame and clears what a previous pass left behind that this one does not
--- want.
---
--- The written set is kept on the frame because a binding's attribute *name* moves when the game's own
--- interaction buttons move, so "what this frame currently holds" cannot be recomputed from the database
--- alone.
---@param frame SpotlightsUnitFrame|SpotlightsClickCastProxy
---@param attributes table<string, string>
local function Reconcile(frame, attributes)
	local previous = frame.spotlightsClickCasts

	if previous then
		for name in pairs(previous) do
			if not attributes[name] then
				-- Nils rather than blanks, so an unmodified binding that is removed hands left-click back to
				-- the `*type1` the template wrote: the wildcard is only shadowed while the specific
				-- attribute exists (`SecureTemplates.lua:249-252`).
				frame:SetAttribute(name, nil)
			end
		end
	end

	for name, value in pairs(attributes) do
		frame:SetAttribute(name, value)
	end

	frame.spotlightsClickCasts = attributes
end

--- Applies every binding to one child, and clears the attributes a removed one left behind. Out of combat
--- only, and safe to re-run: it is the same pass on a fresh child and on a settings change.
---@param child SpotlightsUnitFrame
function Private.ClickCasts.ApplyChild(child)
	local proxy = EnsureKeyProxy(child)
	local bindings = Bindings()

	---@type table<string, string>
	local clicks = {}

	---@type table<string, string>
	local keys = {}

	---@type string[]
	local chords = {}

	for i = 1, #bindings do
		local binding = bindings[i]
		local key = KeyOf(binding)

		if key then
			local button = VirtualButton(key)
			local typeName = "*type-" .. button

			-- A wildcard prefix rather than a bare `type-<name>`, since only the wildcard form is certainly
			-- in the modified-attribute lookup set (`SecureTemplates.lua:6-28`) and the modifier is already
			-- in the suffix.
			if not keys[typeName] then
				keys[typeName] = "spell"
				keys["*spell-" .. button] = tostring(binding.spellID)
				chords[#chords + 1] = key .. " " .. button
			end
		else
			local prefix, suffix = Attribute(binding)
			local typeName = prefix .. "type" .. suffix

			-- Two bindings can resolve onto one suffix -- pressing the button an interaction was moved onto
			-- lands on that interaction's default -- and the earlier one in list order keeps it, so which of
			-- the two fires does not depend on the order `pairs` happens to write them in.
			if IsUsableSuffix(suffix) and not clicks[typeName] then
				clicks[typeName] = "spell"
				clicks[prefix .. "spell" .. suffix] = tostring(binding.spellID)
			end
		end
	end

	Reconcile(child, clicks)
	Reconcile(proxy, keys)
	child:SetAttribute(KEYS_ATTRIBUTE, #chords > 0 and table.concat(chords, " ") or nil)
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

--- Whether a row is a key binding, for the panel: the two routes have different conflicts.
---@param binding SpotlightsClickCast
---@return string? key
function Private.ClickCasts.KeyOf(binding)
	return KeyOf(binding)
end

--- What a binding reads as on screen: "Shift + Left Click", or just the button when nothing is held.
---
--- `CLICK_BINDINGS_BINDING_TEXT_FORMAT`, `GetStringFromModifiers` and `GetBindingText` are the game's own,
--- so a Spotlights row and a row in the client's own windows spell the same combination the same way.
---@param binding SpotlightsClickCast
---@return string
function Private.ClickCasts.Describe(binding)
	local key = KeyOf(binding)

	if key then
		return GetBindingText(key) or key
	end

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

--- Stores a binding, replacing whichever one already claims the same chord, or the same button and modifier
--- prefix.
---
--- Keyed on the prefix rather than the modifier bitfield because the prefix is what the secure lookup
--- reads: a modifier the client counts and `SecureButton_GetModifierPrefix` does not would otherwise store
--- two rows that fire as one.
---@param binding SpotlightsClickCast
---@return boolean stored
function Private.ClickCasts.Store(binding)
	local db = Private.DB
	local key = KeyOf(binding)

	if not db then
		return false
	end

	if not key and not IsUsableSuffix(SecureButton_GetButtonSuffix(binding.button)) then
		return false
	end

	local bindings = db.clickCasts
	local index = #bindings + 1

	for i = 1, #bindings do
		local other = bindings[i]
		local otherKey = KeyOf(other)

		if key and otherKey == key then
			index = i

			break
		end

		if not key and not otherKey and other.button == binding.button and other.prefix == binding.prefix then
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
