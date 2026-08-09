---@type string, Spotlights
local _, Private = ...

local L = Private.L

L.SlashCommands = {}

L.SlashCommands.Usage = "Commands:"

L.SlashCommands.Help = "Lists every command"
L.SlashCommands.Mover = "Unlocks the grid for dragging"
L.SlashCommands.Recenter = "Returns the grid to the screen center"
L.SlashCommands.Add = "Spotlights a raid member by name"
L.SlashCommands.List = "Lists the configured slots"
L.SlashCommands.Rescan = "Forces every occupied slot to re-match the roster"
L.SlashCommands.Options = "Opens the settings panel"

L.Migration = {}

L.Migration.FromTheFuture =
"saved settings are version %d but this build understands %d - they were left untouched rather than downgraded"

L.Registry = {}

L.Registry.NotLoaded = "saved settings have not loaded yet"
L.Registry.AddUsage = "usage: /spotlights add <name>"
L.Registry.Unknown = "no raid member matches '%s'"
L.Registry.IdentitySecret = "cannot match '%s' - %d raid member(s) have secret identities here"
L.Registry.NotInRoster = "that player is not in the raid, so their name cannot be matched reliably"
L.Registry.Duplicate = "%s already holds slot %d"
L.Registry.NoSuchSlot = "there is no slot %d"
L.Registry.Assigned = "slot %d spotlights %s"
L.Registry.Deferred = "in combat - the frames catch up when it ends"
L.Registry.Rescanned = "re-matched %d slot(s) against the roster"
L.Registry.Empty = "no slots configured - try /spotlights add <name>"
L.Registry.ListHeader = "%d slot(s), %d roster name(s) readable, %d secret"
L.Registry.ListPlayer = "  %d. %s |cff808080%s|r"
L.Registry.ListBlank = "  %d. |cff808080(spacer)|r"
L.Registry.Absent = "not in raid"
L.Layout = {}

L.Layout.NotLoaded = "saved settings have not loaded yet"
L.Settings = {}

L.Settings.Title = "Spotlights"
L.Settings.CombatRefused = "settings cannot be opened in combat"
L.Settings.ClosedByCombat = "settings closed: entering combat"

L.Settings.TabGeneral = "General"
L.Settings.TabAppearance = "Appearance"
L.Settings.TabGrid = "Grid"
L.Settings.TabAuras = "Auras"
L.Settings.TabRoster = "Roster"
L.Settings.ShowMinimapButton = "Show minimap button"
L.Settings.ClickToOpenSettings = "Click to open settings"

L.Settings.ToggleMover = "Unlock / lock"
L.Settings.Recenter = "Return to center"

L.Settings.FrameHeading = "Frame"
L.Settings.Width = "Frame width"
L.Settings.Height = "Frame height"
L.Settings.FrameAlpha = "Frame opacity"
L.Settings.BarTexture = "Bar texture"
L.Settings.TextureMissing = "%s (not loaded)"
L.Settings.ShowAbsorb = "Show absorbs"
L.Settings.OutOfRangeAlpha = "Out of range alpha"
L.Settings.DeadAlpha = "Dead alpha"

L.Settings.ColorClass = "Class color"
L.Settings.ColorStatic = "Static color"
L.Settings.HealthColorMode = "Bar color"
L.Settings.HealthColor = "Static bar color"
L.Settings.HealthBgColor = "Background color"
L.Settings.ResetFrame = "Reset frame settings"

L.Settings.NameHeading = "Name"
L.Settings.NameColorMode = "Name color"
L.Settings.NameColor = "Static name color"
L.Settings.NameFont = "Name font"
L.Settings.NameFontSize = "Name font size"
L.Settings.NameAnchor = "Name anchor"
L.Settings.NameOffsetX = "Name offset right"
L.Settings.NameOffsetY = "Name offset up"
L.Settings.ResetName = "Reset name settings"
L.Settings.HealthTextHeading = "Health"
L.Settings.HealthTextEnabled = "Show health"
L.Settings.HealthTextFormat = "Health format"
L.Settings.HealthTextPercent = "Percent"
L.Settings.HealthTextAbsValue = "Abs Value"
L.Settings.HealthTextAbsValueAbbreviated = "Abs Value (Abbreviated)"
L.Settings.HealthTextColorMode = "Health color"
L.Settings.HealthTextColor = "Static health color"
L.Settings.HealthTextFont = "Health font"
L.Settings.HealthTextFontSize = "Health font size"
L.Settings.HealthTextAnchor = "Health anchor"
L.Settings.HealthTextOffsetX = "Health offset right"
L.Settings.HealthTextOffsetY = "Health offset up"
L.Settings.ResetHealthText = "Reset health settings"

