# Changelog

## v0.6.1
- Restore the original radial texture geometry by removing explicit start/end offsets; targeted candidate fix for invisible radial overlays on build 71139.
- Add a regression guard for the default radial geometry. Other rendering and countdown normalization are unchanged.
- Record partial live test results for v0.6.0. This fix is not yet live-tested.

## v0.6.0
- Detect new client builds independently of interface changes; deduplicate warnings and keep overlays enabled.
- Display running build, reviewed baseline 71091 and last live-tested build (not recorded) in status output.
- Added mocked API contract regression tests and live-client compatibility checklist.
- No changes to rendering behavior. Reviewed baseline is not a claim of live compatibility.

## v0.5.0
- Release ZIP now uses the `-forever.zip` suffix and includes a matching Forever-specific TOC for WowUp detection.
- Added root MIT license, direct upstream attribution, and public installation and support documentation.
- Retained existing issue templates and interface target 16001. Rendering behavior is unchanged; full live-client testing remains pending.

## v0.4.0
- Added login-time interface mismatch warning and compatibility details to `/resweep status`.
- Warnings are deduplicated in saved variables; mismatches do not disable the addon.
- Added repository history, release packaging, CI validation, and issue templates.
- Existing overlay rendering and settings are unchanged. Target interface remains 16001; not yet live-tested.

## v0.3.0
- Energy-based and experimental countdown-based progress across all four styles.
- Added countdown preview controls, native protected-value normalization and safe fallback.

## v0.2.0
- Added rising line, bottom bar and perimeter styles; retained radial sweep.
- Added in-game options, visual controls and preview.

## v0.1.0
- Initial standalone energy readiness sweep with native curves and fallback bar.
