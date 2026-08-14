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
-- Refused rather than added and taken straight back out, so the setting explains itself the first time
-- it stops someone from being spotlighted.
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

-- The second tooltip line. Assigning a slot is the most common reason to open the panel, so the button
-- says the shortcut rather than leaving it to be found.
L.Settings.RightClickToOpenRoster = "Right-Click To Open The Roster Tab"
L.Settings.Import = "Import"
L.Settings.Export = "Export"
L.Settings.ImportError = "Import failed: %s"
-- Said in terms of the kind of string rather than the prefix it lacks, because a preset string does
-- start with SPOTLIGHTS! and is still refused here.
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

--- Group headings, one level between a section title and a control's own label. Kept under their own
--- prefix rather than reusing the control labels they sit over: `Size` heads a group whose members are
--- `Frame Width` and `Frame Height`, and a heading that repeated a label would read as a duplicate row.
---
--- Shared across tabs on purpose -- `Text`, `Color` and `Positioning` mean the same thing over the name
--- as over the health text, and one string each is what keeps them spelled the same way.
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

-- Not a strata but the absence of one: the name draws in the layer the grid is already in. Named for
-- what it does rather than "Default", since every other entry in the list is a layer.
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

-- The size the previewed frame really is, then what the pane had to shrink it by to fit -- so a
-- preview that reads smaller than its own numbers is explained rather than misleading.
L.Settings.PreviewCaption = "%d × %d · shown at %d%%"

-- An axis, on both dropdowns it labels: which way the grid wraps, and which way a bar's fill runs. The
-- end that fill starts at is `AuraFillDirection`, which is a separate control on the same panel.
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
-- Says what it does to the grid rather than what it does to the list, because it is destructive: the
-- roles picked here are taken out of the grid and kept out, not merely hidden somewhere.
L.Settings.AutoRemoveRoles = "Automatically Remove These Roles"

-- The two pane headings are read as a pair: each names the people in its own list rather than the
-- structure behind it, and the right one is not "group members" because anyone already spotlighted is
-- left out of it.
L.Settings.SpotlightedHeader = "Spotlighted"
L.Settings.UnrosteredHeader = "Unrostered"
-- Ends in an ellipsis on purpose: the dropdown under it finishes the sentence with the roles picked.
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
-- The third empty state, and the one the role filter above the list adds: the group has members, but
-- none playing a role the list was told to show. Names no role itself, because which ones are shown is
-- the user's to change and the dropdown right above says so.
L.Settings.NoOfferedRoles = "no one in the group plays the roles this list shows"
L.Settings.UpShort = "^"
L.Settings.DownShort = "v"
L.Settings.RemoveShort = "x"
L.Settings.PlusShort = "+"

-- The presets block under the unrostered list. A preset is a slot layout and nothing else, which is
-- what the delete prompt says out loud: "delete" beside a list of slots could be read as deleting the
-- slots.
L.Settings.PresetsHeading = "Presets"
L.Settings.PresetsCount = "%d saved"
L.Settings.PresetsNone = "No presets saved yet. Save the slots you have configured to start one."
-- The dropdown with nothing picked, which is what a fresh session and a finished import both leave
-- behind: an import fills the library without applying anything, so the block has to be able to say
-- that the grid is nobody's preset.
L.Settings.PresetNoneSelected = "None selected"

L.Settings.PresetSave = "Save"
L.Settings.PresetDelete = "Delete"
L.Settings.PresetSavePrompt = "Name this preset:"

-- The same dialog, asked of an imported string, which arrives with the name its author gave it: the
-- question is whether to keep that name rather than what to call an unnamed thing.
L.Settings.PresetImportNamePrompt = "Preset name is currently %s - do you wish to rename it?"
L.Settings.PresetOverwritePrompt = "A preset called \"%s\" already exists. Replace it?"
L.Settings.PresetOverwriteConfirm = "Replace"
L.Settings.PresetDeletePrompt = "Delete the preset \"%s\"? Your configured slots are not touched."

-- What commits the pasted string. It adds a preset to the library rather than applying one, so it says
-- "add" where the Import/Export tab's button says "import".
L.Settings.PresetImportAdd = "Add Preset"

-- A preset string and a profile string cannot be swapped, and each says so in the other's words: this
-- is the answer to a full profile pasted into the preset box.
L.Settings.PresetImportErrorPrefix = "the string is not a Spotlights preset"
L.Settings.PresetImportErrorPayload = "the decoded data is not a slot list"

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

