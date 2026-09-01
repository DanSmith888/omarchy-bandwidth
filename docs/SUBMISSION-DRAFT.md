<!--
Marketplace submission for https://plugins.omarchy.org — UNSUBMITTED DRAFT.
Before submitting: push the repo and tag v1.0.0, strip this comment, then:

  gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace \
    --title "[Plugin]: Network" --body-file docs/SUBMISSION-DRAFT.md
-->

### Repository URL

https://github.com/DanSmith888/omarchy-network

### Category

Hardware

### Tags

bar, system, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Live download and upload in the bar; in the panel a history graph per
direction, per-app bandwidth, the interface picker, unit systems (decimal
bytes, bits, binary bytes) with a fixed or automatic scale, an idle threshold,
speed-band colours taken from the active Omarchy theme, and per-direction alert
limits. Middle-click opens btop.

Reads `/proc/net/dev` for throughput and runs `ss` to attribute traffic to
processes. No daemon, no root, no network of its own, no compiled binaries, and
nothing written outside the plugin folder — removal is clean.

Began as a fork of csawy3r/omarchy-network-speed (MIT) and has been
substantially rewritten: the unit systems, history graphs, hover tooltip,
per-direction alerts, magnitude-based idle threshold, self-sizing bar columns
and the panel layout are new. The original copyright notice is retained in
LICENSE alongside mine, as MIT requires, and the README credits the origin.

One of a trio with omarchy-cpu and omarchy-gpu, which share the same panel
layout and controls.

### Submission checklist

- [x] The repository is public and includes install and removal instructions
- [x] The license and any external dependencies are documented
- [x] I own or have permission to publish the plugin and preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing only and is not a security review
