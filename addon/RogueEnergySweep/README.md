# Rogue Energy Sweep v0.1.0 — experimental
Target: World of Warcraft: Forever 1.60.1, Interface 16001.

Displays an amber radial swipe on existing Rogue action buttons showing the fraction of a spell's energy cost that is still missing. At 20 energy, a 45-energy spell is 25/45 shaded; a 25-energy spell is 5/25 shaded. At the required energy the shading clears. This is a live resource display, not a predicted countdown: changes in energy (including refunds or spending on other abilities) immediately change the displayed deficit. Normal cooldown and GCD widgets are not modified. There is no hard-coded regeneration rate, countdown text, automatic casting, or rotation logic.

## Installation
Extract the `RogueEnergySweep` folder into the Forever client's `Interface/AddOns/` directory (typically `World of Warcraft/_forever_/Interface/AddOns/`). The TOC and Lua files should be immediately inside the `RogueEnergySweep` folder. Restart the game if newly installed, enable it in the character selection AddOns list, and log into a Rogue. The original Rogue Energy Need addon can coexist, but disabling it for the initial test avoids overlapping displays.

## Commands
- `/resweep` — show commands.
- `/resweep demo` — display 50% shading for five seconds on detected energy-cost abilities (out of combat only).
- `/resweep status` — report tracked ability buttons, radial API support, active renderer, source of energy values, and the last caught native API error. No raw secret values are printed.
- `/resweep opacity 65` — adjust opacity, from 15 to 90 percent.
- `/resweep color amber` or `/resweep color black` — choose sweep tint.
- `/resweep mode auto` — default: radial when accepted, thin gold deficit bar otherwise.
- `/resweep mode radial` — force radial, hide overlay if unavailable.
- `/resweep mode bar` — force thin gold deficit bar.
- `/resweep combat` — toggle combat-only display.
- `/resweep on` or `/resweep off` — enable or disable.
- `/resweep rescan` — rediscover action buttons (deferred in combat).
- `/resweep reset` — restore defaults.

## Suggested live test
1. At full energy, run `/resweep demo`. Confirm the partial overlay appears on energy-cost abilities only.
2. At a target dummy or in combat, spend energy until Sinister Strike is unaffordable. Confirm the sweep grows immediately when energy is spent and clears when enough energy returns. Check Kick, a finisher, and an actual cooldown at the same time.
3. Enter/leave stealth and verify the displayed costs follow the new page. Check `/resweep status` in combat and after combat. A secret native curve is expected when power is restricted, if the client exposes that restriction.
4. If the sweep is missing or only a thin bar appears, copy the `/resweep status` output. For Lua errors, use `/console scriptErrors 1`, reload, and capture the first error. Disable the addon if it interferes with normal play.

## Compatibility / limitations
Blizzard action buttons are the primary target. Bartender4, Dominos, and ElvUI are best effort based on exposed action slots and standard button names. Macros work only if the client exposes their spell through `C_ActionBar.GetSpell`; complex conditional macros are not interpreted. Cost changes are supported to the extent the client exposes them; an unreadable cost hides the overlay. The maximum energy defaults to 100 until the game provides a public value, and the last readable maximum is retained. Newly discovered non-main-bar buttons may wait until combat ends. Energy updates are coalesced at 30 ms; visual smoothness depends on client power events. The native radial mask's actual direction/origin and coexistence with cooldown layers need in-game visual confirmation.

Uses `C_CurveUtil.CreateCurve` and `UnitPowerPercent` to map protected energy to a normalized deficit. The result is passed directly to `Texture:SetRadialProgressBarPercent` (or `StatusBar:SetValue` if radial is unavailable). Public arithmetic is used only if no usable native curve result is available and the energy value is explicitly non-secret. The implementation does not read or change secure action state beyond reading the slot attribute.

Validation: 15 simulated Lua tests passed (Lua 5.4 runtime). These check thresholds, simulated restricted-value passthrough, fallback rendering, public fallback, page changes, cost/max-energy changes, coalesced energy events, mode switches, demo, and stale overlays. The simulation is not a WoW client and cannot establish taint safety, real radial appearance, event cadence, or live compatibility. No live game test has been performed.

Based on Rogue Energy Need 0.2.1 by Vryllak / Rogue Energy Need contributors, MIT licensed. Original license included. This is a separate experimental derivative, not an official Rogue Energy Need release.
