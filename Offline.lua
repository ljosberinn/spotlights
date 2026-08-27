---@type string, Spotlights
local _, Private = ...

---@class SpotlightsOffline
Private.Offline = {}

local DeferralKey = Private.Enum.DeferralKey

--- Seconds between sweep requests while anyone is offline. Enough for a threshold whose smallest step is
--- thirty, and it also makes a mid-wait setting change act on the next tick for free.
local TICK_INTERVAL = 1

--- guid -> `GetTime()` when we first observed them offline.
---
--- **Never persisted**: `GetTime` is seconds since the client started, so a stored stamp means nothing in
--- the next session. Someone found offline by the login scan is stamped then and gets the full delay
--- again, which is what keeps a mid-raid reload from blanking half the grid.
---@type table<string, number>
local offlineSince = {}

---@type FunctionContainer?
local ticker

--- How long we have observed a player offline, or nil when they are not tracked.
---@param guid string
---@return number? seconds
function Private.Offline.SecondsOffline(guid)
	local since = offlineSince[guid]

	if not since then
		return nil
	end

	return GetTime() - since
end

--- One ticker rather than a `C_Timer.After` per disconnect, which would leave stale timers behind a
--- setting change and create twenty objects when a raid drops at once.
---
--- Gated on the setting as well as the map, so a group with a permanently offline member and the setting
--- at never does not schedule a sweep every second forever.
local function UpdateTicker()
	local layout = Private.Layout.GetConfig()
	local armed = layout ~= nil
		and layout.offlineBlankDelay ~= Private.Enum.OfflineBlankNever
		and next(offlineSince) ~= nil

	if armed then
		if not ticker then
			ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
				Private.Events.Request(DeferralKey.Offline)
			end)
		end

		return
	end

	if ticker then
		ticker:Cancel()

		ticker = nil
	end
end

--- Stamps or clears one player.
---@param guid string
---@param connected boolean
---@return boolean changed
local function Observe(guid, connected)
	if connected then
		if not offlineSince[guid] then
			return false
		end

		offlineSince[guid] = nil

		return true
	end

	if offlineSince[guid] then
		return false
	end

	offlineSince[guid] = GetTime()

	return true
end

--- Re-reads the whole group. `UNIT_CONNECTION` never fires retroactively, so this is the half that finds
--- someone already offline when we arrive, and the half that drops a stamp for someone the roster no
--- longer answers for.
---
--- No secret guard: `UnitIsConnected` is documented never secret, which
--- `SpotlightsUnitFrameMixin:UpdateHealthColor` already relies on, and the roster drops every member whose
--- identity was.
---@return boolean changed
local function Scan()
	local roster = Private.Roster.List()
	local changed = false

	---@type table<string, boolean>
	local present = {}

	for i = 1, #roster do
		local guid = roster[i].guid
		local token = Private.Roster.GetToken(guid)

		present[guid] = true

		-- No token, no tracking: only a group member the client can name a unit for can be read as offline.
		changed = Observe(guid, not token or UnitIsConnected(token)) or changed
	end

	-- `pairs` is legal because every GUID in here came from the roster, which drops the secret ones.
	for guid in pairs(offlineSince) do
		if not present[guid] then
			offlineSince[guid] = nil
			changed = true
		end
	end

	return changed
end

--- Requests the sweep whenever the map moved, so a disconnect under `instantly` acts on the next frame
--- rather than waiting up to a second for the ticker.
---@param changed boolean
local function Settle(changed)
	if changed then
		Private.Events.Request(DeferralKey.Offline)
	end

	UpdateTicker()
end

--- Re-decides whether the ticker should run, for a caller that changed the setting under it.
function Private.Offline.Reevaluate()
	UpdateTicker()
end

--- The other half of detection, and the only one that catches the transition itself. On the shared bus
--- despite `RegisterEvent`'s note about UNIT_* events: that guards against a *frame-scoped* registration,
--- which wants one unit's filter, where this is roster-wide and unfiltered.
Private.Events.RegisterEvent("UNIT_CONNECTION", function(unit)
	local guid = unit and UnitGUID(unit)

	-- Guarded before the lookup, since comparing a secret is itself an error.
	if not guid or issecretvalue(guid) then
		return
	end

	-- Only a member the roster scan admitted is tracked; the second return is what tells a group member
	-- from someone the client name cache merely remembers.
	local _, fromRoster = Private.Roster.GetName(guid)

	if not fromRoster then
		return
	end

	Settle(Observe(guid, UnitIsConnected(unit)))
end)

Private.Events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	Settle(Scan())
end)

Private.Events.RegisterEvent("PLAYER_LOGIN", function()
	-- Rebuilt here rather than relied on: this file loads before `Registry.lua`, whose own login listener
	-- does the same one line before it applies, so nothing has scanned the group yet and the scan below
	-- would find nobody to stamp. Plain table work, and idempotent.
	Private.Roster.Rebuild()
	Settle(Scan())
end)
