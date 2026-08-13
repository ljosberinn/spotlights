---@type string, Spotlights
local _, Private = ...

---@class SpotlightsRegistry
Private.Registry = {}

local DeferralKey = Private.Enum.DeferralKey

---@return SpotlightsSlot[]?
local function Slots()
	return Private.DB and Private.DB.slots
end

--- The configured slots. Read-only by convention: every mutation goes through the four
--- entry points below, which also schedule the apply.
---@return SpotlightsSlot[]
function Private.Registry.GetSlots()
	return Slots() or {}
end

--- Which slot a GUID currently occupies, or nil.
---
--- GUID only, unlike the internal `FindOccupant`, which also matches on name so an offline-configured
--- slot still counts as taken. This answers the narrower "is this player already in the grid", and
--- every caller has a GUID from the current roster.
---@param guid string?
---@return integer? index
function Private.Registry.SlotOf(guid)
	local slots = Slots()

	if not slots or not guid then
		return nil
	end

	for i = 1, #slots do
		if slots[i].guid == guid then
			return i
		end
	end

	return nil
end

--- The role a slot's player is playing right now, or nil when there is nobody to ask about.
---
--- Resolves the name when the slot carries no GUID, because `SelfHeal` fills those in a deferral
--- later than the callers here run: a slot configured while its player was away would otherwise read
--- as roleless for one more event after they turned up.
---@param slot SpotlightsSlot
---@return string? role
local function SlotRole(slot)
	if slot.kind ~= "player" then
		return nil
	end

	local guid = slot.guid or (slot.name and Private.Roster.GetGuid(slot.name))

	return guid and Private.Roster.GetRole(guid) or nil
end

--- Takes every slot whose player is playing a role the user set to be removed back out of the grid.
---
--- **Backwards**, because a removal shifts the rest up: forwards would skip the slot after each one
--- and leave half the healers in.
---
--- Only a slot that resolves to a role is a candidate. `GetRole` answers nil for a player who is not
--- in the group, one who has not picked a role, and one whose identity is secret -- and an absent
--- raider's slot is the thing the grid exists to hold open, so an absence of information never
--- removes anything.
---
--- Silent, unlike the leave-the-group clear. That one is a single wipe of everything the user has,
--- announced because it is indistinguishable from data loss; this runs on every roster event and
--- takes out exactly what the setting names, so a line per healer joining would be chat spam.
---@return boolean removed
local function AutoRemoveRoles()
	local slots = Slots()
	local layout = Private.Layout.GetConfig()
	local roles = layout and layout.autoRemoveRoles

	if not slots or not roles then
		return false
	end

	local removed = false

	for i = #slots, 1, -1 do
		local role = SlotRole(slots[i])

		if role and roles[role] then
			table.remove(slots, i)

			removed = true
		end
	end

	return removed
end

--- Schedules the model onto the headers. Both keys, always: Build creates or grows the
--- pool, Refresh applies the model to it, and DeferralOrder guarantees that sequence
--- within one pass.
---
--- Deliberately not an InCombatLockdown guard on the mutation itself. The deferral queue carries
--- keys and no arguments, so a guard here could only drop the mutation, not delay it. Mutating the
--- model is a plain Lua table write and always legal; only applying it to a protected header is
--- restricted, and that guard belongs in Build and Refresh where the restricted calls are.
---
--- The role removal runs here rather than beside each caller because every mutation in this file
--- ends here: a preset, a drop, a slash command and a roster event all arrive at one place. It never
--- calls back into Apply, so the recursion that would otherwise follow cannot happen.
---
--- A burst of in-combat mutations is recorded in order and applied in a single pass on
--- PLAYER_REGEN_ENABLED, with nothing lost. The cost is that the model and the frames can disagree
--- for the length of a pull, which is why the slash commands say so and `/spotlights list` reads the
--- model.
local function Apply()
	AutoRemoveRoles()

	Private.Events.Request(DeferralKey.Build)
	Private.Events.Request(DeferralKey.Registry)

	-- Geometry follows registry in DeferralOrder, so a slot added here is anchored in the same pass
	-- it is created rather than on the next unrelated event.
	Private.Layout.Request()
end

