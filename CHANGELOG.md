# Changelog

## v0.24.1
- Capture Gouge target aura, Kick/Gouge cooldowns, actual cast cooldowns and Classic/Retail GCD probes in the diagnostic recorder; report cooldown-event-only GCD flags.
- Preserve exact numeric IDs and emit changed fields only. No gameplay behavior changed.

## v0.24.0
- Add opt-in API diagnostics, live self-test, bounded session-only combat recording and copyable report. No gameplay prediction changes.
- Fix stale version label in existing diagnostics.

## v0.23.1
- Fix Improved Gouge lookup using Forever active combat trait config and active rank; cache and refresh on talent/config changes. No guessed zero rank if lookup fails.
- Record live combo-point secrecy verification; continue using actual target combo points in combat.

## v0.23.0
- Per-relationship automatic timing with Next GCD, Control window and Custom; 0.5s configurable safety margin. Known Gouge, Cheap Shot, Kidney Shot and Blind durations, talent rank and public target combo points where available. GCD included in control duration. Preserve explicit longer v0.22 windows.
- Refresh timing after talent and combo changes; hide unavailable control predictions instead of inventing protected combo values. Existing global reservations, repeat counts and energy sweep unchanged.
- Correct the earlier protected countdown regression test fixture.

## v0.22.0
- Add per-source local follow-up timing windows, defaulting to one second. Longer windows scale the existing assumed energy/GCD; global reservations and repeat budgets remain unchanged.
- Add opt-in independent follow-up pip shape, size, placement, alignment, spacing, outline, brightness, inactive opacity and offset. Preserve existing shared appearance and warning glyphs by default.

## v0.21.1
- Fix countdown animation restarting on free abilities such as Pick Pocket. Only confirmed positive energy costs trigger cast-based snapshot resets; nil, unavailable, protected and zero costs preserve the previous snapshot. Public energy decreases still reset naturally. Diagnostics report confirmed resets and skipped free/unknown casts.

## v0.21.0
- Ability planning repeat pips now represent additional casts by default; choose Total casts to include the first. Standalone Arsenal continues to show total casts. Follow-up opportunities and warning thresholds are unchanged.
- New action-button pip visibility controls: outside/inside placement, alignment, circle/square/diamond repeat shapes, size up to 24px, spacing, contrast outline, brightness, inactive opacity, expanded offset. Existing colors and rules retained.
- Retire GCD-aware energy prediction, including saved flag, options, runtime hooks and module. Actual-energy sweep and planning's explicit regeneration assumption remain independent.

## v0.20.2
- Remove GCD-wide visual suppression and estimated cast-event holds. Accurate prediction only when public GCD duration and regeneration are readable. Prefer Forever's TEST Scorch (29515) over the Retail GCD dummy. Diagnostics record timing availability and actual projections; real deficits are never hidden by a fallback. In-combat projection remains unverified.

## v0.20.1
- Fix GCD-aware readiness flicker when exact timing or regeneration is protected. Use a separate native GCD visibility gate or a confirmed active GCD hold instead of showing transient deficits during the lockout. Public prediction remains preferred; when neither timing nor active state is available, a bounded hold from a public cast/cooldown event is used for known GCD-bound abilities. Unknown/off-GCD abilities keep actual-energy behavior. Preserve planning pips and shared HUD energy.
- Suppress false ready transitions during confirmed fallback holds and refresh after GCD expiry. Diagnostics include projection and fallback counts and last fallback path.

## v0.20.0
- Replace the normal settings experience with one scrollable, navigable window: Action bars, Energy HUD, Ability planning, Advanced and Quick setup. Contextual appearance and behavior pages, grouped visual HUD picker, direct Kick reservation, explicit local/global follow-up conditions, and native action preview.
- Preserve all saved preferences and existing slash commands; legacy options remain available as `/resweep legacy`. Action-bar readiness, planning pips and repeat pips can be enabled independently; the advanced master switch still controls all features.

## v0.19.0
- Ability Chains supports per-relationship opportunity and warning indicators, plus global follow-up rules applied across other energy-spending buttons. Warning diamonds use the target ability color and an exclamation cutout, optionally pulsing, only while the source is affordable and the follow-up would be unaffordable after the configured GCD regeneration. Globals take precedence (warnings first), with up to three visible follow-up slots. Existing positive rules migrate unchanged.
- `/resweep chains kick` enables a global Kick warning if Kick is discovered on an action bar. No protected energy arithmetic; native bounded curves drive warnings. Energy-only, not a target cooldown or combo-point prediction.

