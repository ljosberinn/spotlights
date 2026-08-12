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
L.SlashCommands.OptionsPreview = "Opens the reworked settings panel, still being built"

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
L.Settings.TabImportExport = "Import / Export"
L.Settings.ShowMinimapButton = "Show Minimap Button"
L.Settings.ClickToOpenSettings = "Click To Open Settings"
L.Settings.Import = "Import"
L.Settings.Export = "Export"
L.Settings.ImportError = "Import failed: %s"
L.Settings.ImportErrorPrefix = "the string does not start with SPOTLIGHTS!"
L.Settings.ImportErrorDecode = "the string could not be decoded"
L.Settings.ImportErrorPayload = "the decoded data is not a settings table"
L.Settings.Copy = "Copy"

L.Settings.ToggleMover = "Unlock / Lock"
L.Settings.Recenter = "Return To Center"

L.Settings.PlacementHeading = "Placement"
L.Settings.InterfaceHeading = "Interface"
L.Settings.UnlockFrames = "Unlock Frames For Dragging"
L.Settings.Scale = "Frame Scale"
L.Settings.FrameStrata = "Frame Strata"
L.Settings.SlashHint = "Type |cffffd100/spotlights|r for every command."

--- The frame strata, as display strings. Named for what the layer is rather than transliterated, since
--- the value itself never reaches the user.
L.Settings.Strata = {
	BACKGROUND = "Background",
	LOW = "Low",
	MEDIUM = "Medium",
	HIGH = "High",
	DIALOG = "Dialog",
	FULLSCREEN = "Fullscreen",
	FULLSCREEN_DIALOG = "Fullscreen Dialog",
	TOOLTIP = "Tooltip",
}

L.Settings.FrameHeading = "Frame"
L.Settings.Width = "Frame Width"
L.Settings.Height = "Frame Height"
L.Settings.FrameAlpha = "Frame Opacity"
L.Settings.BarTexture = "Bar Texture"
L.Settings.TextureMissing = "%s (not loaded)"
L.Settings.ShowAbsorb = "Show Absorbs"
L.Settings.OutOfRangeAlpha = "Out Of Range Alpha"
L.Settings.DeadAlpha = "Dead Alpha"

L.Settings.ColorClass = "Class Color"
L.Settings.ColorStatic = "Static Color"
L.Settings.HealthColorMode = "Bar Color"
L.Settings.HealthColor = "Static Bar Color"
L.Settings.HealthBgColor = "Background Color"
L.Settings.ResetFrame = "Reset Frame Settings"

L.Settings.NameHeading = "Name"
L.Settings.NameColorMode = "Name Color"
L.Settings.NameColor = "Static Name Color"
L.Settings.NameFont = "Name Font"
L.Settings.NameFontSize = "Name Font Size"
L.Settings.NameAnchor = "Name Anchor"
L.Settings.NameOffsetX = "Name Offset X"
L.Settings.NameOffsetY = "Name Offset Y"
L.Settings.ResetName = "Reset Name Settings"
L.Settings.HealthTextHeading = "Health"
L.Settings.HealthTextEnabled = "Show Health"
L.Settings.HealthTextFormat = "Health Format"
L.Settings.HealthTextPercent = "Percent"
L.Settings.HealthTextAbsValue = "Abs Value"
L.Settings.HealthTextAbsValueAbbreviated = "Abs Value (Abbreviated)"
L.Settings.HealthTextColorMode = "Health Color"
L.Settings.HealthTextColor = "Static Health Color"
L.Settings.HealthTextFont = "Health Font"
L.Settings.HealthTextFontSize = "Health Font Size"
L.Settings.HealthTextAnchor = "Health Anchor"
L.Settings.HealthTextOffsetX = "Health Offset X"
L.Settings.HealthTextOffsetY = "Health Offset Y"
L.Settings.ResetHealthText = "Reset Health Settings"

L.Settings.PreviewHeading = "Preview"

