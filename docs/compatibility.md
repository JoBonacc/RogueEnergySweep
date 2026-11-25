# Live compatibility record

Reviewed baseline: Forever 1.60.1.71091 (2026-11-25).
Last fully live-tested build for v0.6.0: **not recorded**.
Source: [build catalogue](https://foreverdiff.com/builds/1.60.1.71091/), [Blizzard hotfix notes](https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-23-2026/2403040), [addon API notes archive](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes).

Run after every client patch or rendering change:

- [ ] Record addon version, game build/interface and action-bar addon from `/resweep status`.
- [ ] Test radial, rising, bottom and perimeter in both energy and countdown modes.
- [ ] Check zero energy, partial energy, affordability threshold, second spend and regeneration/refund.
- [ ] Test stealth and bar swaps, macro spell detection, talent-adjusted cost, cooldown/GCD overlap.
- [ ] Verify combat and out-of-combat behavior, reload persistence, no Lua errors or blocked actions.
- [ ] Record any fallback or missing API. Native snapshot status does not prove correct rendering.

Only after all relevant checks pass, record build, addon version, date, client configuration and results here and update LAST_TESTED_BUILD in Lua in a subsequent release. A reviewed build is not a tested build. The automated tests mock API contracts and cannot prove secret-value acceptance or taint safety in WoW.