L.Settings.Orientation = "Fill direction"
L.Settings.Horizontal = "Across, then down"
L.Settings.Vertical = "Down, then across"
L.Settings.Stride = "Wrap every"
L.Settings.GrowX = "Grow horizontally"
L.Settings.GrowRight = "Right"
L.Settings.GrowLeft = "Left"
L.Settings.GrowY = "Grow vertically"
L.Settings.GrowDown = "Down"
L.Settings.GrowUp = "Up"
L.Settings.SpacingX = "Horizontal spacing"
L.Settings.SpacingY = "Vertical spacing"

L.Settings.AllowGaps = "Render empty cells"
L.Settings.AllowGapsHelp =
"On, a player who leaves the raid leaves their cell empty and nothing else moves. Off, the remaining spotlights close the gap once you are out of combat."
L.Settings.ClearOnLeave = "Clear roster when leaving the group"
L.Settings.ClearOnLeaveHelp =
"Off, your spotlights are remembered between raids. On, leaving a raid empties the grid completely - every player and every spacer - so the next one starts from nothing. Logging out, reloading and reconnecting do not count as leaving."

L.Settings.CombatHelp =
"Spotlights are rebuilt out of combat only. Adding or removing one during a fight is remembered and applied the moment combat ends; nothing is lost, but the grid will not change mid-pull."

L.Settings.RosterHelp =
"You can drag & drop players in and out of the grouping below. You can also drag them on top of the Spotlights container if at least one other player is already present."

L.Settings.SlotsHeader = "Configured slots"
L.Settings.RaidHeader = "Raid members"
L.Settings.AddSpacer = "Add a spacer"
L.Settings.BlankSlot = "(spacer)"
L.Settings.UnknownSlot = "(empty)"
L.Settings.NotInRaid = "not in a raid"
L.Settings.AllSpotlighted = "everyone is spotlighted"
L.Settings.UpShort = "^"
L.Settings.DownShort = "v"
L.Settings.RemoveShort = "x"
L.Settings.PlusShort = "+"

L.Settings.AurasRequiresTwelveOne =
"Aura displays need patch 12.1 or later. This client does not have the system they are built on, so the rest of this tab is hidden rather than shown doing nothing."
L.Settings.AurasEvokerOnly = "Aura tracking is an Evoker-only feature for Sense Power and Prescience."

L.Settings.Prescience = "Prescience"
L.Settings.SensePower = "Sense Power"

L.Settings.AuraBar = "Status Bar"
L.Settings.AuraIcon = "Icon"
L.Settings.AuraEnabled = "Show"
L.Settings.AuraColor = "Bar color"
L.Settings.AuraAlpha = "Opacity"
L.Settings.AuraWidthPct = "Width (of frame)"
L.Settings.AuraHeightPct = "Height (of frame)"
L.Settings.AuraAnchor = "Anchor to"
L.Settings.AuraOffsetX = "Offset right"
L.Settings.AuraOffsetY = "Offset up"
L.Settings.AuraShowIcon = "Inline icon"
L.Settings.AuraIconSide = "Icon side"
L.Settings.AuraIconLeft = "Left of the bar"
L.Settings.AuraIconRight = "Right of the bar"
L.Settings.AuraIconWidth = "Width"
L.Settings.AuraIconHeight = "Height"
L.Settings.AuraShowSwipe = "Cooldown swipe"
L.Settings.AuraShowText = "Duration text"
L.Settings.AuraFont = "Duration font"
L.Settings.AuraFontSize = "Duration size"
L.Settings.AuraBorder = "Border"
L.Settings.AuraBorderSize = "Border thickness"
L.Settings.AuraBorderColor = "Border color"

