---@type string, Spotlights
local _, Private = ...

---@class SpotlightsEvents
Private.Events = {}

local DeferralOrder = Private.Enum.DeferralOrder

---@type table<string, fun()>
local handlers = {}

--- Coalesced within a single frame.
---@type table<string, boolean>
local throttled = {}

--- Held until PLAYER_REGEN_ENABLED.
---@type table<string, boolean>
local deferred = {}

---@type table<string, fun(...)[]>
local listeners = {}

--- Runs the handler for a key, if one is registered. A key with no handler is not an error: units
--- land in dependency order and a request may outlive its owner.
---@param key string
local function Run(key)
	local handler = handlers[key]

	if handler then
		handler()
	end
end

--- Drains a pending set in DeferralOrder, then anything outside that order arbitrarily. Clearing
--- the key before running lets a handler re-request itself for the next pass without being
--- swallowed by this one.
---@param pending table<string, boolean>
local function Drain(pending)
	for i = 1, #DeferralOrder do
		local key = DeferralOrder[i]

		if pending[key] then
			pending[key] = nil
			Run(key)
		end
	end

	for key in pairs(pending) do
		pending[key] = nil
		Run(key)
	end
end

--- Frame-based throttle rather than C_Timer: OnUpdate only runs while shown, so a burst of
--- requests costs one pass next frame and no timer objects. Deliberately unparented -- a queue
--- parented to UIParent would stall while anything hides it (cinematic, pet battle).
local dispatcher = CreateFrame("Frame")
dispatcher:Hide()
dispatcher:SetScript("OnUpdate", function(self)
	self:Hide()
	Drain(throttled)
end)

local bus = CreateFrame("Frame")
bus:SetScript("OnEvent", function(_, event, ...)
	local list = listeners[event]

	if not list then
		return
	end

	for i = 1, #list do
		list[i](...)
	end
end)

--- Registers the function a deferral key dispatches to. One handler per key; the owning module
--- registers its own at load.
---@param key string
---@param handler fun()? nil clears the key
function Private.Events.RegisterHandler(key, handler)
	handlers[key] = handler
end

--- The handler currently registered for a key, if any. Lets a caller swap a handler and put the
--- original back.
---@param key string
---@return fun()?
function Private.Events.GetHandler(key)
	return handlers[key]
end

--- Requests that `key` run on the next frame. Idempotent within a frame, so callers may fire it
--- per roster event without counting.
---@param key string
function Private.Events.Request(key)
	throttled[key] = true
	dispatcher:Show()
end

--- Holds `key` until combat ends.
---@param key string
function Private.Events.QueueOOC(key)
	deferred[key] = true
end

--- The guard every combat-restricted entry point opens with:
---
---     if Private.Events.DeferIfInCombat(key) then return end
---
--- Loops over multiple slots should call it again inside the loop, so a mid-pass combat start
--- re-queues the whole pass instead of leaving it half applied.
---@param key string
---@return boolean deferred
function Private.Events.DeferIfInCombat(key)
	if InCombatLockdown() then
		deferred[key] = true

		return true
	end

	return false
end

--- Subscribes to a game event on the shared bus. Frame-scoped UNIT_* events do not belong here
--- -- those are registered per unit frame.
---@param event string
---@param listener fun(...)
function Private.Events.RegisterEvent(event, listener)
	local list = listeners[event]

	if not list then
		list = {}
		listeners[event] = list
		bus:RegisterEvent(event)
	end

	list[#list + 1] = listener
end

--- Whether anything is waiting on combat to end. Diagnostics only.
---@return boolean
function Private.Events.HasDeferredWork()
	return next(deferred) ~= nil
end

Private.Events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	Drain(deferred)
end)
