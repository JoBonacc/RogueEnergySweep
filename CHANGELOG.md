# Changelog

## v0.9.0
- Optional target combo-point filter for finisher overlays across all styles and progress modes. Defaults off; demo and simulated preview bypass it.
- Detect ranked finishers and required combo-point power costs; refresh on target and combo-point changes. Use target-specific API, fail closed when unavailable, and report gate source in status.
- Add mocked finisher detection, public/protected combo gate and event coverage. Live-client verification pending.

## v0.8.0
- Add eight named color swatches and a native custom RGB color picker, with live action-bar and options previews, cancel restoration and saved custom color.
- Support exact hex colors through `/resweep color #RRGGBB`; preserve existing presets, default gold and the legacy black-preset behavior. Opacity remains separate.
- Add regression tests for color migration, RGB/hex validation, picker callbacks and cancellation. No changes to countdown or energy rendering logic beyond color selection. Native picker needs live-client verification.

## v0.7.1
- Correct actual-progress labels in chat and options (e.g. `native countdown: 5` instead of `5: 5`).
- Add a regression test for mixed progress states and empty indicators.
- Record successful live animation smoke tests on build 71139 across v0.6.0–v0.7.0. Rendering is unchanged; full compatibility checklist remains pending.

## v0.7.0
- Replace failed protected countdown normalization readback with direct native status-bar ranges for rising, bottom, radial and clipped perimeter styles.
- Preserve energy-based renderers and reset linear ranges when switching back to energy progress.
- Show actual progress and per-button fallback diagnostics in options and status; retry rejected native ranges on a new snapshot or style change.
- Add mocked direct-range, fallback and state restoration regression tests. Live client behavior is unverified.

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