L.Settings.AuraReset = "Reset to defaults"
L.Settings.AuraResetConfirm = "Reset"
-- Names the feature so the prompt is unambiguous when both sub-tabs share one button, and stays
-- silent about the tracked cooldown list because a reset does not touch it and Prescience has none.
L.Settings.AuraResetPrompt = "Reset %s's Status Bar and icon to their default settings?"

-- The one place the cost of the design is visible to the user, so it says what it costs rather than
-- only that it costs something.
L.Settings.AurasRebuildHelp =
"Some settings may need a reload after application. You will get prompted to do so when you finished customizing."

L.Settings.AuraBuiltinCooldowns = "Tracked Cooldowns"
L.Settings.AuraBuiltinCooldownsNote =
"The Sense Power display also shows these major cooldowns when the spotlighted player uses one."

L.Settings.AuraCustomCooldowns = "Custom Auras"

-- Says what will silently not work, because the failure mode is a spell that was added successfully and
-- then simply never appears -- which reads as a bug rather than as a limit.
L.Settings.AuraCustomCooldownsNote =
"These must be BUFFS that appear on players, so trinket effects work. Debuffs and casts cannot be tracked here, and adding one will do nothing at all."

L.Settings.AuraCustomAdd = "Add"
L.Settings.AuraCustomSpellID = "Spell ID"

L.Settings.ReloadPrompt =
"Some aura settings replaced their displays rather than changing them, and the originals stay in memory until you reload.\n\nReload now?"
L.Settings.ReloadNow = "Reload now"
L.Settings.ReloadLater = "Later"

L.Settings.Anchors = {
	TOPLEFT = "Top left",
	TOP = "Top",
	TOPRIGHT = "Top right",
	LEFT = "Left",
	CENTER = "Center",
	RIGHT = "Right",
	BOTTOMLEFT = "Bottom left",
	BOTTOM = "Bottom",
	BOTTOMRIGHT = "Bottom right",
}

L.Auras = {}

-- Two prompts rather than one, because they ask for different things. The first is a setup problem
-- the user may not know they have; the second is a switch they can flick.
L.Auras.SensePowerMissing =
"Spotlights cannot tell whether Sense Power is active unless it is on one of your action bars.\n\nOnly the cooldowns you have enabled can be tracked, which leaves out some summons. For complete tracking, Sense Power must be active, so put it on a bar if you wish to turn it on."
L.Auras.SensePowerInactive =
"Sense Power is not active.\n\nOnly the cooldowns you have enabled can be tracked, which leaves out some summons. For complete tracking, please activate Sense Power."

L.ContextMenu = {}

L.ContextMenu.Title = "Spotlights"
L.ContextMenu.Add = "Spotlight this player"
L.ContextMenu.Remove = "Stop spotlighting"

L.DragAssign = {}

L.DragAssign.HintDrag = "Drag %s onto a spotlight"
L.DragAssign.HintAdd = "Add %s as slot %d"
L.DragAssign.HintAppend = "Add %s to the end"
L.DragAssign.HintAlready = "%s already holds slot %d"
L.DragAssign.HintReorder = "Drag %s to a cell to reorder, or to Raid members to remove"
L.DragAssign.HintMove = "Move %s to slot %d"
L.DragAssign.HintRemove = "Remove %s"

L.Preview = {}

-- Only ever seen on a slot with nobody assigned to it, so it has to read as a stand-in rather than
-- as a player whose name failed to resolve.
L.Preview.Label = "Spotlight %d"

L.Mover = {}

L.Mover.Label = "Spotlights"
L.Mover.Unlocked = "grid unlocked - drag it anywhere, /spotlights mover to lock"
L.Mover.Locked = "grid locked"
L.Mover.LockedByCombat = "grid locked: entering combat"
L.Mover.CombatRefused = "cannot move the grid in combat"
L.Mover.Reset = "grid returned to the screen center"
L.Registry.Unresolved = "no guid yet"
L.Registry.ClearedOnLeave = "left the raid - roster cleared, as configured"