--- Which slot already holds this player, if any. Checked on both keys because either can be the
--- only one we have: an offline-assigned slot has a name and no GUID, and two headers with the same
--- nameList would silently show the same person twice.
---@param guid string?
---@param name string?
---@return integer? index
local function FindOccupant(guid, name)
	local slots = Slots()

	if not slots then
		return nil
	end

	for i = 1, #slots do
		local slot = slots[i]

		if slot.kind == "player" then
			if guid and slot.guid == guid then
				return i
			end

			if name and slot.name == name then
				return i
			end
		end
	end

	return nil
end

local containerHooked = false

--- Grows the header pool to the configured slot count. Frame creation only: anchoring and
--- sizing belong to Private.Layout, and nameList is Refresh's job.
---
--- Split from Refresh so the two defer independently. DeferralOrder runs build before
--- registry, so combat starting between them cannot leave a nameList written to a header
--- that does not exist yet, and each re-queues only its own half.
local function Build()
	if Private.Events.DeferIfInCombat(DeferralKey.Build) then
		return
	end

	local slots = Slots()

	if not slots then
		return
	end

	local container = Private.Container.Get()

	if not containerHooked then
		containerHooked = true

		-- A header created while the container is hidden has no child at all: OnShow is what
		-- runs SecureGroupHeader_Update, and a header inside a hidden container never fires
		-- it. The state driver shows the container after the roster event that triggered it,
		-- so roster events alone always run too early. Hooking the container and deferring a
		-- frame lands after the children exist.
		--
		-- Safe in a way hooking a header would not be: the container is ours, plain and
		-- unprotected.
		container:HookScript("OnShow", Apply)
	end

	-- Seeded from the layout rather than left at the native default. Build runs before
	-- geometry in DeferralOrder, so without this every header is created at 72x36 and
	-- resized a step later -- one frame of visibly wrong geometry on the first pass.
	local layout = Private.Layout.GetConfig()
	local config = layout and Private.FrameConfig.Get(layout.frameWidth, layout.frameHeight)
		or Private.FrameConfig.Get()

	for i = 1, #slots do
		-- Re-checked inside the loop so a mid-pass combat start re-queues the whole pass rather than
		-- leaving it half applied.
		if Private.Events.DeferIfInCombat(DeferralKey.Build) then
			return
		end

		Private.SlotHeader.EnsureChild(
			Private.SlotHeader.Acquire(i, config.frameWidth, config.frameHeight)
		)
	end
end

--- Keeps a slot's stored name and GUID pointing at the same player.
---
--- Both directions, because either half can be missing. A roster-sourced slot has both; an
--- offline-assigned slot has only a name and picks up its GUID the first time the player appears.
--- A name can go stale on its own through a rename or realm transfer, which self-heals here into a
--- one-cycle blip rather than a permanently dead slot.
---
--- Only a roster-sourced name is ever written back. Private.Roster.GetName's second return enforces
--- that: a cache-sourced name is reassembled from a bare name and a realm, which is exactly what
--- SecureGroupHeaders will not match.
---@param slot SpotlightsSlot
local function SelfHeal(slot)
	if slot.kind ~= "player" then
		return
	end

	if not slot.guid then
		if slot.name then
			slot.guid = Private.Roster.GetGuid(slot.name)
		end

		return
	end

	local name, fromRoster = Private.Roster.GetName(slot.guid)

	if fromRoster and name ~= slot.name then
		slot.name = name
	end
end

--- Which slot each grid cell is currently showing, rebuilt by `ResolveCells` on every apply.
---
--- With gaps on this is the identity map. With gaps off it is the inverse of compaction, and it is
--- the difference between a drop landing where the user pointed and landing somewhere plausible.
---@type integer[]
local slotByCell = {}

--- The slot a grid cell is showing.
---
--- Cell and slot are the same number only while `allowGaps` is on, which is the default. With gaps
--- off, cells hold present players in slot order, so cell 2 can be showing slot 5 -- and anything
--- that reads a cell index off the screen and hands it to the model must come through here first.
---
--- Falls back to the identity when no apply has run yet: with no mapping there is no compaction to
--- undo.
---@param cell integer
---@return integer slot
function Private.Registry.SlotOfCell(cell)
	return slotByCell[cell] or cell
end

