# Network — Omarchy plugin

Live download and upload in the Omarchy bar.

Read the `omarchy-plugin-dev` skill first; it holds the conventions. This file
holds only what is specific to this repo.

## Identity

- id / IPC target / `moduleName`: `dansmith888.network`
- repo: `https://github.com/DanSmith888/omarchy-network.git`
- installed copy: `~/.config/omarchy/plugins/dansmith888.network`
- kind: `bar-widget`, entry point `BarWidget.qml`

## Origin

A fork of csawy3r/omarchy-network-speed (MIT), substantially rewritten. The
older fork still lives at `~/Work/omarchy-network-speed` and carries an open
PR upstream; changes meant for csawy3r go there, changes for this plugin go
here. Chris Sawyer's copyright stays in LICENSE — MIT requires it, do not
remove it.

## Map

- `manifest.json` — the contract; bump `version` on release.
- `BarWidget.qml` — entry point. Owns the pill and the single IpcHandler.
- `Panel.qml` — all state and the whole popup.
- `Model.js` — pure formatting/unit helpers; testable with plain node.
- `Sparkline.qml` — Canvas line graph used for the history graphs.

## Rules

- Keep in sync on release: `manifest.version`, git tag `vX.Y.Z`, `moduleName`
  and `ipcTarget` in every QML, README commands.
- Never edit `/usr/share/omarchy/**`.
- No `git push`, tag push, or marketplace submission unless Daniel says so.

## Gotchas

- The bar centres each line of a tooltip and Qt trims trailing whitespace, so
  tooltip lines are padded with U+00A0 to a common length.
- Bar columns reserve the width they have needed and never shrink, so the bar
  does not reflow; `speedWidth` pins them instead.
