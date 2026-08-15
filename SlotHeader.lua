---@type string, Spotlights
local _, Private = ...

---@class SpotlightsSlotHeader
Private.SlotHeader = {}

local SENTINEL = Private.Enum.NameListSentinel

--- Every attribute write on a *visible* header runs SecureGroupHeader_Update synchronously, which
--- scans the whole roster with a C call per member. There is no throttle or dirty flag anywhere in
--- that file, so comparing before writing is a correctness-shaped performance rule.
---@param header Frame
---@param name string
---@param value any
local function SetAttributeIfChanged(header, name, value)
	if header:GetAttribute(name) == value then
		return
	end

	header:SetAttribute(name, value)
end

--- initialConfigFunction is compiled and run as a restricted snippet, so it must be a *string*. It
--- must set width and height, because configureChildren reads unitButton:GetWidth() immediately
--- afterwards to size the header.
---@param width number
---@param height number
---@return string
local function BuildInitialConfig(width, height)
	return string.format("self:SetWidth(%d) self:SetHeight(%d)", width, height)
end

--- Applies the attribute set for one slot. Out of combat only.
---
--- groupFilter and roleFilter must stay nil, and nameList must never *become* nil: with all three
--- unset, SecureGroupHeader_Update falls back to groupFilter "1,2,3,4,5,6,7,8" and renders the
--- entire group into this one slot -- a party included, since every party member reports subgroup 1.
--- Blank slots get the sentinel.
---@param header Frame
---@param nameList string?
---@param width number
---@param height number
function Private.SlotHeader.ApplyAttributes(header, nameList, width, height)
	SetAttributeIfChanged(header, "template", "SpotlightsUnitFrameTemplate")
	SetAttributeIfChanged(header, "templateType", "Button")
	SetAttributeIfChanged(header, "sortMethod", "NAMELIST")
	SetAttributeIfChanged(header, "point", "TOPLEFT")
	SetAttributeIfChanged(header, "initialConfigFunction", BuildInitialConfig(width, height))

	-- The template brings `showRaid`; this is the other half of "any group we render for", and the two do
	-- not overlap because GetGroupHeaderType tests the raid first (SecureGroupHeaders.lua:266-272).
	--
	-- `showPlayer` and `showSolo` stay unset, which starts the party walk at index 1 rather than 0 -- so the
	-- player is never a spotlight -- and leaves a solo player with no kind at all.
	SetAttributeIfChanged(header, "showParty", true)

	-- No `auraContainerTemplate`, deliberately: it builds exactly one container per child at
	-- header-creation time (SecureGroupHeaders.lua:111-112). Four independently positioned displays need
	-- four rectangles, a container's rect being the only transform above the aura button's access
	-- restriction, and `Private.Auras` builds one only for a switched-on display on an occupied spotlight.
	SetAttributeIfChanged(header, "nameList", nameList or SENTINEL)
end

--- Pushes new child dimensions into a header. Out of combat only.
---
--- Only affects children created *after* this call, since initialConfigFunction runs once per child;
--- existing ones are resized by ApplyChildConfig, which Layout runs in the same pass. Kept separate from
--- ApplyAttributes so a geometry change need not know the header's current nameList.
---@param header Frame
---@param width number
---@param height number
function Private.SlotHeader.ApplySize(header, width, height)
	SetAttributeIfChanged(header, "initialConfigFunction", BuildInitialConfig(width, height))
end

--- Resizes an existing child, since initialConfigFunction never runs again after creation. Out of combat
--- only, and safe to re-run.
---@param child SpotlightsUnitFrame
function Private.SlotHeader.ApplyChildConfig(child)
	local size = Private.FrameConfig.Get()

	child:SetSize(size.frameWidth, size.frameHeight)

	-- The one region whose anchor is computed rather than declared, so also the one a resize invalidates.
	child:UpdateTempMaxHealthLoss()

	-- The other, one layer out: an aura bar is stored as a fraction of the spotlight, and its display is
	-- nested under a frozen aura button, so the rect is recomputed here or never.
	Private.Auras.ApplyChild(child)
end

--- One-time out-of-combat setup for a header's child.
---@param child SpotlightsUnitFrame
function Private.SlotHeader.InitChild(child)
	Private.SlotHeader.ApplyChildConfig(child)

	child:CreateAbsorbBar()

	--- Created here rather than lazily because every call on a child of a secure unit button is protected
	--- and this path is guaranteed out of combat. The strata is requested rather than applied inline, so
	--- several children cost one keyed pass and a child created before the database loaded still gets one.
	Private.NameStyle.EnsureLayer(child)
	Private.NameStyle.Request()

	--- Hooked rather than set: the template wires `OnEnter` to `UnitFrame_OnEnter`, which is what puts the
	--- unit tooltip up, so replacing it would trade the name setting for the tooltip.
	child:HookScript("OnEnter", function(self)
		self.spotlightsHovered = true

		self:UpdateNameVisibility()
	end)

	child:HookScript("OnLeave", function(self)
		self.spotlightsHovered = false

		self:UpdateNameVisibility()
	end)

	-- After CreateAbsorbBar, which is what there is to apply the showAbsorb setting to.
	child:UpdateTexture()

	-- Wired by hand rather than through SecureUnitButton_OnLoad, two of whose three attributes are hazards.
	--
	-- `menu-function` runs the stored function with the taint of whoever stored it
	-- (SecureTemplates.lua:262-266), so set from our code every menu entry reaching a protected API fails.
	-- `togglemenu` builds the same RAID_PLAYER popup entirely inside SecureTemplates (:269-319).
	--
	-- `unit` is the header's to own: writing it taints a value Blizzard assigned securely, and
	-- configureChildren overwrites it on the next update anyway.
	child:RegisterForClicks("AnyUp")
	child:SetAttribute("*type1", "target")
	child:SetAttribute("*type2", "togglemenu")

	-- No UnregisterAllEvents needed: ours arrives with none, where a CompactUnitFrame_OnLoad frame arrived
	-- with 21 global registrations putting our tainted Lua into dispatches Blizzard's own frames share.
	child:SetScript("OnEvent", child.OnEvent)
	child:RegisterGlobalEvents()

	child:HookScript("OnAttributeChanged", function(self, name, value)
		if name ~= "unit" then
			return
		end

		self:OnUnitAttributeChanged(value)
	end)

	-- The hook only fires on future writes, and the header may already have assigned a unit while
	-- creating the child.
	child:OnUnitAttributeChanged(child:GetAttribute("unit"))