## v0.18.0
- Add Energy Arsenal, a movable standalone tracker layout displaying alternative repeat-cast budgets as colored circles, diamonds, rectangular charges or public numeric counts (native pip fallback if protected). Horizontal rows or vertical stacks; optional icons, names and costs.
- Reuse Ability Chains' palette, repeat definitions, native curves, partial fills, hide-inactive preference, repeat cap and assumed energy per GCD even with action-button pips disabled. Use the existing tracker ability picker and category/ability exclusions. Non-builders default to one pip unless configured or all-repeats is enabled. Energy-only estimates ignore cooldown/combo/positional constraints; all rows spend the same shared pool.

## v0.17.0
- Add four icon-free Energy Breakpoints layouts: Segments, Staircase, Lights and Arc. Unique public ability costs determine the stationary thresholds; current energy fills native widgets.
- Add optional Ability Chains repeat and follow-up pips with templates, per-ability rules and colors, partial repeat progress, size/spacing/opacity/offset settings, and configurable assumed energy per GCD.
- Add experimental GCD-aware readiness using public GCD timing and regeneration; protected timing falls back to actual energy. Countdown snapshots remain actual-energy based.

## v0.16.0
- Add optional standalone Energy Tracker: Dial, Bars, Icons, Freeform and concentric Rings layouts with independent appearance, movable locked/unlocked frames, manual ability selection and action-bar display toggle.
- Share native energy/cost groups, countdown snapshots and filtering with the original overlays. Dial uses original transparent ring artwork and static cost markers; numeric energy only when public. Add diagnostics and a separate settings window.
- Tracker disabled by default. Native geometry, layout, placement and performance require live validation.

## v0.15.0
- Add global energy-ready effects: native cast burst, cooldown flash, proc glow, halo, custom border, pulse and soft flash. None remains the default.
- Use a separate native readiness alpha curve and existing ability, combo and cooldown gates. One-shots trigger only from explicitly public transitions (energy or conservative non-finisher power usability); optional pulse fallback for protected transitions.
- Add a compact ready effects dialog, native artwork preview, intensity, match color, diagnostics, and mocked readiness/transition tests. No existing Blizzard action button effect frames are modified. Live verification pending.

## v0.14.0
- Add Solid, Gradient and Luminous Rising Line fill effects, with a gradient following the native fill region and additive blending for Luminous. Reverse direction flips the fade; both progress modes share the same appearance path.
- Preserve Solid as the default and persist the selected fill effect per style. Contextual settings appear only when Rising Line tint is enabled.
- Fall back to solid if gradient setup fails; report fallback count in diagnostics. Compact appearance layout to make room for the new controls.
- Add mocked gradient, direction, migration, fallback and layout tests. Live visual verification pending.

## v0.13.0
- Add builder, finisher and Other/utility category filters alongside per-ability exclusions; include Death Mark as a Forever finisher, retain unknown spells in Other.
- Preserve independent appearance settings per style; migrate old shared settings without changing the selected style. Add per-style reset and confirmation for resetting all settings in options.
- Add independent rising tint opacity, reversed animation direction for all four styles, and an animated regeneration preview that stops when the settings close.
- Add a selectable diagnostic report, optional session-local update timing, request coalescing counts and client-reported memory estimate.
- Update public documentation and live test checklist; add mocked migration, direction, preview and profiling regression coverage. Live-client testing and public distribution remain pending.

## v0.11.0
- Add optional per-ability exclusions with a paginated named/icon list of tracked and excluded spells.
- Add optional cooldown filtering using native duration objects with GCD excluded; fail open when the API is unavailable. Separate display gates preserve combo-point and energy opacity.
- Refresh on cooldown and charge events; filters are bypassed for the demo. Add regression tests and status diagnostics. Live verification pending.

## v0.10.1
- Move section divider lines alongside headings so they cannot cross preceding sliders.
- Give the Rising Line thickness slider and tint checkbox separate rows, with additional spacing before Progress mode, Appearance and Preview.
- Add layout spacing regression assertions. No changes to rendering or saved settings; in-game layout verification pending.

## v0.10.0
- Group options into Behavior, Animation style, Progress mode, Appearance and Preview with section dividers.
- Move style-specific controls below the style selector; hide and disable tint outside Rising Line and thickness for Radial Sweep. Preserve saved values when switching styles.
- Highlight selected style and progress buttons; make checkbox labels clickable, and keep preview controls contextual.
- Add mocked contextual-control tests. Rendering behavior is unchanged; live layout verification pending.

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
