---@type string, Spotlights
local _, Private = ...

local L = Private.L

L.SlashCommands = {}

L.SlashCommands.Usage = "Commands:"

L.SlashCommands.Help = "Lists every command"
L.SlashCommands.Mover = "Unlocks the grid for dragging"
L.SlashCommands.Recenter = "Returns the grid to the screen center"
L.SlashCommands.Add = "Spotlights a group member by name"
L.SlashCommands.List = "Lists the configured slots"
L.SlashCommands.Rescan = "Forces every occupied slot to re-match the roster"
L.SlashCommands.Options = "Opens the settings panel"

L.Migration = {}

L.Migration.FromTheFuture =
"saved settings are version %d but this build understands %d - they were left untouched rather than downgraded"

L.Registry = {}

L.Registry.NotLoaded = "saved settings have not loaded yet"
L.Registry.AddUsage = "usage: /spotlights add <name>"
L.Registry.Unknown = "no group member matches '%s'"
L.Registry.IdentitySecret = "cannot match '%s' - %d group member(s) have secret identities here"
L.Registry.NotInRoster = "that player is not in the group, so their name cannot be matched reliably"
L.Registry.Duplicate = "%s already holds slot %d"
-- Refused rather than added and taken straight back out, so the setting explains itself the first time it
-- stops someone from being spotlighted.
L.Registry.RoleAutoRemoved = "%s plays a role set to be removed from the grid"
L.Registry.NoSuchSlot = "there is no slot %d"
L.Registry.Assigned = "slot %d spotlights %s"
L.Registry.Deferred = "in combat - the frames catch up when it ends"
L.Registry.Rescanned = "re-matched %d slot(s) against the roster"
L.Registry.Empty = "no slots configured - try /spotlights add <name>"
L.Registry.ListHeader = "%d slot(s), %d roster name(s) readable, %d secret"
L.Registry.ListPlayer = "  %d. %s |cff808080%s|r"
L.Registry.ListBlank = "  %d. |cff808080(spacer)|r"
L.Registry.Absent = "not in group"
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

-- The second tooltip line, since assigning a slot is the most common reason to open the panel.
L.Settings.RightClickToOpenRoster = "Right-Click To Open The Roster Tab"
L.Settings.Import = "Import"
L.Settings.Export = "Export"
L.Settings.ImportError = "Import failed: %s"
-- Said in terms of the kind of string rather than the prefix it lacks: a preset string does start with
-- SPOTLIGHTS! and is still refused here.
L.Settings.ImportErrorPrefix = "the string is not a Spotlights profile"
L.Settings.ImportErrorDecode = "the string could not be decoded"
L.Settings.ImportErrorPayload = "the decoded data is not a settings table"
-- The one import failure the user can act on, so it says what to do rather than only what went wrong.
L.Settings.ImportErrorVersion = "the profile comes from a newer version of Spotlights, so update the addon first"
L.Settings.Copy = "Copy"

L.Settings.Recenter = "Return To Center"

L.Settings.PlacementHeading = "Placement"
L.Settings.InterfaceHeading = "Interface"
L.Settings.UnlockFrames = "Unlock Frames For Dragging"
L.Settings.Scale = "Frame Scale"
L.Settings.FrameStrata = "Frame Strata"
L.Settings.SlashHint = "Type |cffffd100/spotlights|r for every command."

--- Named for what the layer is rather than transliterated; the stored value never reaches the user.
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

--- Group headings, one level between a section title and a control's own label. Their own prefix rather
--- than the control labels they sit over, which would read as a duplicate row, and shared across tabs so
--- `Text`, `Color` and `Positioning` stay spelled the same way wherever they appear.
L.Settings.GroupSize = "Size"
L.Settings.GroupHealthBar = "Health Bar"
L.Settings.GroupOpacity = "Opacity"
L.Settings.GroupText = "Text"
L.Settings.GroupColor = "Color"
L.Settings.GroupPositioning = "Positioning"
L.Settings.GroupDisplay = "Display"
L.Settings.GroupCooldown = "Cooldown"
L.Settings.GroupBar = "Bar"
L.Settings.GroupIcon = "Icon"
L.Settings.GroupBlock = "Block"

L.Settings.NameHeading = "Name"
L.Settings.ShowName = "Show Name"
L.Settings.NameHoverOnly = "Show Name On Hover Only"
L.Settings.NameStrata = "Name Strata"

