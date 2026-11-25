# Rogue Energy Sweep v0.4.0 — experimental
Target: World of Warcraft: Forever 1.60.1, Interface 16001.

## Installation and options
Replace the old `RogueEnergySweep` folder under `Interface/AddOns/` with the folder in this ZIP. Your saved variables are retained. Reload the UI (or restart the client), log into a Rogue, and type `/resweep` to open the options panel. The panel is also registered under Settings > AddOns > Rogue Energy Sweep. All settings apply immediately and persist across reloads.

## Four indicator styles
- Rising line: a bright horizontal stripe rises up the icon; optional faint tint below it. Default for new installations and former Auto mode. If the fill-edge anchor is unavailable, a vertical fill is used instead.
- Bottom bar: fills left to right against a dark track.
- Perimeter: fills clockwise along the top, right, bottom, and left edges.
- Radial sweep: legacy deficit shading, with explicit start/end offsets for a full circle. The live client must confirm the geometry.

All four indicators support two progress modes. Energy-based (default) shows the fraction of the ability cost accumulated. Countdown (experimental) starts at zero progress using a post-spend snapshot and fills toward affordability: after spending 45 of 60 energy, the next 45-energy ability progresses from 0% at 15 energy to 50% at 30 energy and disappears at 45. The sweep shows the remaining fraction. Another spend restarts the countdown for affected abilities; a refund advances it. All indicators disappear at affordability. Both modes follow actual energy rather than a fixed time estimate. The options preview has a second slider in countdown mode for post-spend starting energy. The standard cooldown/GCD is not modified. The new options panel has color presets, opacity (15–100%), indicator thickness (2–8 UI units; linear indicators), optional rising fill tint, combat-only and enable switches, three sample icons with a simulated energy slider, a five-second action-bar test, and reset defaults.

## Commands
- `/resweep` or `/resweep options`: open options.
- `/resweep demo`: display 50% progress for five seconds on tracked buttons (out of combat only).
- `/resweep status`: display renderer counts, curve source, last caught API error and interface compatibility.
- `/resweep mode rising|bar|perimeter|radial`: change style.
- `/resweep progress energy|countdown`: switch progress mode across all four styles.
- `/resweep color amber|white|cyan|green|black`: change color. Black is radial-only; linear styles use white instead.
- `/resweep opacity 90`: change opacity.
- `/resweep thickness 4`: change line/bar thickness.
- `/resweep combat`: toggle combat-only.
- `/resweep on` / `/resweep off`: enable or disable.
- `/resweep rescan`: rediscover action buttons.
- `/resweep reset`: restore defaults.

## Patch and update alerts
At login the addon compares the fourth return from `GetBuildInfo()` with its target interface (16001). A mismatch warns once per distinct interface/target pair in saved variables, without disabling the addon. `/resweep status` always reports the current compatibility state when available. A matching interface is not proof of live compatibility; patches can change behavior without changing the interface number. WoW addons cannot query GitHub for updates themselves. Check the repository Releases page or configure an external updater after the repository is published.

## Compatibility and limitations
Blizzard action buttons are the primary target; Bartender4, Dominos, and ElvUI are best effort. Macro support depends on whether the client exposes the underlying spell through `C_ActionBar.GetSpell`. Cost changes depend on the client exposing public costs. Maximum energy defaults to 100 until a public value is available. New non-main-bar buttons may wait for combat to end. Resource events are coalesced at 30 ms; smoothness depends on the client. In-game visual layout, the rising line anchor, cooldown layering, full radial geometry, native secret-value alpha acceptance and actual taint safety are not confirmed by simulation. If a renderer fails, the addon tries the bottom bar; if native alpha or value rendering fails there too, it hides the overlay. Run `/resweep status` and capture any Lua error if something is missing or behaving unexpectedly.

Uses native curves for readiness, deficit, and visibility, with public arithmetic fallback when energy is explicitly non-secret. Native widget methods consume protected curve outputs. Does not perform arithmetic on protected energy values or change secure action button attributes.

Countdown implementation: public energy uses changes in the energy fraction to detect spending. Protected energy uses successful player spellcasts to request a fresh snapshot on the next coalesced update; if the spell identity/cost is protected, a successful non-energy cast can also reset the display. An energy loss not accompanied by a successful cast may not restart the protected countdown; cast/power event order can also affect the snapshot. The native radial StatusBar API normalizes the secret snapshot and current energy fraction for rendering; no protected values are compared or used for Lua arithmetic. Native normalization is experimental. If its public self-test or native calls fail, countdown mode falls back to energy-based progress and `/resweep status` reports that fallback. The source `countdown (native snapshot)` reports that native calls succeeded, not that visual output was verified. Failed cast attempts do not restart the countdown.

Historical validation of v0.3.0 (not rerun for v0.4.0): 26 simulated Lua tests passed in a Lua 5.4 runtime, including existing action discovery behavior, all four modes with simulated secret values, clearing at readiness, options registration and controls, settings updates, preview thresholds, both progress modes, protected snapshot normalization, restart behavior, and safe fallback. This is not a live-client test.

Adapted from Rogue Energy Need 0.2.1 by Vryllak / Rogue Energy Need contributors, MIT licensed. Original license included. Separate experimental derivative, not an official Rogue Energy Need release.