--- What each grid cell should hold. This is where `allowGaps` lives, and the reason it is here
--- rather than in Private.Layout: both modes use identical geometry. Headers are pinned to their
--- cells out of combat and never move again; only which name lands in which cell differs.
---
--- **Gaps on — geometry is identity.** Slot i is cell i forever. A departed player leaves an empty
--- cell and a spacer holds its position, so nothing ever moves out from under a click.
---
--- **Gaps off — compaction by content.** Cells are filled by present players in slot order, and
--- spacers collapse with the holes. Presence means roster presence, so a player who has left is
--- skipped.
---
--- Compaction cannot disturb the in-combat rejoin catch: Refresh is out-of-combat only, so no cell
--- is ever rewritten during a pull. A player who leaves mid-combat keeps their cell and the header
--- keeps scanning for them in both modes; compaction happens only after the fight.
---@param slots SpotlightsSlot[]
---@param layout SpotlightsLayoutConfig
---@return (string|false)[] byCell
local function ResolveCells(slots, layout)
	---@type (string|false)[]
	local byCell = {}

	table.wipe(slotByCell)

	if layout.allowGaps then
		for i = 1, #slots do
			local slot = slots[i]

			byCell[i] = slot.kind == "player" and slot.name or false
			slotByCell[i] = i
		end

		return byCell
	end

	local cell = 1

	for i = 1, #slots do
		local slot = slots[i]

		if slot.kind == "player" and slot.name and Private.Roster.GetGuid(slot.name) then
			byCell[cell] = slot.name
			slotByCell[cell] = i
			cell = cell + 1
		end
	end

	for i = cell, #slots do
		byCell[i] = false
	end

	return byCell
end

--- Writes one resolved cell onto its header.
---@param header Frame
---@param name string|false
---@param config table<string, any>
local function ApplySlot(header, name, config)
	local occupied = name ~= false

	-- Attributes before visibility. Every attribute write on a visible header runs a full
	-- synchronous roster scan, so writing them while hidden and then showing once is one scan
	-- instead of several.
	Private.SlotHeader.ApplyAttributes(
		header,
		occupied and name or nil,
		config.frameWidth,
		config.frameHeight
	)

	-- An occupied slot stays visible even while its player is absent. A hidden header early-outs
	-- before its roster scan, and that scan is the entire mechanism that catches a player rejoining
	-- mid-combat -- so hiding an empty-but-assigned slot would trade away the reason this
	-- architecture was chosen. Blank slots have nothing to catch and so cost nothing.
	--
	-- Show and Hide are legal here because Refresh is out-of-combat only. The resulting OnShow runs
	-- SecureGroupHeader_Update inside our tainted call, which measurably does not poison the
	-- header's later untainted updates.
	header:SetShown(occupied)

	-- A header hidden until a moment ago had no child, and OnShow has just created one. Build's own
	-- EnsureChild ran before that happened, so without this the first frame a slot becomes occupied
	-- would render unstyled with no attribute mirror installed. Idempotent.
	if occupied then
		Private.SlotHeader.EnsureChild(header)
	end
end

--- Applies the model to the headers. The only writer of `nameList` anywhere in the addon.
local function Refresh()
	if Private.Events.DeferIfInCombat(DeferralKey.Registry) then
		return
	end

	local slots = Slots()

	if not slots then
		return
	end

	Private.Roster.Rebuild()

	local config = Private.FrameConfig.Get()
	local layout = Private.Layout.GetConfig()

	if not layout then
		return
	end

	-- Self-heal before resolving, not during: compaction reads whether each slot's player is
	-- currently in the roster, and a stale name would be counted absent and collapsed away on the
	-- very pass that would have fixed it.
	for i = 1, #slots do
		SelfHeal(slots[i])
	end

	local byCell = ResolveCells(slots, layout)

	for i = 1, #slots do
		if Private.Events.DeferIfInCombat(DeferralKey.Registry) then
			return
		end

		local header = Private.SlotHeader.Get(i)

		if header then
			ApplySlot(header, byCell[i] or false, config)
		end
	end

	-- Headers past the configured count. Frames cannot be destroyed, so removing a slot leaves its
	-- header behind; sentinel and hide it. Costs nothing afterwards, because a hidden header
	-- early-outs in SecureGroupHeader_OnEvent before it scans anything.
	for i = #slots + 1, Private.SlotHeader.Count() do
		if Private.Events.DeferIfInCombat(DeferralKey.Registry) then
			return
		end

		local header = Private.SlotHeader.Get(i) --[[@as Frame]]

		Private.SlotHeader.ApplyAttributes(header, nil, config.frameWidth, config.frameHeight)
		header:Hide()
	end
end

