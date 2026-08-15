v1.1.0

## Bugfixes

- fixed a bug where unit range was not reliably asserted
- fixed a bug where the available raid members to spotlight would not update instantly upon roster changes when the frame was open
- fixed a bug where aura previews kept showing spells that were toggled off
- fixed a bug where the gap between pooled aura icons only reached displays built afterwards
- fixed a bug where player names were leaking out of the frame
- fixed a bug where importing a profile exported by a newer version made this account skip that version's settings migration for good; such a profile is now refused with a prompt to update the addon
- fixed a bug where importing a profile carried the exporter's minimap button state and left the button unable to be toggled until the next reload
- fixed a bug where a read-only export box re-encoded the whole profile on every keystroke
- fixed a bug where picking a color inverted its opacity, leaving the color selection button black and the color invisible until the picker was opened again

## Features

- the options panel was rebuilt from scratch and a lot of settings were added:
  - added Health Text customization to Frame settings
  - color pickers now allow opacity
  - exposed inputs for all sliders
  - default icon size was reduced
  - moved Prescience/Sense Power tabs to the bottom of the frame
  - added a checkbox per-class in order to toggle inclusion of all of that specs abilities
  - Status Bars can now be vertically aligned
  - added Show Name
  - added Show Name On Hover Only
  - added Name Strata
- enabled Auras system for non-Evokers
  - non-Augmentation Evokers now can customize "Cooldowns & Custom Auras" and "Defensives"
    - "Cooldowns & Custom Auras" uses the same list the Sense Power feature uses
      - these are all _trackable_ major cooldowns except for summons such as Demonic Tyrant as those are not trackable via aura
    - "Defensives" uses the games own list for defensive auras, amended with a couple spells the default ui currently does not consider as such
    - these additional auras are off by default
- Defensives now cover Power Word: Barrier, Anti-Magic Zone and Darkness, tracked on the players standing in them
- options panel labels too long for their column now show their full text in a tooltip on hover
- added Import / Export support
- added Roster Presets which can also be imported and exported
- added a third display option: Square
- added a fourth display option: Text, a bare duration countdown with its own font, size, color and placement
- added a fifth display option: Frame Color - colors the entire health bar for as long as the aura is up
- right-clicking the minimap button now opens the Roster tab directly
- spotlights now render in a party, not only in a raid
- Clear Roster When Leaving The Group now also clears when a party becomes a raid, or a raid a party
- Roster tab shows role icons and class color
- the Unrostered list can now be narrowed to chosen roles, and the dropdown that narrows it is now captioned
- roles can now be set to be removed from the grid automatically, keeping tanks or healers out of every preset and every add
- aura appearance sections whose display is switched off now start collapsed
- the Auras tab preview frame now wears your own class color instead of a fabricated one
- added Fill Direction to Status Bars

### Augmentation-specific

- added Shifting Sands as dedicatedly trackable and customizable aura
- aura preview now has a second preview the moment you enable more than one display kind for an aura (e.g. Status Bar and Text for Prescience), so you can see them at the same time

# Unreviewed

- the Sense Power prompt has a second button, Ignore until Reload, which silences it for the rest of the session
- custom auras are their own category now, available to every specialization, and no longer appear in Cooldowns, Defensives or Sense Power
- icons of a category tracking several auras at once have a Grow Direction, so they can flow left, right, up or down from where they are anchored instead of always running right off the frame
- aura categories another specialization owns are hidden from the category strip instead of shown greyed out
- added Click Casting: click bindings that cast a spell on Spotlights frames and nowhere else, made by entering a spell ID and pressing the mouse button you want it on
- the options panel is wider, so the new tab fits beside the existing six