-- Not a strata but the absence of one, and named for that rather than "Default", since every other entry
-- in the list is a layer.
L.Settings.NameStrataInherit = "Inherit"

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

-- The frame's real size, then what the pane shrank it by, so a preview smaller than its own numbers is
-- explained rather than misleading.
L.Settings.PreviewCaption = "%d × %d · shown at %d%%"

-- An axis on both dropdowns it labels: which way the grid wraps, and which way a bar's fill runs. Which
-- end that fill starts at is `AuraFillDirection`, a separate control.
L.Settings.Orientation = "Fill Axis"
L.Settings.Horizontal = "Across, Then Down"
L.Settings.Vertical = "Down, Then Across"
L.Settings.Stride = "Wrap Every"
L.Settings.GrowX = "Grow Horizontally"
L.Settings.GrowRight = "Right"
L.Settings.GrowLeft = "Left"
L.Settings.GrowY = "Grow Vertically"
L.Settings.GrowDown = "Down"
L.Settings.GrowUp = "Up"

L.Settings.FillHeading = "Fill"
L.Settings.Spacing = "Spacing"
L.Settings.SpacingHorizontalShort = "H"
L.Settings.SpacingVerticalShort = "V"
L.Settings.FillOrderHeading = "Fill Order"
L.Settings.FillOrderCaption = "%s · wraps every %d · grows %s, %s"

L.Settings.AllowGaps = "Render Empty Cells"
L.Settings.ClearOnLeave = "Clear Roster When Leaving The Group"
-- Says what it does to the grid rather than to the list, because it is destructive: these roles are taken
-- out and kept out, not hidden.
L.Settings.AutoRemoveRoles = "Automatically Remove These Roles"

-- Read as a pair, each naming the people in its own list. Not "group members" on the right, since anyone
-- already spotlighted is left out of it.
L.Settings.SpotlightedHeader = "Spotlighted"
L.Settings.UnrosteredHeader = "Unrostered"
-- Ends in an ellipsis: the dropdown under it finishes the sentence with the roles picked.
L.Settings.UnrosteredRoleFilter = "Show roles matching..."
L.Settings.AddSpacer = "Add Spacer"
L.Settings.NoSlots =
"No spotlights configured yet. Add a group member from the list beside this one, or drag one onto it."
L.Settings.ClearSlots = "Prune"
L.Settings.ClearSlotsPrompt = "Confirm pruning the roster"
L.Settings.ClearSlotsConfirm = "Prune"
L.Settings.BlankSlot = "(spacer)"
L.Settings.UnknownSlot = "(empty)"
L.Settings.NotInGroup = "not in a group"
L.Settings.AllSpotlighted = "everyone is spotlighted"
-- The empty state the role filter adds: members exist, none in a shown role. Names no role itself, since
-- the dropdown right above says which are shown.
L.Settings.NoOfferedRoles = "no one in the group plays the roles this list shows"
L.Settings.UpShort = "^"
L.Settings.DownShort = "v"
L.Settings.RemoveShort = "x"
L.Settings.PlusShort = "+"

-- A preset is a slot layout and nothing else, which the delete prompt says out loud: "delete" beside a list
-- of slots could be read as deleting the slots.
L.Settings.PresetsHeading = "Presets"
L.Settings.PresetsCount = "%d saved"
L.Settings.PresetsNone = "No presets saved yet. Save the slots you have configured to start one."
-- What a fresh session and a finished import both leave behind: an import fills the library without
-- applying anything, so the block has to be able to say the grid is nobody's preset.
L.Settings.PresetNoneSelected = "None selected"

L.Settings.PresetSave = "Save"
L.Settings.PresetDelete = "Delete"
L.Settings.PresetSavePrompt = "Name this preset:"

-- The same dialog asked of an imported string, where the question is whether to keep the author's name
-- rather than what to call an unnamed thing.
L.Settings.PresetImportNamePrompt = "Preset name is currently %s - do you wish to rename it?"
L.Settings.PresetOverwritePrompt = "A preset called \"%s\" already exists. Replace it?"
L.Settings.PresetOverwriteConfirm = "Replace"
L.Settings.PresetDeletePrompt = "Delete the preset \"%s\"? Your configured slots are not touched."