-- The third display: a coloured block with no spell art on it, for when presence and remaining time are
-- the whole of what is wanted. One size, since it is square, and its colour is all that tells two of
-- them apart -- which is why the label says what is being coloured.
L.Settings.AuraSquare = "Square"
L.Settings.AuraSquareSize = "Size"
L.Settings.AuraSquareColor = "Block Color"

-- The fourth display: the remaining duration and nothing else. Its three style labels drop the `Duration`
-- the icon's and the square's carry, because there is nothing else on this display for them to be about.
L.Settings.AuraText = "Text"
L.Settings.AuraTextFont = "Font"
L.Settings.AuraTextFontSize = "Size"
L.Settings.AuraTextColor = "Text Color"
-- The fifth display: the spotlight's health bar wearing a colour for as long as the aura is up. Two
-- controls and no others -- its rect is the health bar's, so there is no size, no anchor and no border to
-- offer. The note says what the opacity costs, because at 1 the class colour is gone while the aura is up
-- and that reads as a bug rather than as the setting doing what it says.
L.Settings.AuraFrameColor = "Frame Color"
L.Settings.AuraFrameColorColor = "Health Bar Color"
L.Settings.AuraFrameColorNote =
"Colors the health bar while the aura is up. At full opacity the class color is hidden until the aura falls off; lower it to let the class color show through. Drawn over the name unless you raise Name Strata."

-- The tint's summary. The shortest of the five, because opacity is the only thing it has to say: it has no
-- size, no anchor and no border.
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

-- Which axis a bar's fill runs along, under the `L.Settings.Orientation` label the Grid tab also uses.
-- Not that tab's own two choices: "Across, Then Down" is a wrapping rule and says nothing about a bar.
L.Settings.AuraFillHorizontal = "Horizontal"
L.Settings.AuraFillVertical = "Vertical"

-- Which end of that axis the fill is anchored to. Four choices for two stored values: the pair offered
-- names the ends of whichever axis is set, and the summary reuses the same words.
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

-- What a collapsed display section says about itself: its size, where it hangs, the one option that
-- most changes how it reads, and its border. Formatted from the live config on every edit, so the
-- header tracks the body -- and replaced outright by `AuraSummaryHidden` for a display that is off,
-- since a size for something nothing will draw is worse than no summary at all.
L.Settings.AuraSummary = "%d × %d · %s · %s · %s"

-- The bar's own, one field longer: its fill direction goes between the size and the anchor, because a
-- `100 × 25` that drains upward reads as a lie without it.
L.Settings.AuraSummaryBar = "%d × %d · %s · %s · %s · %s"

-- The bare countdown's own, three fields shorter: it has no size of its own -- the font size is what
-- stands in for one -- and no swipe, so what is left is how big, where, and its border.
L.Settings.AuraSummaryText = "%dpx · %s · %s"
L.Settings.AuraSummaryHidden = "Hidden"
L.Settings.AuraSummarySwipeOn = "swipe on"
L.Settings.AuraSummarySwipeOff = "swipe off"
L.Settings.AuraSummaryInlineIcon = "inline icon"
L.Settings.AuraSummaryNoInlineIcon = "no inline icon"
L.Settings.AuraSummaryBorder = "%dpx border"
L.Settings.AuraSummaryNoBorder = "no border"

-- The second pane in a display section, shown only once the category has two displays on: the same mini
-- spotlight wearing all of them at once, which is where the offsets that separate them are judged. The
-- caption names what is on the frame rather than restating its size, which the pane above already gives.
L.Settings.AuraCombinedPreviewHeading = "All Active Displays"
L.Settings.AuraCombinedPreviewCaption = "Every display this category has switched on, together."

L.Settings.AuraReset = "Reset To Defaults"
L.Settings.AuraResetConfirm = "Reset"
-- Names the display and then the category it belongs to, because the Appearance sub-tab carries one
-- reset per display and the three are configured independently. Silent about the tracked spell list,
-- which a display reset does not touch and which two of the five categories do not have.
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

-- What stands in for the spell pane when there is no group to show. Prescience and Shifting Sands watch
-- one specific aura each, so there is nothing to choose; the other is a search that matched nothing.
L.Settings.AuraNoTrackedSpells = "%s watches one specific aura, so there is nothing to choose here."
L.Settings.AuraNoSpellMatches = "No spells match your search."

-- The one place the cost of the design is visible to the user, so it says what it costs rather than
-- only that it costs something.
L.Settings.AurasRebuildHelp =
"Some settings may need a reload after application. You will get prompted to do so when you finished customizing."

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
L.DragAssign.HintReorder = "Drag %s to a cell to reorder, or to Unrostered to remove"
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
L.Registry.ClearedOnLeave = "group changed - roster cleared, as configured"
