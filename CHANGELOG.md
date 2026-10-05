v1.1.2

## Features

- click casting can now be bound to keyboard keys and the mouse wheel, not only mouse buttons
- the settings window is now available in combat
  - changes apply upon leaving combat where needed
  - click-casting cannot be changed in combat
- added Load Conditions
  - you can now disable Spotlights on a per-spec basis
  - the minimap icon will turn red when its currently disabled
- "Add all DPS automatically while in a Party" is now a role picker like Auto-Remove
  - aimed at Augmentation Evokers wanting to focus Tank + DPS in dungeons
- added a new option to automatically remove Offline players from the grid after a configurable time
- added NSRT Nicknames support
  - this still depends on https://github.com/Reloe/NorthernSkyRaidTools/pull/272
  - once its released, you'll also need to `Enable Nicknames` in NSRT Options, then `Enable Spotlights Nicknames`

## Bugfixes

- binding a key that you already have a keybind on now asks for confirmation first
- role icons should now reliably work
- Sense Power icons should no longer change mid-window
- the grid no longer changes position based on the former center anchor when a new row or column is added

# Unreviewed

- players added automatically in a party are now ordered tank first and healer last when Tank or Healer is ticked, and are taken back out of the grid when you leave the party
- Grow Horizontally and Grow Vertically can now be Centered, growing the grid evenly around its position with a short last row or column centered on the rest
- spotlights can now have a border, set under Appearance > Frame > Border
- in a raid, spotlights of members who are not in your instance are now hidden until they arrive, toggled under Roster > Hide Members Outside The Instance (on by default)
