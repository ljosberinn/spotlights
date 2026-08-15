---@type string, Spotlights
local addonName, Private = ...

Private.L = {}

---@class SpotlightsSlashCommands
Private.SlashCommands = {}

---@type table<string, SpotlightsSlashCommand>
local commands = {}

---@type string[]
local ordered = {}

--- Registers a `/spotlights <name>` subcommand. The description is a key in `L.SlashCommands` rather than a
--- resolved string, because commands register at file-load while the locale tables populate later.
---@param name string
---@param descriptionKey string
---@param handler fun(args: string)
function Private.SlashCommands.Register(name, descriptionKey, handler)
	if commands[name] == nil then
		ordered[#ordered + 1] = name
		table.sort(ordered)
	end

	commands[name] = {
		name = name,
		descriptionKey = descriptionKey,
		handler = handler,
	}
end

local function PrintUsage()
	local L = Private.L.SlashCommands

	Private.Utils.Print(L.Usage)

	for i = 1, #ordered do
		local command = commands[ordered[i]]

		Private.Utils.Printf("  |cffffd100/spotlights %s|r - %s", command.name, L[command.descriptionKey])
	end
end

--- The engine resolves slash handlers through these globals, so they are the one unavoidable
--- exception to the no-globals rule alongside XML mixin tables.
SLASH_SPOTLIGHTS1 = "/spotlights"

SlashCmdList["SPOTLIGHTS"] = function(message)
	local name, args = string.match(message or "", "^(%S*)%s*(.-)$")
	local command = name and commands[string.lower(name)]

	if not command then
		PrintUsage()

		return
	end

	command.handler(args or "")
end

Private.SlashCommands.Register("help", "Help", PrintUsage)

--- Redraws every spotlight after a zone change, where a unit's health, range and target state can all have
--- moved without an event reaching us. No combat guard: every updater writes a region of a frame we own.
local function RefreshConfig()
	Private.SlotHeader.ForEachChild(function(child)
		child:UpdateAll()
	end)
end

Private.Events.RegisterHandler(Private.Enum.DeferralKey.Config, RefreshConfig)

--- **Requested rather than run inline: a taint fix, not a throttling nicety.** PLAYER_ENTERING_WORLD is
--- dispatched to every frame registered for it, and Blizzard's compact frames rebuild themselves there.
--- Running UpdateAll inside that dispatch tainted them -- measured as CompactRaidGroup1Member1 throwing on
--- its own secret values after a loading screen, with no spotlights configured. Request defers past it.
local function RequestConfigRefresh()
	Private.Events.Request(Private.Enum.DeferralKey.Config)
end

Private.Events.RegisterEvent("PLAYER_ENTERING_WORLD", RequestConfigRefresh)
Private.Events.RegisterEvent("ZONE_CHANGED_NEW_AREA", RequestConfigRefresh)

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	-- The one place SpotlightsSaved is read or written. Everything downstream goes through
	-- Private.DB, so the global is a serialisation detail rather than an interface.
	local db, fresh = Private.Migration.Run(SpotlightsSaved)

	SpotlightsSaved = db
	Private.DB = db

	do
		local iconTexture = C_AddOns.GetAddOnMetadata(addonName, "IconTexture")

		LibStub("LibDBIcon-1.0"):Register(addonName, LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
			type = "launcher",
			text = addonName,
			icon = iconTexture,
			--- LibDBIcon forwards the button it registered `anyUp` for, so a right-click is ours to route.
			OnClick = function(_, button)
				if button == "RightButton" then
					Private.Options.SelectTab("roster")

					return
				end

				Private.Options.SetShown()
			end,
			OnTooltipShow = function(tooltip)
				tooltip:AddLine(addonName)
				tooltip:AddLine(Private.L.Settings.ClickToOpenSettings, 1, 1, 1)
				tooltip:AddLine(Private.L.Settings.RightClickToOpenRoster, 1, 1, 1)
			end,
		}), db.minimap)

		AddonCompartmentFrame:RegisterAddon({
			text = addonName,
			icon = iconTexture,
			func = function()
				Private.Options.SetShown()
			end,
			funcOnEnter = function(button)
				GameTooltip:SetOwner(button, "ANCHOR_LEFT")
				GameTooltip:AddLine(Private.L.Settings.ClickToOpenSettings)
				GameTooltip:Show()
			end,
			funcOnLeave = function()
				GameTooltip:Hide()
			end,
		})
	end

	if fresh then
		Private.Utils.Print(Private.L.Registry.Empty)
	end
end)