-- The size the previewed frame really is, then what the pane had to shrink it by to fit -- so a
-- preview that reads smaller than its own numbers is explained rather than misleading.
L.Settings.PreviewCaption = "%d × %d · shown at %d%%"

L.Settings.Orientation = "Fill Direction"
L.Settings.Horizontal = "Across, Then Down"
L.Settings.Vertical = "Down, Then Across"
L.Settings.Stride = "Wrap Every"
L.Settings.GrowX = "Grow Horizontally"
L.Settings.GrowRight = "Right"
L.Settings.GrowLeft = "Left"
L.Settings.GrowY = "Grow Vertically"
L.Settings.GrowDown = "Down"
L.Settings.GrowUp = "Up"
L.Settings.SpacingX = "Horizontal Spacing"
L.Settings.SpacingY = "Vertical Spacing"

L.Settings.FillHeading = "Fill"
L.Settings.Spacing = "Spacing"
L.Settings.SpacingHorizontalShort = "H"
L.Settings.SpacingVerticalShort = "V"
L.Settings.FillOrderHeading = "Fill Order"
L.Settings.FillOrderCaption = "%s · wraps every %d · grows %s, %s"

L.Settings.AllowGaps = "Render Empty Cells"
L.Settings.AllowGapsHelp =
"On, a player who leaves the raid leaves their cell empty and nothing else moves. Off, the remaining spotlights close the gap once you are out of combat."
L.Settings.ClearOnLeave = "Clear Roster When Leaving The Group"
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

L.Settings.AurasEvokerOnly = "Aura tracking is an Evoker-only feature for Sense Power, Prescience, and Shifting Sands."

L.Settings.Prescience = "Prescience"
L.Settings.ShiftingSands = "Shifting Sands"
L.Settings.SensePower = "Sense Power"
L.Settings.Cooldowns = "Cooldowns & Custom Auras"
L.Settings.Defensives = "Defensives"
L.Settings.AuraAugmentationOnly = "Prescience, Shifting Sands, and Sense Power are available only to Augmentation Evokers."

-- The Auras tab's second sub-tab, and the tooltip on a category tab's enable dot.
L.Settings.AuraTracked = "Tracked"
L.Settings.AuraFeatureToggle = "Track %s"

L.Settings.AuraBar = "Status Bar"
L.Settings.AuraIcon = "Icon"
L.Settings.AuraEnabled = "Show"
L.Settings.AuraColor = "Bar Color"
L.Settings.AuraAlpha = "Opacity"
L.Settings.AuraWidth = "Width"
L.Settings.AuraHeight = "Height"
L.Settings.AuraAnchor = "Anchor To"
L.Settings.AuraOffsetX = "Offset X"
L.Settings.AuraOffsetY = "Offset Y"
L.Settings.AuraShowIcon = "Inline Icon"
L.Settings.AuraIconSide = "Icon Side"
L.Settings.AuraGap = "Gap"
L.Settings.AuraIconLeft = "Left Of The Bar"
L.Settings.AuraIconRight = "Right Of The Bar"
L.Settings.AuraIconWidth = "Width"
L.Settings.AuraIconHeight = "Height"
L.Settings.AuraShowSwipe = "Cooldown Swipe"
L.Settings.AuraShowText = "Duration Text"
L.Settings.AuraFont = "Duration Font"
L.Settings.AuraFontSize = "Duration Size"
L.Settings.AuraBorder = "Border"
L.Settings.AuraBorderStyle = "Border Style"
L.Settings.AuraBorderSize = "Border Size"
L.Settings.AuraBorderColor = "Border Color"

