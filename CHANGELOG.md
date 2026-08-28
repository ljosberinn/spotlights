v1.1.2

## Features

- click casting can now be bound to keyboard keys and the mouse wheel, not only mouse buttons

## Bugfixes

- binding a key that you already have a keybind on now asks for confirmation first
- role icons should now reliably work
- Sense Power icons should no longer change mid-window

# Unreviewed

- the grid no longer shifts sideways when adding a spotlight starts a new row or column, and flipping a grow direction now reverses the grid around the first spotlight instead of moving it
- the settings window now opens in combat and stays open when a pull starts, with anything it cannot apply mid-fight landing as soon as combat ends
- click-cast bindings still cannot be captured in combat, and pressing Bind now says so
- closing the settings window part-way through capturing a click binding no longer leaves the capture overlay covering the Click Casting tab when it is re-opened
- the minimap button and /spotlights now open the settings window in combat again after the Appearance or Auras tab has been visited
- switching tabs in the settings window during combat no longer throws a blocked-action error
- "Add all DPS automatically while in a Party" is now a role picker like Auto-Remove's, so tanks and healers can be auto-added too; fresh installs now ship with Damage ticked and the sweep on by default
- a new "Blank Offline Players After" setting turns a disconnected spotlight's cell into an empty spacer after never, instantly, 30 seconds, 1, 3 or 5 minutes, keeping its place in the grid so nothing after it moves, and waiting until you leave combat
- a new "Enabled Specializations" setting lets you pick which specializations Spotlights stays active for account-wide; on any other spec the grid is hidden and the roster is left alone, your slots are kept, and the minimap icon tints red as a reminder
