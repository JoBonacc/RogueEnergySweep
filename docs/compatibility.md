# Live compatibility record

Reviewed baseline: Forever 1.60.1.71091 (2026-11-25).
Last fully live-tested build for v0.6.0: **not recorded**.
Source: [build catalogue](https://foreverdiff.com/builds/1.60.1.71091/), [Blizzard hotfix notes](https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-23-2026/2403040), [addon API notes archive](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes).

## Partial live test — v0.6.0, build 71139, interface 16001

- User reports energy-based rising, bottom and perimeter indicators working; radial invisible in normal use.
- Fixed 50% demo status: five tracked buttons, five radial-capable, five radial active; status alone does not prove pixels were rendered.
- Countdown normalization public self-test failed (line 448); fallback to energy-based confirmed.
- v0.6.1 removes explicit radial angle offsets to restore v0.1.0 geometry. Candidate fix pending live verification. No fully tested build is claimed.

v0.6.1: user confirmed restored radial rendering works. All four energy-based styles reported working across v0.6.0/v0.6.1; complete checklist still pending.

## Live animation smoke test — November 25, 2026

Build 71139, interface 16001: user reported all four countdown styles working in v0.7.0. Together with the earlier v0.6.0/v0.6.1 energy-style checks, all eight animation combinations are reported working. The v0.7.0 bottom-bar status showed five tracked buttons, five bars active, a protected snapshot requesting direct ranges, and no historical API error. The progress summary incorrectly displayed `5: 5`; v0.7.1 fixes the label without changing rendering. The full edge-case checklist below has not been completed, and action-bar configuration was not recorded. No fully live-tested build is claimed. The reviewed baseline remains 71091.

## v0.15.0 combined release-candidate checklist

- [ ] Test all energy-ready effects in the ready dialog and animated main preview. Test real energy thresholds in and out of combat, public vs protected signal paths, fallback enabled/disabled, ability/cooldown/finisher filtering, stealth swaps, no repeated one-shot while ready, and no conflict with native cast/proc/cooldown animations. Verify no taint or errors; capture diagnostic report.

- [ ] Test Solid, Gradient and Luminous in both Rising Line directions and both progress modes. Verify tint off, zero tint opacity, partial fill, zero progress and affordability, color changes, reload persistence and no visual spill beyond the icon. Review diagnostic fallback count.

- [ ] Verify v0.11 cooldown filter ignores GCD, restores overlays after real cooldowns, and respects combo gates, category filters and per-spell exclusions. Verify Death Mark and other newly learned spell ranks if available.
- [ ] Verify target swap, no target and spending the last combo point; test in combat and on a stealth bar.
- [ ] Verify preset/custom color picker, cancel, persistence, separate style appearance and reset behavior.
- [ ] Verify reverse direction for every style in both progress modes, including clipped perimeter direction and rising stripe anchoring.
- [ ] Verify tint opacity and contextual controls; check preview play/stop, manual slider interruption, closing settings and UI scale.
- [ ] Run diagnostic sampling during representative gameplay; capture update count, mean/max callback time, coalesced requests, reported memory and errors. Compare behavior with addon disabled if needed. No measured client performance is claimed yet.
- [ ] Review and copy the diagnostic report; verify no unexpected information before sharing.
- [ ] Capture public screenshots, confirm packaging, attribution and compatibility language before distribution.

Run after every client patch or rendering change:

- [ ] Record addon version, game build/interface and action-bar addon from `/resweep status`.
- [ ] Test radial, rising, bottom and perimeter in both energy and countdown modes.
- [ ] Check zero energy, partial energy, affordability threshold, second spend and regeneration/refund.
- [ ] Test stealth and bar swaps, macro spell detection, talent-adjusted cost, cooldown/GCD overlap.
- [ ] Verify combat and out-of-combat behavior, reload persistence, no Lua errors or blocked actions.
- [ ] Record any fallback or missing API. Native snapshot status does not prove correct rendering.

Only after all relevant checks pass, record build, addon version, date, client configuration and results here and update LAST_TESTED_BUILD in Lua in a subsequent release. A reviewed build is not a tested build. The automated tests mock API contracts and cannot prove secret-value acceptance or taint safety in WoW.

## v0.16.0 tracker checklist
- [ ] Enable tracker, test all five layouts, drag group and freeform icons, lock, reload, disable action bars and restore them.
- [ ] Verify Dial alignment at public known thresholds, 0 and maximum; verify fallback and secret values in combat. Check duplicate/close-cost markers and high UI scale.
- [ ] Verify bar/ring/icon energy and countdown modes, selection, filters, ready effects, stealth/page swaps, cost changes, persistence, mouse transparency and performance.

## v0.17.0 checklist
- [ ] Configure repeat and follow-up pips, check colors, partial fills, templates, cap, placement, talent changes, and energy-only predictions. Test GCD projection with public and protected timing, off-GCD spells, no GCD, and cooldown/combo filters. Inspect diagnostic paths.
- [ ] Test all four breakpoint layouts, duplicate/talent-adjusted costs, manual selection, protected energy, labels, arc alignment, stable markers during cooldowns/finishers, and tracker GCD projection.

## v0.18.0 Arsenal checklist
- [ ] Test all four Arsenal styles in both orientations, with icons/names/costs hidden or shown. Change color and repeat settings in Ability Chains with action-button pips disabled. Verify manual selection, talent cost changes, one-pip utility defaults, all-repeat option, count fallback in combat, stable placement and click-through. Verify shared energy semantics and no Lua/taint errors.

## v0.19.0 warning checklist
- [ ] Verify positive rule migration; cycle local and global conditions, global priority and duplicate suppression, warning visibility only inside the energy window, over-cap thresholds, pulsing and disabled cleanup. Test Kick global rule, cost changes, protected values and action-bar paging. Warnings are energy-only and ignore target cooldowns.

## v0.20.0 settings checklist
- [ ] Open through slash and addon Settings, navigate every page, scroll at different UI scales, test previews, configure all HUD families and shared colors, edit global/local rules, use quick setup and reset. Check saved preference persistence and independent action sweep/planning switches. Verify no UI or taint errors in combat; legacy fallback remains available.

## v0.20.1
- [ ] With GCD-aware enabled, use Sinister Strike from 100 energy with Backstab (60 cost) tracked. Confirm no deficit flash, with ready effects off and on. Test low-energy casts, GCD expiry, off-GCD abilities, combat and protected/native fallback; check cumulative diagnostics. Confirm planning pips unaffected.

## v0.20.2
- [ ] Verify 29515 source availability outside and inside combat, projection counts and last unavailable reason, real deficits remain visible, no GCD-wide visual hold. Test 100-energy Sinister Strike -> Backstab only if public projection is available.

## v0.21.0
- [ ] Verify additional/total selection on 45-energy builder at 45/80/100 energy, partial and inactive modes, persistence, Arsenal total counts and unchanged follow-up warnings. Check larger/outside pips, left/center/right alignment, shapes, outline, brightness, opacity, and offset with adjacent bars. Confirm GCD prediction is absent from both settings interfaces and real energy remains visible.
