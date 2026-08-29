Spotlights — World of Warcraft (retail) addon in Lua, singling out individual raid members into their own draggable grid of unit frames.

## Project map

- `*.lua` (root) — core: `Registry.lua`, `SpotlightsUnitFrameMixin.lua`, `Auras.lua`, `Migration.lua`, `Roster.lua`, `Layout.lua`, …
- `Types.lua` — annotations only, meta file, not shipped (see `.pkgmeta`)
- `Options/` — settings UI
- `Localization/` — one file per locale, `enUS.lua` is the source of truth
- `Templates/` — all XML
- `Libs/` — vendored libraries
- `Scratch/` — throwaway in-game test files
- `docs/issues/`, `docs/notes/` — local-only issue and note markdown
- `Spotlights.toc` — load order, interface version
- `.pkgmeta`, `.github/workflows/release.yml` — tag push packages and publishes to CurseForge and Wago

<important if="you are adding or changing user-facing strings">

Strings live in `Localization/`. When adding to one locale, note the gaps in the others so they get closed.
</important>

<important if="you are updating the changelog">

Never edit existing text in `CHANGELOG.md`. Append to a `# Unreviewed` section below it, creating it if absent. Match the style established in git history.
</important>

<important if="you are writing or moving issue docs">

Issues are local-only markdown in `docs/`. Move them to the done folder when starting a new branch. Absolute minimum information — context only where the feature or problem is otherwise not understandable. No narration.
</important>
