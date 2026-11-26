# Rogue Energy Sweep v0.13.0 — release candidate
Target: World of Warcraft: Forever 1.60.1, Interface 16001.

## Installation and options
Replace the old `RogueEnergySweep` folder under `Interface/AddOns/` with the folder in this ZIP. Your saved variables are retained. Reload the UI (or restart the client), log into a Rogue, and type `/resweep` to open the options panel. The panel is also registered under Settings > AddOns > Rogue Energy Sweep. All settings apply immediately and persist across reloads. Settings are grouped into Behavior, Animation style, Progress mode, Appearance and Preview. Tint is shown only for Rising Line; thickness is shown for Rising Line, Bottom Bar and Perimeter, not Radial Sweep. Hidden controls preserve their saved values.

## Four indicator styles
- Rising line: a bright horizontal stripe rises up the icon; optional faint tint below it. Default for new installations and former Auto mode. If the fill-edge anchor is unavailable, a vertical fill is used instead.
- Bottom bar: fills left to right against a dark track.
- Perimeter: fills clockwise along the top, right, bottom, and left edges.
- Radial sweep: legacy deficit shading, with native default full-circle geometry restored from v0.1.0. Reported working in the v0.7.0 animation smoke test; current release candidate requires retesting.

All four indicators support two progress modes. Energy-based (default) shows the fraction of the ability cost accumulated. Countdown (experimental) starts at zero progress using a post-spend snapshot and fills toward affordability: after spending 45 of 60 energy, the next 45-energy ability progresses from 0% at 15 energy to 50% at 30 energy and disappears at 45. The sweep shows the remaining fraction. Another spend restarts the countdown for affected abilities; a refund advances it. All indicators disappear at affordability. Both modes follow actual energy rather than a fixed time estimate. The options preview has a second slider in countdown mode for post-spend starting energy. The standard cooldown/GCD is not modified. The new options panel has eight color swatches, a native custom RGB color picker with live preview and cancel restoration, opacity (15–100%), indicator thickness (2–8 UI units; linear indicators), optional rising fill tint, combat-only and enable switches, three sample icons with a simulated energy slider, a five-second action-bar test, and reset defaults.

## Finisher filtering
Enable **Finishers only with combo points on target** to hide energy overlays on finishers unless your current target has at least one combo point. Works independently of style and progress mode. Known ranked finishers and spells with a required combo-point cost are detected; other abilities are unaffected. Target swaps and combo-point events refresh the display. The setting defaults off; the demo and simulated preview ignore this gate. If target-specific combo points cannot be displayed safely, finisher overlays are hidden rather than showing stale points. `/resweep status` reports the gate source and number of detected finishers. Protected-value behavior needs live verification.

## Ability filters
Use **Ability filters...** to uncheck individual discovered energy abilities. Exclusions apply by spell ID to all matching buttons and are saved; new ranks may need to be excluded separately. **Hide on cooldown (ignore GCD)** uses native spell cooldown duration objects to suppress overlays on cooldown, excluding the global cooldown. If unavailable, effects remain visible. Both filters are optional, default off/empty, and bypassed by the demo. The preview is unaffected. Live verification is pending.

## Appearance and preview
Each style remembers its own color, opacity, thickness, direction, tint and tint opacity. Existing shared values are copied to all four styles on upgrade. **Reset style** restores only the current appearance; **Reset all** requires confirmation in options. Reverse direction is available for all four animations. Rising fill tint has independent opacity (relative to the main opacity). Animate runs a simulated 10 energy/sec regeneration cycle in the preview and stops at 100, on manual slider changes or when closing the settings. It does not change live energy or cast spells.

## Diagnostics
Use **Diagnostics** or `/resweep diagnostics` to open a selectable report. Click Select report and press Ctrl+C; WoW does not permit addons to write directly to the system clipboard. Review before sharing. Start sampling enables session-local timing of addon update callbacks; stop retains the sample. Reported memory is a client estimate and timing is not a full frame-rate/CPU profiler. No profiling is enabled by default. Actual performance and live compatibility still require in-game validation.