-- "Add" rather than the Import/Export tab's "import": it adds a preset to the library without applying one.
L.Settings.PresetImportAdd = "Add Preset"

-- The answer to a full profile pasted into the preset box; the two kinds of string cannot be swapped, and
-- each says so in the other's words.
L.Settings.PresetImportErrorPrefix = "the string is not a Spotlights preset"
L.Settings.PresetImportErrorPayload = "the decoded data is not a slot list"

L.Settings.Prescience = "Prescience"
L.Settings.ShiftingSands = "Shifting Sands"
L.Settings.SensePower = "Sense Power"
L.Settings.Cooldowns = "Cooldowns"
L.Settings.Defensives = "Defensives"
L.Settings.CustomAuras = "Custom Auras"
L.Settings.AuraAugmentationOnly = "Prescience, Shifting Sands, and Sense Power are available only to Augmentation Evokers."

-- The Auras tab's second sub-tab, and the tooltip on a category tab's enable dot.
L.Settings.AuraTracked = "Tracked"
L.Settings.AuraFeatureToggle = "Track %s"

L.Settings.AuraBar = "Status Bar"
L.Settings.AuraIcon = "Icon"

-- The third display: a coloured block with no spell art. One size, since it is square, and its colour is
-- all that tells two of them apart -- hence a label saying what is being coloured.
L.Settings.AuraSquare = "Square"
L.Settings.AuraSquareSize = "Size"
L.Settings.AuraSquareColor = "Block Color"

-- The fourth display: the remaining duration and nothing else, so its labels drop the `Duration` the icon's
-- and the square's carry.
L.Settings.AuraText = "Text"
L.Settings.AuraTextFont = "Font"
L.Settings.AuraTextFontSize = "Size"
L.Settings.AuraTextColor = "Text Color"
-- The fifth display: the health bar wearing a colour while the aura is up. Its rect is the health bar's, so
-- there is no size, anchor or border to offer. The note says what the opacity costs, because at 1 the class
-- colour disappears and that reads as a bug.
L.Settings.AuraFrameColor = "Frame Color"
L.Settings.AuraFrameColorColor = "Health Bar Color"
L.Settings.AuraFrameColorNote =
"Colors the health bar while the aura is up. At full opacity the class color is hidden until the aura falls off; lower it to let the class color show through. Drawn over the name unless you raise Name Strata."

-- The shortest of the five summaries, because opacity is all this display has.
L.Settings.AuraSummaryFrameColor = "%d%% opacity"

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

-- The same two stored values as above, named for a bar that fills along its height: `LEFT` is the end
-- the labels above call left, which on a vertical bar is its top.
L.Settings.AuraIconTop = "Above The Bar"
L.Settings.AuraIconBottom = "Below The Bar"

-- Under the `L.Settings.Orientation` label the Grid tab also uses, but not that tab's own two choices:
-- "Across, Then Down" is a wrapping rule and says nothing about a bar.
L.Settings.AuraFillHorizontal = "Horizontal"
L.Settings.AuraFillVertical = "Vertical"

-- Four choices for two stored values: the pair offered names the ends of whichever axis is set.
L.Settings.AuraFillDirection = "Fill Direction"
L.Settings.AuraFillLeftToRight = "Left To Right"
L.Settings.AuraFillRightToLeft = "Right To Left"
L.Settings.AuraFillBottomToTop = "Bottom To Top"
L.Settings.AuraFillTopToBottom = "Top To Bottom"
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

-- What a collapsed display section says about itself, formatted from the live config on every edit.
-- Replaced outright by `AuraSummaryHidden` for a display that is off, since a size for something nothing
-- will draw is worse than no summary.
L.Settings.AuraSummary = "%d × %d · %s · %s · %s"

-- The bar's own, one field longer: a `100 × 25` that drains upward reads as a lie without its fill
-- direction.
L.Settings.AuraSummaryBar = "%d × %d · %s · %s · %s · %s"

-- The bare countdown's own, three fields shorter: no size of its own -- the font size stands in -- and no
-- swipe.
L.Settings.AuraSummaryText = "%dpx · %s · %s"
L.Settings.AuraSummaryHidden = "Hidden"
L.Settings.AuraSummarySwipeOn = "swipe on"
L.Settings.AuraSummarySwipeOff = "swipe off"
L.Settings.AuraSummaryInlineIcon = "inline icon"
L.Settings.AuraSummaryNoInlineIcon = "no inline icon"
L.Settings.AuraSummaryBorder = "%dpx border"
L.Settings.AuraSummaryNoBorder = "no border"

