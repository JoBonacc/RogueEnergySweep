# Rogue Energy Sweep

Experimental World of Warcraft: Forever addon that displays energy readiness directly on rogue action buttons. Four styles and two progress modes. Target interface: 16001 (Forever 1.60.1); live compatibility is not guaranteed.

See [installation, options and known limitations](addon/RogueEnergySweep/README.md) and [changelog](CHANGELOG.md). Download the versioned ZIP from this repository's Releases page once published; extract `RogueEnergySweep` into `Interface/AddOns`, then `/reload` (restart if the client has not discovered the addon). Use `/resweep status` for diagnostics. An interface mismatch is a prompt to test, not proof of a break. No in-game internet update check is possible.

## Maintenance
- Update the TOC and Lua version, README and changelog together; change the supported interface only after checking the new client.
- Run `lua tests/compatibility.lua` and `python scripts/package.py --version X.Y.Z --output dist` from the repository root. The compatibility test runs the actual diagnostic functions extracted from the addon; it does not test rendering or the live client. The original v0.3.0 simulation report is archived in the addon folder; its test harness was not included in the uploaded release.
- Push changes to `main`, then push a new `vX.Y.Z` tag. GitHub Actions validates, packages, and publishes a release ZIP plus SHA-256 checksum. The action must have permission to create releases. Historical tags v0.1.0–v0.3.0 preserve the original packages as source; their old workflows do not publish releases.
- Report issues with `/resweep status` output and reproduction steps. Do not post personal information.

Adapted from Rogue Energy Need by Vryllak and contributors under MIT. See [license](addon/RogueEnergySweep/LICENSE). Not an official Rogue Energy Need release.