---@param guid string?
---@param name string
---@param index integer?
---@return boolean ok, string? reason, integer? assignedTo
local function Assign(guid, name, index)
	local slots = Slots()

	if not slots then
		return false, Private.L.Registry.NotLoaded
	end

	local occupant = FindOccupant(guid, name)

	if occupant then
		return false, string.format(Private.L.Registry.Duplicate, name, occupant)
	end

	local layout = Private.Layout.GetConfig()
	local roles = layout and layout.autoRemoveRoles
	local role = guid and Private.Roster.GetRole(guid)

	-- Refused rather than left to the sweep in `Apply`, which would take the slot straight back out.
	-- The outcome is the same either way; what differs is that `/spotlights add` gets to say why
	-- instead of reporting a slot that is gone by the time the line is printed, and a drag that goes
	-- nowhere is explained rather than watched.
	if role and roles and roles[role] then
		return false, string.format(Private.L.Registry.RoleAutoRemoved, name)
	end

	---@type SpotlightsSlot
	local slot = { kind = "player", guid = guid, name = name }

	-- An explicit index **inserts**, pushing the rest of the grid down. Replace would silently
	-- discard whoever was already there, and a drop is a gesture people miss by an inch. Inserting
	-- cannot lose a slot to a misaimed drop, and the position the user pointed at is still where the
	-- player lands.
	local target = index and slots[index] and index or #slots + 1

	if target > #slots then
		slots[target] = slot
	else
		table.insert(slots, target, slot)
	end

	Apply()

	return true, nil, target
end

--- Assigns by name, resolving the GUID if the player is in the group.
---
--- A name with no GUID behind it is a legitimate state, not a failure: GetPlayerInfoByGUID only
--- goes GUID to name, so there is no way to obtain a GUID for someone not currently in the group.
--- The slot works regardless -- the name is what the header matches on -- and SelfHeal fills the
--- GUID in the first time they appear.
---@param name string exactly as the roster scan spells it
---@param index integer?
---@return boolean ok, string? reason, integer? assignedTo
function Private.Registry.AssignByName(name, index)
	return Assign(Private.Roster.GetGuid(name), name, index)
end

--- Assigns by GUID, which is what a drop and the options roster list both have.
---
--- `index` inserts at that position rather than replacing it; see `Assign`.
---
--- Refuses when only the client name cache knows the name, rather than storing a reassembled
--- `Name-Realm` the header would fail to match. Every front-end that produces a GUID sources it from
--- the current group, so this rejection should be unreachable -- hence loud rather than silent.
---@param guid string
---@param index integer?
---@return boolean ok, string? reason, integer? assignedTo
function Private.Registry.AssignByGuid(guid, index)
	local name, fromRoster = Private.Roster.GetName(guid)

	if not name or not fromRoster then
		return false, Private.L.Registry.NotInRoster
	end

	return Assign(guid, name, index)
end

--- Removes a slot entirely, shifting the ones after it up. Blanking is SetBlank; this is
--- for taking a cell out of the grid.
---@param index integer
---@return boolean ok, string? reason
function Private.Registry.Unassign(index)
	local slots = Slots()

	if not slots or not slots[index] then
		return false, string.format(Private.L.Registry.NoSuchSlot, index)
	end

	table.remove(slots, index)
	Apply()

	return true
end