-- The second pane, shown once a category has two displays on: where the offsets separating them are judged.
-- Names what is on the frame rather than restating the size the pane above already gives.
L.Settings.AuraCombinedPreviewHeading = "All Active Displays"
L.Settings.AuraCombinedPreviewCaption = "Every display this category has switched on, together."

L.Settings.AuraReset = "Reset To Defaults"
L.Settings.AuraResetConfirm = "Reset"
-- Names the display and then its category, because the Appearance sub-tab carries one reset per display.
-- Silent about the tracked spell list, which a display reset does not touch.
L.Settings.AuraResetDisplayPrompt = "Reset The %s For %s To Its Default Settings?"

-- The tracked list's own reset says what it leaves alone: a spell the user typed in has no default to
-- return to, and deleting it is not what a reset is for.
L.Settings.AuraResetSpellsPrompt = "Reset Which Spells %s Tracks To The Shipped Defaults? Spells You Added Yourself Are Kept."

-- How much of a class is switched on, beside its name in the rail: enabled over total.
L.Settings.AuraGroupCount = "%d/%d"

-- These act on whatever the search box left showing, so a filtered list does what the buttons say.
L.Settings.AuraEnableAll = "Enable All"
L.Settings.AuraDisableAll = "Disable All"

-- What stands in for the spell pane when there is no group to show: a one-aura category, or a search that
-- matched nothing.
L.Settings.AuraNoTrackedSpells = "%s watches one specific aura, so there is nothing to choose here."
L.Settings.AuraNoSpellMatches = "No spells match your search."

-- The one place the cost of the design is visible to the user, so it says what that cost is.
L.Settings.AurasRebuildHelp =
"Some settings may need a reload after application. You will get prompted to do so when you finished customizing."

-- Says what will silently not work: a spell added successfully and then never seen reads as a bug.
L.Settings.AuraCustomNote =
"These must be BUFFS that appear on players, so trinket effects work. Debuffs and casts cannot be tracked here, and adding one will do nothing at all."

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

-- Two prompts, because the first is a setup problem the user may not know they have and the second is a
-- switch they can flick.
L.Auras.SensePowerMissing =
"Spotlights cannot tell whether Sense Power is active unless it is on one of your action bars.\n\nOnly the cooldowns you have enabled can be tracked, which leaves out some summons. For complete tracking, Sense Power must be active, so put it on a bar if you wish to turn it on."
L.Auras.SensePowerInactive =
"Sense Power is not active.\n\nOnly the cooldowns you have enabled can be tracked, which leaves out some summons. For complete tracking, please activate Sense Power."
L.Auras.SensePowerIgnore = "Ignore until Reload"

L.ContextMenu = {}

L.ContextMenu.Title = "Spotlights"
L.ContextMenu.Add = "Spotlight this player"
L.ContextMenu.Remove = "Stop spotlighting"

L.DragAssign = {}

L.DragAssign.HintDrag = "Drag %s onto a spotlight"
L.DragAssign.HintAdd = "Add %s as slot %d"
L.DragAssign.HintAppend = "Add %s to the end"
L.DragAssign.HintAlready = "%s already holds slot %d"
L.DragAssign.HintReorder = "Drag %s to a cell to reorder, or to Unrostered to remove"
L.DragAssign.HintMove = "Move %s to slot %d"
L.DragAssign.HintRemove = "Remove %s"

L.Preview = {}

-- Only ever seen on an unassigned slot, so it has to read as a stand-in rather than as a name that failed
-- to resolve.
L.Preview.Label = "Spotlight %d"

L.Mover = {}

L.Mover.Label = "Spotlights"
L.Mover.Unlocked = "grid unlocked - drag it anywhere, /spotlights mover to lock"
L.Mover.Locked = "grid locked"
L.Mover.LockedByCombat = "grid locked: entering combat"
L.Mover.CombatRefused = "cannot move the grid in combat"
L.Mover.Reset = "grid returned to the screen center"
L.Registry.Unresolved = "no guid yet"
L.Registry.ClearedOnLeave = "group changed - roster cleared, as configured"