## Commands
- `/resweep` or `/resweep options`: open options.
- `/resweep demo`: display 50% progress for five seconds on tracked buttons (out of combat only).
- `/resweep status`: display renderer counts, curve source, last caught API error and interface compatibility.
- `/resweep mode rising|bar|perimeter|radial`: change style.
- `/resweep progress energy|countdown`: switch progress mode across all four styles.
- `/resweep color amber|white|cyan|green|red|purple|orange|black` or `/resweep color #RRGGBB`: change color. The legacy black preset uses white in linear styles; a custom RGB color applies exactly to every style. Opacity is separate. If the native picker is unavailable, use the hex command.
- `/resweep opacity 90`: change opacity.
- `/resweep diagnostics`: open the diagnostic report.
- `/resweep profile on|off`: start/reset or stop the update sampler.
- `/resweep reverse`: reverse the active style.
- `/resweep tintopacity 15`: set rising tint opacity (0–100).
- `/resweep resetstyle`: reset only active appearance.
- `/resweep thickness 4`: change line/bar thickness.
- `/resweep finishers on|off`: enable or disable target combo-point filtering (omit argument to toggle).
- `/resweep filters`: open individual ability filters.
- `/resweep cooldowns on|off`: toggle cooldown filtering.
- `/resweep combat`: toggle combat-only.
- `/resweep on` / `/resweep off`: enable or disable.
- `/resweep rescan`: rediscover action buttons.
- `/resweep reset`: restore defaults.

## Patch and update alerts
At login the addon also compares the client build (second GetBuildInfo return) with reviewed baseline 71091 and warns once per newer build. /resweep status displays the running build, baseline and last fully live-tested build (not recorded). At login the addon compares the fourth return from `GetBuildInfo()` with its target interface (16001). A mismatch warns once per distinct interface/target pair in saved variables, without disabling the addon. `/resweep status` always reports the current compatibility state when available. A matching interface is not proof of live compatibility; patches can change behavior without changing the interface number. WoW addons cannot query GitHub for updates themselves. Check the repository Releases page or use WowUp's Install from URL with https://github.com/JoBonacc/RogueEnergySweep for external updates.

## Compatibility and limitations
Blizzard action buttons are the primary target; Bartender4, Dominos, and ElvUI are best effort. Macro support depends on whether the client exposes the underlying spell through `C_ActionBar.GetSpell`. Cost changes depend on the client exposing public costs. Maximum energy defaults to 100 until a public value is available. New non-main-bar buttons may wait for combat to end. Resource events are coalesced at 30 ms; smoothness depends on the client. In-game visual layout, the rising line anchor, cooldown layering, full radial geometry, native secret-value alpha acceptance and actual taint safety are not confirmed by simulation. If a renderer fails, the addon tries the bottom bar; if native alpha or value rendering fails there too, it hides the overlay. Run `/resweep status` and capture any Lua error if something is missing or behaving unexpectedly.

Uses native curves for readiness, deficit, and visibility, with public arithmetic fallback when energy is explicitly non-secret. Native widget methods consume protected curve outputs. Does not perform arithmetic on protected energy values or change secure action button attributes.

Countdown implementation: public energy uses changes in the energy fraction to detect spending. Protected energy uses successful player spellcasts to request a fresh snapshot on the next coalesced update; if the spell identity/cost is protected, a successful non-energy cast can also reset the display. An energy loss not accompanied by a successful cast may not restart the protected countdown; cast/power event order can also affect the snapshot. Protected countdown now passes the post-spend snapshot directly to native status bar ranges, without reading back a radial texture. Bottom and rising use native linear ranges, radial uses a native radial status bar, and perimeter uses four clipped bars with the same full range. If a widget rejects the protected range or clipping is unavailable, that button falls back to energy-based progress until a new snapshot or style change. Options and `/resweep status` show actual progress state and per-button API errors. Native direct range is experimental; successful calls do not prove visual output, and perimeter clipping may be unavailable in Forever. Failed cast attempts do not restart the countdown.

Historical validation of v0.3.0 (not rerun for v0.4.0): 26 simulated Lua tests passed in a Lua 5.4 runtime, including existing action discovery behavior, all four modes with simulated secret values, clearing at readiness, options registration and controls, settings updates, preview thresholds, both progress modes, protected snapshot normalization, restart behavior, and safe fallback. This is not a live-client test.

Adapted from [Rogue Energy Need](https://www.curseforge.com/wow/addons/rogue-energy-need) 0.2.1 by Vryllak / Rogue Energy Need contributors, MIT licensed. Original license included. Separate experimental derivative, not an official Rogue Energy Need release.
