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

Run after every client patch or rendering change:

- [ ] Record addon version, game build/interface and action-bar addon from `/resweep status`.
- [ ] Test radial, rising, bottom and perimeter in both energy and countdown modes.
- [ ] Check zero energy, partial energy, affordability threshold, second spend and regeneration/refund.
- [ ] Test stealth and bar swaps, macro spell detection, talent-adjusted cost, cooldown/GCD overlap.
- [ ] Verify combat and out-of-combat behavior, reload persistence, no Lua errors or blocked actions.
- [ ] Record any fallback or missing API. Native snapshot status does not prove correct rendering.

Only after all relevant checks pass, record build, addon version, date, client configuration and results here and update LAST_TESTED_BUILD in Lua in a subsequent release. A reviewed build is not a tested build. The automated tests mock API contracts and cannot prove secret-value acceptance or taint safety in WoW.