end

--- Creates one slot header, pinned by the caller. Out of combat only: CreateFrame is legal in
--- combat but SetAttribute, SetPoint and Show on a protected frame are not.
---@param index integer
---@param parent Frame
---@param nameList string?
---@param width number
---@param height number
---@return Frame
local function CreateHeader(index, parent, nameList, width, height)
	-- SecureRaidGroupHeaderTemplate is SecureGroupHeaderTemplate plus showRaid; ApplyAttributes adds
	-- `showParty`. Outside a group GetGroupHeaderType returns no kind and the child hides itself.
	local header = CreateFrame(
		"Frame",
		"SpotlightsSlotHeader" .. index,
		parent,
		"SecureRaidGroupHeaderTemplate"
	)

	Private.SlotHeader.ApplyAttributes(header, nameList, width, height)

	-- OnShow is wired straight to SecureGroupHeader_Update in XML, which creates child1.
	header:Show()

	Private.SlotHeader.EnsureChild(header)

	return header
end

--- Initialises the header's child if it exists and has not been set up yet. Idempotent, so safe to call on
--- every build pass.
---
--- Creating a header while the container is hidden does **not** create a child, because the child is made
--- by the OnShow that never fires. It appears later when the state driver shows the container, so without
--- this pass the frame would render unstyled with `unit` never mirrored.
---@param header Frame
---@return boolean initialised
function Private.SlotHeader.EnsureChild(header)
	local child = header:GetAttribute("child1") --[[@as SpotlightsUnitFrame?]]

	if not child or child.spotlightsInitialised then
		return false
	end

	child.spotlightsInitialised = true

	Private.SlotHeader.InitChild(child)

	return true
end

--- The header pool, indexed by slot. Contiguous, because Acquire is only ever called over 1..#slots.
--- Headers are never released: WoW cannot destroy a frame, so a slot the user removes leaves its
--- header behind to reuse.
---@type Frame[]
local pool = {}

--- The header for a slot index, or nil if that slot has never been built.
---@param index integer
---@return Frame?
function Private.SlotHeader.Get(index)
	return pool[index]
end

--- How many headers exist -- a high-water mark, not the slot count. The gap between the two is what
--- Registry.Refresh has to sentinel and hide.
---@return integer
function Private.SlotHeader.Count()
	return #pool
end

--- The header for a slot index, created on first use. Out of combat only.
---
--- Geometry is deliberately *not* re-applied to an existing header: initialConfigFunction only runs at
--- child-creation time, so rewriting it would cost a full roster scan per header for no effect.
---@param index integer
---@param width number
---@param height number
---@return Frame
function Private.SlotHeader.Acquire(index, width, height)
	local header = pool[index]

	if header then
		return header
	end

	header = CreateHeader(index, Private.Container.Get(), nil, width, height)
	pool[index] = header

	return header
end

--- The *cell* whose live spotlight is under the cursor, or nil. A cell, not a slot: with `allowGaps` off a
--- cell shows whichever slot compaction put there, so callers acting on the model must pass this through
--- `Private.Registry.SlotOfCell`.
---
--- `Private.Preview` answers for empty cells, and the two can never both answer. Reading geometry and
--- visibility off a protected frame is not a protected call.
---@return integer? cell
function Private.SlotHeader.CellUnderCursor()
	for i = 1, #pool do
		local child = pool[i]:GetAttribute("child1") --[[@as SpotlightsUnitFrame?]]

		if child and Private.Utils.IsCursorOver(child) then
			return i
		end
	end

	return nil
end

--- Runs `callback` over every initialised child in the pool, for changes that apply to every spotlight at
--- once. The walk knows two things worth not duplicating: `child1` may be absent, and an uninitialised
--- child must not be touched.
---
--- The index passed alongside is the cell, not the slot -- with `allowGaps` off the two differ, and a
--- caller acting on the model must put it through `Private.Registry.SlotOfCell`.
---@param callback fun(child: SpotlightsUnitFrame, cell: integer)
function Private.SlotHeader.ForEachChild(callback)
	for i = 1, #pool do
		local child = pool[i]:GetAttribute("child1") --[[@as SpotlightsUnitFrame?]]

		if child and child.spotlightsInitialised then
			callback(child, i)
		end
	end
end
