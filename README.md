# Rogue Energy Sweep

Customizable energy readiness indicators directly on your Rogue action buttons in **World of Warcraft: Forever**. See how close an ability is to becoming affordable without constantly looking at your energy bar.

**Release candidate:** Targets interface 16001 (Forever 1.60.1). All eight style/progress combinations were reported working in earlier live smoke tests on build 71139; the combined release candidate still requires testing.

## Install and update

**WowUp (recommended):** Select your Forever client, choose Get Addons → Install from URL, and enter `https://github.com/JoBonacc/RogueEnergySweep`. The v0.5.0 and later releases are packaged for Forever detection. Enable auto-update if desired.

**Manual:** Download the latest `RogueEnergySweep-<version>-forever.zip` from [Releases](https://github.com/JoBonacc/RogueEnergySweep/releases). For v0.4.0 use the ZIP without the Forever suffix. Do not use GitHub's source-code archives. Extract the `RogueEnergySweep` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Replace the old addon folder when upgrading, then reload the UI or restart WoW if the addon is not detected. Saved variables are stored separately.

## Features

| Indicator | Behavior |
| --- | --- |
| Rising line | A horizontal stripe rises through the icon |
| Bottom bar | A compact bar fills left to right |
| Perimeter | Progress follows the icon's edge |
| Radial sweep | A shaded sector clears as energy regenerates |

Choose **energy-based** progress (fraction of the spell cost accumulated) or **countdown-based** progress (starts at zero after a detected spend). For example, a 45-energy ability with 15 energy left starts at 33% in energy mode or 0% in countdown mode. Both follow actual energy, not a fixed timer. Countdown is experimental and may fall back to energy mode. The options panel and `/resweep status` distinguish actual native/public countdown from energy fallback.

Type `/resweep` to change style, progress mode, color, opacity, thickness, tint and combat-only behavior. Choose from eight preset colors or use the native custom RGB picker; colors preview live, cancel restores the previous selection, and opacity remains independent. Hex colors are also supported with `/resweep color #RRGGBB` (for example, `/resweep color #FFCC33`). Settings are grouped by purpose; tint appears only for Rising Line and thickness only for linear and perimeter styles. Each style remembers its own appearance. Reverse direction, independent rising tint opacity, solid/gradient/luminous fill effects, per-style reset and an animated preview are included. Optional energy-ready effects include native completion burst, cooldown flash, animated proc glow, halo, border, pulse and soft flash. Protected one-shot triggers can fall back to a persistent pulse; no secret comparisons are performed. The panel includes a simulated preview, test on your bars and a selectable diagnostic report with optional update timing. An optional finisher filter hides overlays on combo-point spenders until the current target has at least one combo point. Enable it in options or with `/resweep finishers on`; `/resweep finishers off` restores the original behavior. Optional category filters, per-ability exclusions and cooldown filtering (ignores the GCD) reduce clutter. Existing spell cooldowns and the global cooldown are not modified.

## Support and compatibility

Blizzard action bars are the primary target. Bartender4, Dominos and ElvUI are best-effort; macro and talent-modified cost detection depends on the client API. Protected-value rendering has passed earlier smoke tests; new filters, reversed geometry and the combined candidate require live verification. Use `/resweep status` to inspect the renderer, fallback and interface compatibility. An interface warning is a prompt to test, not proof of breakage.

Build alerts detect newer builds even when the interface number is unchanged. See [live compatibility checklist and review record](docs/compatibility.md). No complete live test is recorded for this release.

See [full options and limitations](addon/RogueEnergySweep/README.md), [changelog](CHANGELOG.md), and [report a bug or suggest a feature](https://github.com/JoBonacc/RogueEnergySweep/issues/new/choose). Include client interface, action bar addon, style, progress mode, and steps to reproduce. Remove personal information from diagnostic output.

## Development

Run `lua tests/compatibility.lua` and `lua tests/api_contracts.lua` and `python scripts/package.py --version X.Y.Z --output dist` from the repository root. The compatibility test exercises the actual diagnostic functions, not live rendering. The historical v0.3.0 simulation harness was not retained; its report is archived with the addon.

Update the TOC, Lua version, addon README and changelog together. Change the supported interface only after checking the client. The packager generates a matching Forever-specific TOC and release ZIP plus SHA-256 checksum. Ordinary commits to main run validation only. To publish intentionally, use a commit with subject `Publish release: vX.Y.Z` matching the TOC version, or run the release workflow manually; pushing a single new version tag also works. GitHub Actions gates publication on passing tests. Historical tags preserve previous versions.

## License and attribution

Adapted from [Rogue Energy Need](https://www.curseforge.com/wow/addons/rogue-energy-need) 0.2.1 by Vryllak and Rogue Energy Need contributors, under the [MIT License](LICENSE). Original copyright and license notices are retained in the addon package. This is a separate, unofficial derivative.

## Optional standalone Energy Tracker
Five movable layouts: a shared energy dial, stacked bars, grouped icons, freeform icons and concentric per-ability rings. Independent color, scale, size, spacing and icon style; action bars, tracker, or both. Shares native protected energy curves and cooldown/finisher filters with the original overlay. Disabled by default; live verification pending.
