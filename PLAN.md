# Spotlights — Remaining Implementation Plan

All feature work units are complete: WU-0 through WU-8 and WU-10. WU-9 was deliberately punted and has no remaining implementation scope.

What remains is the release work. This phase stays last; any newly discovered product work should be inserted before T5.

## Remaining Phases

| Phase | Status  | Goal                                                         |
| ----- | ------- | ------------------------------------------------------------ |
| T5    | Pending | Add packaging/release automation and verify the shipped zip. |

---

## T5 — Packaging And Release

**Goal.** A tag push builds and publishes the addon, and the shipped zip excludes development-only material.

**Files.**

- `.github/workflows/release.yml`
- `.pkgmeta`

**Release Workflow.**

- Trigger on tag push.
- Use `BigWigsMods/packager@v2`.
- Use repository secrets for release targets.
- Do not include a copied test job unless this project has a real workflow for it.

**Package Metadata.**

- Ignore `.gitignore`, `Types.lua`, `.vscode`, `.github`, and markdown files.
- Do not use a manual changelog block unless a changelog is actually maintained.
- Verify the built zip rather than trusting the ignore list.

**Done When.**

- A tag produces a zip.
- The zip contains no markdown, `Types.lua`, `.vscode`, `.github`, or `.gitignore`.
- Shipped `.lua` files outside `Libs/` contain no comments and keep source line counts.
- `Libs/` is byte-identical to the repository.
- The addon loads from the zip and the retained self-test passes.
