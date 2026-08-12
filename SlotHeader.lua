---@type string, Spotlights
local _, Private = ...

---@class SpotlightsSlotHeader
Private.SlotHeader = {}

local SENTINEL = Private.Enum.NameListSentinel

--- Every attribute write on a *visible* header runs SecureGroupHeader_Update synchronously, which
--- scans the whole roster with a GetRaidRosterInfo C call per member. There is no throttle or dirty
--- flag anywhere in that file, so comparing before writing is a correctness-shaped performance rule.
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
--- entire raid into this one slot. Blank slots get the sentinel.
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

	-- No `auraContainerTemplate`, deliberately. The attribute makes SecureGroupHeaders.lua:111-112
	-- build exactly **one** container per child, parented straight to the unit button -- wrong twice
	-- over. Four independently positioned displays need four independently movable rectangles, and a
	-- container's rect is the only transform above the aura button's access restriction, so they
	-- cannot share one. And a container built here is built for every spotlight at header-creation
	-- time, where `Private.Auras` builds one only for a switched-on display on a spotlight with a
	-- unit.
	SetAttributeIfChanged(header, "nameList", nameList or SENTINEL)
end

--- Pushes new child dimensions into a header. Out of combat only.
---
--- Only affects children created *after* this call -- initialConfigFunction runs once per child, at
--- creation. Existing children are resized by re-running ApplyChildConfig, which Layout does in the
--- same pass.
---
--- Kept separate from ApplyAttributes so a geometry change need not know the header's current
--- nameList to avoid clobbering it.
---@param header Frame
---@param width number
---@param height number
function Private.SlotHeader.ApplySize(header, width, height)
	SetAttributeIfChanged(header, "initialConfigFunction", BuildInitialConfig(width, height))
end

--- Resizes an existing child. Out of combat only, and safe to re-run.
---
--- initialConfigFunction sizes a child at creation and never runs again, so a width or height
--- change must reach existing children some other way -- which is all this is. Every region in the
--- template is anchored relatively, so nothing else needs telling the frame grew.
---@param child SpotlightsUnitFrame
function Private.SlotHeader.ApplyChildConfig(child)
	local size = Private.FrameConfig.Get()

	child:SetSize(size.frameWidth, size.frameHeight)

	-- The one region whose anchor is computed rather than declared, so also the one a resize
	-- invalidates.
	child:UpdateTempMaxHealthLoss()

	-- The other, one layer out. An aura bar is stored as a fraction of the spotlight, so its
	-- anchor's rect is recomputed here or never -- the display is nested under a frozen aura button.
	Private.Auras.ApplyChild(child)
end

--- One-time out-of-combat setup for a header's child.
---@param child SpotlightsUnitFrame
function Private.SlotHeader.InitChild(child)
	Private.SlotHeader.ApplyChildConfig(child)

	child:CreateAbsorbBar()

	--- The name's own frame. Created here rather than lazily because everything about it is a protected
	--- call -- `SetAllPoints`, `SetFrameLevel` and `SetFrameStrata` on a child of a secure unit button --
	--- and this is the one path guaranteed to be out of combat.
	---
	--- The strata is requested rather than applied inline: the sweep is keyed and idempotent, so a header
	--- rebuild that initialises several children costs one pass, and a child created before the database
	--- loaded still gets its strata on the next one.
	Private.NameStyle.EnsureLayer(child)
	Private.NameStyle.Request()

	--- Hooked rather than set. `OnEnter` and `OnLeave` are wired to Blizzard globals in the template --
	--- script attributes take global function names -- and `UnitFrame_OnEnter` is what puts the unit
	--- tooltip up, so replacing them would trade the name setting for the tooltip.
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

	-- Left-click target, right-click menu, wired by hand rather than through SecureUnitButton_OnLoad.
	-- Two of the three attributes it sets are hazards here.
	--
	-- `menu-function` is invoked as self:ExecuteAttribute("menu-function", ...)
	-- (SecureTemplates.lua:262-266), running the stored function with the taint of whoever stored it.
	-- Set from our code, every menu entry reaching a protected API fails (SetRaidTarget from the raid
	-- marker submenu is the one users hit within seconds). `togglemenu` builds the same RAID_PLAYER
	-- popup entirely inside SecureTemplates (:269-319) with no tainted value in the call.
	--
	-- `unit` is the header's to own. Writing it ourselves taints a value Blizzard assigned securely,
	-- and configureChildren overwrites it on the next update anyway. Leaving it alone also keeps
	-- click-casting addons working.
	child:RegisterForClicks("AnyUp")
	child:SetAttribute("*type1", "target")
	child:SetAttribute("*type2", "togglemenu")

	-- No UnregisterAllEvents needed. A frame from the old template arrived with **21 global events**
	-- already registered by CompactUnitFrame_OnLoad, none with a reader once its OnEvent was
	-- replaced, each putting our tainted Lua into a dispatch Blizzard's compact frames registered
	-- for. Ours arrives with none.
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
	-- SecureRaidGroupHeaderTemplate is SecureGroupHeaderTemplate plus showRaid = true, so raid-only
	-- gating is free: GetGroupHeaderType returns no kind outside a raid and the child hides itself.
	-- showParty and showSolo stay unset -- nil is falsy there.
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

--- Initialises the header's child if it exists and has not been set up yet.
---
--- Creating a header while the container is hidden does **not** create a child: OnShow runs
--- SecureGroupHeader_Update, and a header inside a hidden container never fires it. So a spotlight
--- built while out of a raid has no child1 at Create time; the child appears later when the state
--- driver shows the container -- by which point nothing would have applied the config, hidden the
--- unused regions, or installed the attribute mirror. The frame renders unstyled and `unit` is never
--- mirrored, which makes UnitFrame_UpdateTooltip pass nil to C_TooltipInfo.GetUnit.
---
--- Idempotent, so safe to call on every build pass.
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
--- Geometry is deliberately *not* re-applied to an existing header. initialConfigFunction only runs
--- at child-creation time, so rewriting it later changes nothing about an existing child -- a resize
--- reaches the child through ApplyChildConfig instead. Writing it anyway would cost a full roster
--- scan per header for no effect.
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

--- The *cell* whose live spotlight is under the cursor, or nil.
---
--- A cell, not a slot: the pool is indexed by cell, and with `allowGaps` off a cell shows whichever
--- slot compaction put there. Callers acting on the model must pass this through
--- `Private.Registry.SlotOfCell`.
---
--- A drop target while the grid shows real players. `Private.Preview` answers for empty cells, and
--- the two can never both answer: a preview is shown exactly when its cell's child is not visible.
---
--- Reads geometry and visibility off a protected frame, which is not a protected call -- nothing
--- here writes to a header or its child.
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

--- Runs `callback` over every initialised child in the pool. For changes that apply to every
--- spotlight at once, such as an option table the environment has invalidated.
---
--- The cell index is passed alongside, for callers that must *name* the spotlight rather than only
--- act on it. It is the pool index and therefore the cell, not the slot -- with `allowGaps` off the
--- two differ, and a caller acting on the model must put it through `Private.Registry.SlotOfCell`.
---
--- Second argument rather than a second function, because the alternative is every such caller
--- rewriting this walk, which knows two things worth not duplicating: that `child1` may be absent
--- and that an uninitialised child must not be touched.
---@param callback fun(child: SpotlightsUnitFrame, cell: integer)
function Private.SlotHeader.ForEachChild(callback)
	for i = 1, #pool do
		local child = pool[i]:GetAttribute("child1") --[[@as SpotlightsUnitFrame?]]

		if child and child.spotlightsInitialised then
			callback(child, i)
		end
	end
end
