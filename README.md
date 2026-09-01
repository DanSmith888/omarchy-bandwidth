# Network

Live download and upload in the [Omarchy](https://omarchy.org/) bar, with the
detail one click away.

The pill shows both directions and recolours itself as traffic climbs. The
panel adds a history graph per direction, which apps are using the connection,
every unit system you might want, and alert limits.

![The trio in the bar](docs/bar.png)

![The panel](docs/panel.png)

## Install

```bash
omarchy plugin add https://github.com/DanSmith888/omarchy-network.git --enable
```

## Update

```bash
omarchy plugin update dansmith888.network && omarchy restart shell
```

## Remove

```bash
omarchy plugin remove dansmith888.network
```

## Using it

**Left-click** the pill to open the panel. **Middle-click** opens `btop`,
reusing an existing window rather than stacking up terminals. **Hover** for the
interface and full-precision rates. Esc closes. To open the panel from a
hotkey:

```bash
omarchy-shell shell toggle dansmith888.network
```

## What it shows

| Section | What's in it |
|---|---|
| **Hero** | Interface name and the live download and upload rates |
| **Graphs** | Download and upload history, 30–240 samples, each scaled to its own peak |
| **Top apps** | Per-process bandwidth, busiest first |
| **Interface** | Auto (default route), all interfaces combined, or a specific NIC |
| **Display** | Unit system (decimal bytes, bits, binary bytes), fixed or auto scale, the pill icon, refresh rate, graph history |
| **Download / Upload** | The arrow glyph each direction uses |
| **Idle threshold** | Hide rates below a number + magnitude |
| **Layout** | Pin each reading to a fixed width, or leave it to size itself |
| **Speed colors** | A colour per magnitude band, taken from your live Omarchy theme |
| **Alert** | Per-direction limits that recolour a reading when exceeded |

Settings are stored inline on the widget's `~/.config/omarchy/shell.json`
entry and apply immediately.

## Requirements

- Omarchy (Quattro or later)
- `iproute2` for `ss` (per-app bandwidth); present on a stock Arch install
- `btop`, only for the middle-click shortcut

## Good to know

- Rates are a delta between polls, read from `/proc/net/dev`.
- Each reading reserves the width it has needed, so the bar does not reflow as
  the numbers change. Pin a width under Layout if you prefer a fixed column.
- Unit systems cover decimal bytes (kB/MB/GB), bits (kb/Mb/Gb) and binary
  bytes (KiB/MiB/GiB); the choice drives the readings, the speed colours and
  the thresholds together.

## What runs, and as whom

Omarchy plugins run inside the shell process, unsandboxed, as your user. This
one reads `/proc/net/dev` and runs `ss` to attribute traffic to processes. No
daemon, no root, no network of its own, and nothing written outside its own
folder.

## Related

One of a trio that share a panel layout and controls:

- [omarchy-cpu](https://github.com/DanSmith888/omarchy-cpu) — load, cores,
  temperature, memory, top processes
- [omarchy-gpu](https://github.com/DanSmith888/omarchy-gpu) — load, VRAM,
  power, sensors, GPU clients

## Credits

Began as a fork of
[omarchy-network-speed](https://github.com/csawy3r/omarchy-network-speed) by
Chris Sawyer, MIT licensed, and has been substantially rewritten since. His
copyright notice is retained in [LICENSE](LICENSE) alongside mine, as MIT
requires.

## Licence

MIT — see [LICENSE](LICENSE).
