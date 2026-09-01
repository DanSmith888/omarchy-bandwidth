<!--
Marketplace submission, unsubmitted. To send: push, then
  gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace \
    --title "[Plugin]: Bandwidth" --body-file docs/SUBMISSION-DRAFT.md
(strip this comment first)
-->

### Repository URL

https://github.com/DanSmith888/omarchy-bandwidth

### Category

Hardware

### Tags

bar, system, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Live download and upload in the bar. The panel adds a history graph per
direction, per app bandwidth, the interface picker, three unit systems with a
fixed or automatic scale, an idle threshold, speed band colours taken from the
active theme, and per direction alert limits. Middle click opens btop.

It reads /proc/net/dev for throughput and runs ss to attribute traffic to
processes. No daemon, no root, no network of its own, no binaries, and nothing
written outside its own folder.

Named Bandwidth rather than Network so it does not collide with the
first-party omarchy.network widget in the picker.

This began as a fork of csawy3r/omarchy-network-speed (MIT) and has been
substantially rewritten. The unit systems, history graphs, hover tooltip, alert
limits, idle threshold, self sizing bar columns and panel layout are new. Chris
Sawyer's copyright notice stays in LICENSE alongside mine, as MIT requires, and
the README credits the origin.

One of a trio with omarchy-cpu and omarchy-gpu, which share a panel layout and
controls.

### Submission checklist

- [x] The repository is public and includes install and removal instructions
- [x] The license and any external dependencies are documented
- [x] I own or have permission to publish the plugin and preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing only and is not a security review