-- What a collapsed display section says about itself: its size, where it hangs, the one option that
-- most changes how it reads, and its border. Formatted from the live config on every edit, so the
-- header tracks the body -- and replaced outright by `AuraSummaryHidden` for a display that is off,
-- since a size for something nothing will draw is worse than no summary at all.
L.Settings.AuraSummary = "%d × %d · %s · %s · %s"
L.Settings.AuraSummaryHidden = "Hidden"
L.Settings.AuraSummarySwipeOn = "swipe on"
L.Settings.AuraSummarySwipeOff = "swipe off"
L.Settings.AuraSummaryInlineIcon = "inline icon"
L.Settings.AuraSummaryNoInlineIcon = "no inline icon"
L.Settings.AuraSummaryBorder = "%dpx border"
L.Settings.AuraSummaryNoBorder = "no border"

L.Settings.AuraReset = "Reset To Defaults"
L.Settings.AuraResetConfirm = "Reset"
-- Names the feature so the prompt is unambiguous when both sub-tabs share one button, and stays
-- silent about the tracked cooldown list because a reset does not touch it and Prescience has none.
L.Settings.AuraResetPrompt = "Reset %s's Status Bar And Icon To Their Default Settings?"

-- The reworked panel resets one display at a time, since the two are configured independently: the
-- display first, then the category it belongs to.
L.Settings.AuraResetDisplayPrompt = "Reset The %s For %s To Its Default Settings?"

-- The tracked list has a reset of its own, under the class rail. It says what it leaves alone, because
-- a spell the user typed in has no default to return to and deleting it is not what a reset is for.
L.Settings.AuraResetSpellsPrompt = "Reset Which Spells %s Tracks To The Shipped Defaults? Spells You Added Yourself Are Kept."

-- How much of a class is switched on, beside its name in the rail: enabled over total.
L.Settings.AuraGroupCount = "%d/%d"

-- The bulk switches over the spell pane. They act on whatever the search box left showing, so that a
-- filtered list does exactly what the buttons above it say.
L.Settings.AuraEnableAll = "Enable All"
L.Settings.AuraDisableAll = "Disable All"

-- The second line of a spell row: its ID, and the client's own subtext for it where there is one -- a
-- specialisation, a rank. Most spells have none, and the row is then the ID alone.
L.Settings.AuraSpellMeta = "%d · %s"

-- What stands in for the spell pane when there is no group to show. Prescience and Shifting Sands watch
-- one specific aura each, so there is nothing to choose; the other is a search that matched nothing.
L.Settings.AuraNoTrackedSpells = "%s watches one specific aura, so there is nothing to choose here."
L.Settings.AuraNoSpellMatches = "No spells match your search."

-- The one place the cost of the design is visible to the user, so it says what it costs rather than
-- only that it costs something.
L.Settings.AurasRebuildHelp =
"Some settings may need a reload after application. You will get prompted to do so when you finished customizing."

L.Settings.AuraBuiltinCooldowns = "Tracked Cooldowns"
L.Settings.AuraBuiltinCooldownsNote =
"Show these major cooldowns when the spotlighted player uses one."
L.Settings.AuraBuiltinDefensives = "Tracked Defensives"
L.Settings.AuraBuiltinDefensivesNote = "Show these defensive abilities when the spotlighted player uses one."

L.Settings.AuraCustomCooldowns = "Custom Auras"

-- Says what will silently not work, because the failure mode is a spell that was added successfully and
-- then simply never appears -- which reads as a bug rather than as a limit.
L.Settings.AuraCustomCooldownsNote =
"These must be BUFFS that appear on players, so trinket effects work. Debuffs and casts cannot be tracked here, and adding one will do nothing at all."
L.Settings.AuraCustomDefensivesNote = "Add defensive spell IDs that are not in the shipped list."

L.Settings.AuraCustomAdd = "Add"
L.Settings.AuraCustomSpellID = "Spell ID"

L.Settings.ReloadPrompt =
"Some aura settings replaced their displays rather than changing them, and the originals stay in memory until you reload.\n\nReload now?"
L.Settings.ReloadNow = "Reload now"
L.Settings.ReloadLater = "Later"
L.Settings.ImportReloadPrompt = "Spotlights settings were imported. Reload the UI now?"

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
