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

--- Wraps a listener so it runs at most once per `interval`, on the leading edge and the trailing one.
---
--- The leading call is what keeps a lone roster change immediate: a single join has to land now, not in
--- a second. The trailing call is what makes the throttle safe -- a burst whose last event is dropped
--- leaves its listener showing the state before it, and a roster burst is exactly the case where the
--- last event is the true one.
---
--- `C_Timer` rather than the dispatcher frame, against this file's own preference: that frame exists to
--- fold requests within one frame and holds no per-key deadline. One timer per burst at 1Hz is not the
--- cost that comment was written about.
---
--- Arguments are not forwarded. Every listener this is meant for reads current state rather than the
--- event's payload, and a trailing call could only carry the stale arguments of the event that
--- scheduled it.
---@param interval number seconds
---@param handler fun()
---@return fun() listener
function Private.Events.Throttled(interval, handler)
	--- One interval in the past, so the first call is always a leading one. Zero would not do it:
	--- `GetTime` is seconds since the client started, and an addon loading into an already-running
	--- client is not the only case -- at login it can legitimately be under one.
	local last = -interval
	local scheduled = false

	local function Fire()
		last = GetTime()
		scheduled = false

		handler()
	end

	return function()
		-- Already waiting on a trailing call, which will read the state this event produced.
		if scheduled then
			return
		end

		local remaining = last + interval - GetTime()

		if remaining <= 0 then
			Fire()

			return
		end

		scheduled = true

		C_Timer.After(remaining, Fire)
	end
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