--- Turns a slot into a user-placed spacer, or appends one when index is nil. The cell stays
--- in the grid and holds its position; only its occupant goes.
---@param index integer?
---@return boolean ok, string? reason
function Private.Registry.SetBlank(index)
	local slots = Slots()

	if not slots then
		return false, Private.L.Registry.NotLoaded
	end

	if index and not slots[index] then
		return false, string.format(Private.L.Registry.NoSuchSlot, index)
	end

	---@type SpotlightsSlot
	local slot = { kind = "blank" }

	slots[index or #slots + 1] = slot
	Apply()

	return true
end

--- Empties the grid: every player and every spacer.
---
--- Spacers go too, on the same grounds the leave-the-group clear takes them: a grid with its players
--- gone but its holes kept is not cleared, and the shape is a handful of clicks to lay out again.
---
--- Answers false on an already-empty grid rather than applying, so a caller can tell "nothing to do"
--- from "done" without counting slots itself.
---@return boolean cleared
function Private.Registry.Clear()
	local slots = Slots()

	if not slots or #slots == 0 then
		return false
	end

	table.wipe(slots)
	Apply()

	return true
end

--- Replaces the whole slot list, for the one caller that arrives with a list rather than an edit:
--- applying a roster preset.
---
--- Copied rather than stored by reference. The list handed in belongs to the preset library and has
--- to keep belonging to it -- assigning it directly would make every later edit of the grid an edit
--- of the preset.
---
--- GUIDs are resolved from the names here rather than carried over, because a preset names the same
--- people in every raid while their GUIDs are the ones it happened to see. A name is what the header
--- matches on, and `SelfHeal` fills the GUID back in the first time the player is in the group.
---@param slots SpotlightsSlot[]
---@return boolean ok, string? reason
function Private.Registry.SetSlots(slots)
	local current = Slots()

	if not current then
		return false, Private.L.Registry.NotLoaded
	end

	table.wipe(current)

	for i = 1, #slots do
		local slot = slots[i]

		-- Anything that is not a player is a spacer. `retired` is a header's state rather than a
		-- slot's, so it cannot legitimately be stored here and is not worth a second branch.
		if slot.kind == "player" and slot.name then
			current[i] = { kind = "player", name = slot.name, guid = Private.Roster.GetGuid(slot.name) }
		else
			current[i] = { kind = "blank" }
		end
	end

	Apply()

	return true
end

--- Reorders a slot. Insert-after-remove, so the slots between the two ends shift by one rather than
--- swapping -- dragging slot 5 to position 2 pushes 2, 3 and 4 down.
---@param from integer
---@param to integer
---@return boolean ok, string? reason
function Private.Registry.Move(from, to)
	local slots = Slots()

	if not slots or not slots[from] then
		return false, string.format(Private.L.Registry.NoSuchSlot, from)
	end

	if not slots[to] then
		return false, string.format(Private.L.Registry.NoSuchSlot, to)
	end

	if from == to then
		return true
	end

	table.insert(slots, to, table.remove(slots, from))
	Apply()

	return true
end

--- Forces every occupied header to re-scan the roster, by bouncing its nameList through the
--- sentinel and back.
---
--- Exposed as `/spotlights rescan` and deliberately wired to no event. It is the recovery path for
--- one unproven case: a spotlighted player who leaves and rejoins the group while in combat, if the
--- header's own scan does not pick them up. Wire it to PLAYER_REGEN_ENABLED only once that is known
--- to happen -- an unconditional bounce costs two full roster scans per slot and defeats the diff
--- guard the whole cost model rests on.
---@return integer rescanned
function Private.Registry.Rescan()
	if Private.Events.DeferIfInCombat(DeferralKey.Registry) then
		return 0
	end

	local slots = Slots()

	if not slots then
		return 0
	end

	local layout = Private.Layout.GetConfig()

	if not layout then
		return 0
	end

	local config = Private.FrameConfig.Get()

	-- Resolved rather than read straight off the slots. With gaps off, header i holds the i-th
	-- present player rather than slot i's, so bouncing `slots[i].name` through the sentinel would
	-- re-point half the grid at the wrong people until the next Refresh.
	local byCell = ResolveCells(slots, layout)
	local count = 0

	for i = 1, #slots do
		local name = byCell[i]
		local header = Private.SlotHeader.Get(i)

		if header and name then
			Private.SlotHeader.ApplyAttributes(header, nil, config.frameWidth, config.frameHeight)
			Private.SlotHeader.ApplyAttributes(header, name, config.frameWidth, config.frameHeight)

			count = count + 1
		end
	end

	return count
end

Private.Events.RegisterHandler(DeferralKey.Build, Build)
Private.Events.RegisterHandler(DeferralKey.Registry, Refresh)

--- Which kind of group the player was in the last time the roster changed.
---
--- A kind rather than a boolean because one set of slots serves both party and raid, and the two are
--- different lists in practice -- so converting between them is a leave as much as disbanding is.
---@return "none"|"party"|"raid"
local function GroupKind()
	if IsInRaid() then
		return "raid"
	end

	if IsInGroup() then
		return "party"
	end

	return "none"
end

--- What makes this setting safe, and the reason it is a remembered edge rather than a live test of
--- `GroupKind`. A bare "not in a group, so clear" would fire on the `PLAYER_ENTERING_WORLD` below and
--- wipe the user's entire configuration on every login, reload and reconnect.
---
--- Starting at `none` is correct: a session that begins outside a group has not left one, and a
--- session that begins inside one sees its first roster event as an arrival.
---@type "none"|"party"|"raid"
local lastGroupKind = "none"

--- Wipes every configured slot when the kind of group the player is in changes, if the setting says
--- to. Leaving, and converting in either direction, all count; arriving from nothing does not.
---
--- Everything, including spacers. The setting says "clear the roster" and a grid with its players
--- gone but its holes kept is not cleared; anyone who wants the shape back has the mover and an
--- empty grid.
---
--- Not combat-guarded, and does not need to be: wiping a table is plain Lua. The frames catch up
--- through the deferral queue like every other mutation in this file.
---
--- Announced, because a settings-driven deletion the user did not watch happen is indistinguishable
--- from data loss.
---@return boolean cleared
local function ClearOnLeave()
	local kind = GroupKind()
	local left = lastGroupKind ~= "none" and kind ~= lastGroupKind

	lastGroupKind = kind

	if not left then
		return false
	end

	local layout = Private.Layout.GetConfig()
	local slots = Slots()

	if not layout or not layout.clearOnLeave or not slots or #slots == 0 then
		return false
	end

	table.wipe(slots)
	Private.Utils.Print(Private.L.Registry.ClearedOnLeave)

	return true
end

--- Runs the role removal for a caller that just changed the setting, so ticking Healer acts on the
--- grid already on screen rather than at the next roster event.
---@return boolean removed
function Private.Registry.EnforceAutoRemoveRoles()
	if not AutoRemoveRoles() then
		return false
	end

	Apply()

	return true
end

Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	ClearOnLeave()
	Apply()
end)

