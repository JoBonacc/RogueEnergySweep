# Rogue Energy Sweep v0.2.0 — experimental
Target: World of Warcraft: Forever 1.60.1, Interface 16001.

## Installation and options
Replace the old `RogueEnergySweep` folder under `Interface/AddOns/` with the folder in this ZIP. Your saved variables are retained. Reload the UI (or restart the client), log into a Rogue, and type `/resweep` to open the options panel. The panel is also registered under Settings > AddOns > Rogue Energy Sweep. All settings apply immediately and persist across reloads.

## Four indicator styles
- Rising line: a bright horizontal stripe rises up the icon; optional faint tint below it. Default for new installations and former Auto mode. If the fill-edge anchor is unavailable, a vertical fill is used instead.
- Bottom bar: fills left to right against a dark track.
- Perimeter: fills clockwise along the top, right, bottom, and left edges.
- Radial sweep: legacy deficit shading, with explicit start/end offsets for a full circle. The live client must confirm the geometry.

Each linear indicator shows the fraction of the ability's energy cost you have accumulated. All indicators disappear at affordability. They reflect current energy, not estimated time or an assumed regeneration rate. The standard cooldown/GCD is not modified. The new options panel has color presets, opacity (15–100%), indicator thickness (2–8 UI units; linear indicators), optional rising fill tint, combat-only and enable switches, three sample icons with a simulated energy slider, a five-second action-bar test, and reset defaults.

## Commands
- `/resweep` or `/resweep options`: open options.
- `/resweep demo`: display 50% progress for five seconds on tracked buttons (out of combat only).
- `/resweep status`: display renderer counts, curve source and last caught API error.
- `/resweep mode rising|bar|perimeter|radial`: change style.
- `/resweep color amber|white|cyan|green|black`: change color. Black is radial-only; linear styles use white instead.
- `/resweep opacity 90`: change opacity.
- `/resweep thickness 4`: change line/bar thickness.
- `/resweep combat`: toggle combat-only.
- `/resweep on` / `/resweep off`: enable or disable.
- `/resweep rescan`: rediscover action buttons.
- `/resweep reset`: restore defaults.

## Compatibility and limitations
Blizzard action buttons are the primary target; Bartender4, Dominos, and ElvUI are best effort. Macro support depends on whether the client exposes the underlying spell through `C_ActionBar.GetSpell`. Cost changes depend on the client exposing public costs. Maximum energy defaults to 100 until a public value is available. New non-main-bar buttons may wait for combat to end. Resource events are coalesced at 30 ms; smoothness depends on the client. In-game visual layout, the rising line anchor, cooldown layering, full radial geometry, native secret-value alpha acceptance and actual taint safety are not confirmed by simulation. If a renderer fails, the addon tries the bottom bar; if native alpha or value rendering fails there too, it hides the overlay. Run `/resweep status` and capture any Lua error if something is missing or behaving unexpectedly.

Uses native curves for readiness, deficit, and visibility, with public arithmetic fallback when energy is explicitly non-secret. Native widget methods consume protected curve outputs. Does not perform arithmetic on protected energy values or change secure action button attributes.

Validation: 20 simulated Lua tests passed in a Lua 5.4 runtime, including existing action discovery behavior, all four modes with simulated secret values, clearing at readiness, options registration and controls, settings updates, and preview thresholds. This is not a live-client test.

Adapted from Rogue Energy Need 0.2.1 by Vryllak / Rogue Energy Need contributors, MIT licensed. Original license included. Separate experimental derivative, not an official Rogue Energy Need release.