-- A role change moves nobody in or out of the group, so nothing else in this file hears it. Without
-- it, a spotlighted damage dealer who switches to healing with Healer set to be removed keeps their
-- slot until the next membership change.
Private.Events.RegisterEvent("PLAYER_ROLES_ASSIGNED", function()
	if AutoRemoveRoles() then
		Apply()
	end
end)

-- Deliberately **not** wired to the clear. This fires on login, on every loading screen and on
-- every reload, none of which is anyone leaving anything.
Private.Events.RegisterEvent("PLAYER_ENTERING_WORLD", Apply)

Private.Events.RegisterEvent("PLAYER_LOGIN", function()
	-- Rebuild the roster before anything asks for it, and unconditionally: it is plain table work,
	-- so it runs even under lockdown. That makes a build blocked by a mid-combat reload one pass on
	-- PLAYER_REGEN_ENABLED rather than a scan and then a build.
	Private.Roster.Rebuild()
	Apply()
end)

--- Reports a mutation, and says so when the frames will lag the model. The model is always
--- current; only the headers wait for combat to end.
---@param ok boolean
---@param reasonOrMessage string?
local function Report(ok, reasonOrMessage)
	if reasonOrMessage then
		Private.Utils.Print(reasonOrMessage)
	end

	if ok and InCombatLockdown() then
		Private.Utils.Print(Private.L.Registry.Deferred)
	end
end

Private.SlashCommands.Register("add", "Add", function(args)
	local L = Private.L.Registry
	local input = string.match(args, "^%s*(.-)%s*$")

	if input == "" then
		Private.Utils.Print(L.AddUsage)

		return
	end

	local name = Private.Roster.Resolve(input)

	if not name then
		local _, skipped = Private.Roster.GetStats()

		Private.Utils.Printf(skipped > 0 and L.IdentitySecret or L.Unknown, input, skipped)

		return
	end

	local ok, reason, assignedTo = Private.Registry.AssignByName(name)

	Report(ok, reason or string.format(L.Assigned, assignedTo or 0, name))
end)

Private.SlashCommands.Register("list", "List", function()
	local L = Private.L.Registry
	local slots = Private.Registry.GetSlots()

	if #slots == 0 then
		Private.Utils.Print(L.Empty)

		return
	end

	local scanned, skipped = Private.Roster.GetStats()

	Private.Utils.Printf(L.ListHeader, #slots, scanned, skipped)

	for i = 1, #slots do
		local slot = slots[i]

		if slot.kind ~= "player" then
			Private.Utils.Printf(L.ListBlank, i)
		else
			-- The token proves the *header* matched, and it comes from our own UnitTokenFromGUID
			-- rather than the child's tainted `unit` attribute.
			local token = slot.guid and Private.Roster.GetToken(slot.guid)

			Private.Utils.Printf(
				L.ListPlayer,
				i,
				tostring(slot.name),
				token or (slot.guid and L.Absent or L.Unresolved)
			)
		end
	end
end)

Private.SlashCommands.Register("rescan", "Rescan", function()
	Private.Utils.Printf(Private.L.Registry.Rescanned, Private.Registry.Rescan())
end)
