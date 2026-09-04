// Bounded procfs parsers. Nothing here runs a shell: the panel reads
// /proc/net/dev and /proc/net/route in process, so there is no PATH lookup,
// no inherited environment and no child to outlive us.

var MAX_DEV_LINES = 256      // interfaces considered per poll
var MAX_ROUTE_LINES = 512    // route table rows considered per poll
var MAX_THEME_LINES = 512    // colours.toml lines considered per load
var IFACE_NAME_MAX = 24      // kernel caps at IFNAMSIZ 16, this is slack

// Interface names come from the kernel, but they are still strings we did
// not author, so they get the same treatment as process names.
function safeIface(name) {
  return String(name || "")
    .replace(/[\x00-\x1f\x7f]/g, "")
    .replace(/[^A-Za-z0-9._:@-]/g, "")
    .slice(0, IFACE_NAME_MAX)
}

// /proc/net/dev: two header lines, then "  iface: rx_bytes ... tx_bytes ...".
// Field 0 after the colon is received bytes, field 8 is transmitted.
function parseNetDev(raw) {
  var lines = String(raw || "").split("\n")
  var limit = Math.min(lines.length, MAX_DEV_LINES)
  var ifaces = {}
  var list = []

  for (var i = 0; i < limit; i++) {
    var line = lines[i]
    var colon = line.indexOf(":")
    if (colon < 0) continue
    var name = safeIface(line.slice(0, colon).trim())
    if (!name || name === "lo") continue
    var fields = line.slice(colon + 1).trim().split(/\s+/)
    if (fields.length < 9) continue
    var rx = parseFloat(fields[0])
    var tx = parseFloat(fields[8])
    if (!isFinite(rx) || !isFinite(tx)) continue
    ifaces[name] = { rx: rx, tx: tx }
    list.push(name)
  }

  list.sort()
  return { ifaces: ifaces, list: list }
}

// /proc/net/route: the default route is the row whose destination is all
// zeroes. Lowest metric wins, matching what the kernel would pick.
function parseDefaultRoute(raw) {
  var lines = String(raw || "").split("\n")
  var limit = Math.min(lines.length, MAX_ROUTE_LINES)
  var best = ""
  var bestMetric = Infinity

  for (var i = 1; i < limit; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 7) continue
    if (parts[1] !== "00000000") continue
    var metric = parseInt(parts[6], 10)
    if (!isFinite(metric)) metric = 0
    if (metric >= bestMetric) continue
    var name = safeIface(parts[0])
    if (!name) continue
    best = name
    bestMetric = metric
  }

  return best
}

// Both files arrive from one bounded read, separated by head's "==> path <=="
// banners. Splitting here keeps the two parsers above independently testable.
function splitSections(raw) {
  var out = {}
  var current = ""
  var lines = String(raw || "").split("\n")
  var limit = Math.min(lines.length, MAX_DEV_LINES + MAX_ROUTE_LINES + 8)
  for (var i = 0; i < limit; i++) {
    var line = lines[i]
    var banner = line.match(/^==>\s+(\S+)\s+<==$/)
    if (banner) { current = banner[1]; out[current] = []; continue }
    if (current) out[current].push(line)
  }
  for (var key in out) out[key] = out[key].join("\n")
  return out
}

// The two reads together, in the shape resolveActive already expects.
function buildSample(raw) {
  var sections = splitSections(raw)
  var dev = parseNetDev(sections["/proc/net/dev"] || "")
  return {
    auto: parseDefaultRoute(sections["/proc/net/route"] || ""),
    ifaces: dev.ifaces,
    list: dev.list
  }
}

// Parses the small, stable subset of theme/colors.toml keys every Omarchy
// theme defines (accent, muted, foreground, red, yellow, orange, green,
// cyan, blue, magenta) into a flat dict. Same regex shape as the shell's
// own Color.qml loader, so it stays correct if a theme quotes values or
// adds trailing comments.
function parseThemeColors(raw) {
  var keys = ["accent", "muted", "foreground", "red", "yellow", "orange", "green", "cyan", "blue", "magenta"]
  var out = {}
  var lines = String(raw || "").split("\n")
  var limit = Math.min(lines.length, MAX_THEME_LINES)
  for (var i = 0; i < limit; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (!match) continue
    if (keys.indexOf(match[1]) !== -1) out[match[1]] = match[2]
  }
  return out
}

// Builds the speed-tier swatch palette from the live theme, falling back to
// the old fixed One Dark values for any key an unusual theme omits.
function themePalette(theme) {
  var t = theme || {}
  return [
    "",
    t.red || "#e06c75",
    t.yellow || "#e5c07b",
    t.green || "#98c379",
    t.cyan || "#56b6c2",
    t.blue || t.accent || "#61afef",
    t.magenta || "#c678dd",
    t.muted || "#abb2bf",
    t.foreground || "#ffffff"
  ]
}

// raw -> { auto: "eth0", ifaces: { eth0: {rx,tx}, ... }, list: [names...] }
// Resolves the configured selection ("auto" | "all" | <iface name>) against
// a parsed sample to a single { rx, tx, label } reading.
function resolveActive(sample, selected) {
  var s = sample || { auto: "", ifaces: {}, list: [] }

  if (selected === "all") {
    var rx = 0, tx = 0
    for (var k in s.ifaces) { rx += s.ifaces[k].rx; tx += s.ifaces[k].tx }
    return { rx: rx, tx: tx, label: "All interfaces" }
  }

  if (!selected || selected === "auto") {
    var name = s.auto
    var entry = name && s.ifaces[name] ? s.ifaces[name] : { rx: 0, tx: 0 }
    return { rx: entry.rx, tx: entry.tx, label: name || "No connection" }
  }

  var found = s.ifaces[selected]
  if (found) return { rx: found.rx, tx: found.tx, label: selected }
  return { rx: 0, tx: 0, label: selected + " (not found)" }
}

// Same delta-over-time algorithm as the built-in network panel's
// throughputState, keyed by an opaque string instead of a bare iface name so
// switching between auto/all/<iface> also resets the rate to 0.
function throughputState(previous, next, now) {
  var prev = previous || {}
  var key = next.key || ""
  var rx = Number(next.rx || 0)
  var tx = Number(next.tx || 0)
  var previousTime = Number(prev.prevTime || 0)

  if (key !== (prev.prevKey || "") || previousTime === 0) {
    return { prevKey: key, prevRx: rx, prevTx: tx, prevTime: now, downloadRate: 0, uploadRate: 0 }
  }

  var dt = now - previousTime
  var downloadRate = Number(prev.downloadRate || 0)
  var uploadRate = Number(prev.uploadRate || 0)
  if (dt > 0) {
    downloadRate = Math.max(0, (rx - Number(prev.prevRx || 0)) / dt)
    uploadRate = Math.max(0, (tx - Number(prev.prevTx || 0)) / dt)
  }

  return { prevKey: key, prevRx: rx, prevTx: tx, prevTime: now, downloadRate: downloadRate, uploadRate: uploadRate }
}

// Every poll is bounded. `ss` output on a busy host runs to thousands of
// sockets, and this parse happens inside the shell process as often as twice a
// second, so the line count, the number of processes tracked and the length of
// any single name all have hard caps.
var MAX_LINES = 4000
var MAX_PROCS = 200
var NAME_MAX = 32

// A process name is whatever a local program chose to call itself, and it ends
// up in the panel and in the bar's tooltip. The bar renders tooltips with a
// Text that auto-detects rich text, so markup in a name would be interpreted
// rather than shown. Keep a conservative printable subset and cap the length:
// that is the boundary, enforced here rather than trusted downstream.
function safeName(value) {
  var out = String(value === undefined || value === null ? "" : value)
    .replace(/[^A-Za-z0-9 ._+@:-]/g, "")
    .slice(0, NAME_MAX)
    .trim()
  return out === "" ? "?" : out
}

// Parses `ss -H -tanpi` output into per-process rx/tx byte totals, then
// diffs against the previous sample to get a rate. Unprivileged: `ss -p`
// only resolves process info for sockets the current user owns, so this
// only ever shows the current user's own apps.
function parseNetworkProcesses(raw, previous, now) {
  var lines = String(raw || "").split("\n")
  var pending = null
  var txTotals = {}
  var rxTotals = {}
  var names = {}

  var nameCount = 0
  var limit = Math.min(lines.length, MAX_LINES)
  for (var i = 0; i < limit; i++) {
    var line = lines[i]
    var userMatch = line.match(/users:\(\("([^"]+)",pid=(\d+)/)
    if (userMatch) {
      pending = { pid: userMatch[2], name: safeName(userMatch[1]) }
      if (names[pending.pid] === undefined) {
        if (nameCount >= MAX_PROCS) { pending = null; continue }
        nameCount++
      }
      names[pending.pid] = pending.name
    }
    if (line.indexOf("bytes_") < 0) continue
    var ackedMatch = line.match(/bytes_acked:(\d+)/)
    var sentMatch = line.match(/bytes_sent:(\d+)/)
    var receivedMatch = line.match(/bytes_received:(\d+)/)
    if (!ackedMatch && !sentMatch && !receivedMatch) continue
    var pid = pending ? pending.pid : null
    if (!pid) continue
    var txBytes = ackedMatch ? Number(ackedMatch[1]) : (sentMatch ? Number(sentMatch[1]) : 0)
    var rxBytes = receivedMatch ? Number(receivedMatch[1]) : 0
    txTotals[pid] = (txTotals[pid] || 0) + txBytes
    rxTotals[pid] = (rxTotals[pid] || 0) + rxBytes
    pending = null
  }

  var prev = previous || {}
  var list = []
  var nextPrev = {}

  for (var pidKey in names) {
    var tx = txTotals[pidKey] || 0
    var rx = rxTotals[pidKey] || 0
    var prevEntry = prev[pidKey]
    var rxRate = 0
    var txRate = 0
    if (prevEntry) {
      var seconds = Math.max(0.5, (now - prevEntry.at) / 1000)
      rxRate = Math.max(0, (rx - prevEntry.rx) / seconds)
      txRate = Math.max(0, (tx - prevEntry.tx) / seconds)
    }
    nextPrev[pidKey] = { rx: rx, tx: tx, at: now }
    if (!prevEntry && rx + tx <= 0) continue
    list.push({ pid: pidKey, name: names[pidKey], rxRate: rxRate, txRate: txRate })
  }

  list.sort(function(a, b) { return (b.rxRate + b.txRate) - (a.rxRate + a.txRate) })

  return { list: list, previous: nextPrev }
}

// Unit systems. `mult` converts bytes to the system's base unit, `base` is
// the step between magnitudes, `labels` are the magnitude names.
var UNIT_SYSTEMS = {
  bytes:  { base: 1000, mult: 1, labels: ["B", "kB", "MB", "GB"], short: ["B", "k", "M", "G"] },
  bits:   { base: 1000, mult: 8, labels: ["b", "kb", "Mb", "Gb"], short: ["b", "k", "M", "G"] },
  binary: { base: 1024, mult: 1, labels: ["B", "KiB", "MiB", "GiB"], short: ["B", "k", "M", "G"] }
}
var SCALES = ["base", "kilo", "mega", "giga"]
var SCALE_DECIMALS = [0, 1, 1, 2]
// Older builds stored the display unit as "B" | "KB" | "MB" | "GB".
var LEGACY_SCALES = { B: "base", KB: "kilo", MB: "mega", GB: "giga" }

function isUnitSystem(name) {
  return Object.prototype.hasOwnProperty.call(UNIT_SYSTEMS, String(name || ""))
}

function normalizeSystem(name) {
  return isUnitSystem(name) ? String(name) : "bytes"
}

function normalizeScale(scale) {
  var s = String(scale || "auto")
  if (LEGACY_SCALES[s]) return LEGACY_SCALES[s]
  return SCALES.indexOf(s) !== -1 ? s : "auto"
}

function isFixedScale(scale) {
  return SCALES.indexOf(normalizeScale(scale)) !== -1
}

function systemSpec(system) {
  return UNIT_SYSTEMS[normalizeSystem(system)]
}

// Bytes/sec -> value in the system's base unit (bits or bytes).
function toSystemUnits(bytes, system) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  return n * systemSpec(system).mult
}

// Magnitude index (0 = base, 1 = kilo, 2 = mega, 3 = giga) that auto-scaling
// would pick for a reading. Tier colours use the same boundaries.
function magnitudeIndex(bytes, system) {
  var spec = systemSpec(system)
  var v = toSystemUnits(bytes, system)
  var i = 0
  while (i < SCALES.length - 1 && v >= Math.pow(spec.base, i + 1)) i++
  return i
}

function unitLabel(system, scale) {
  var idx = SCALES.indexOf(normalizeScale(scale))
  return systemSpec(system).labels[idx < 0 ? 0 : idx]
}

function formatIn(bytes, system, scale) {
  var spec = systemSpec(system)
  var idx = isFixedScale(scale) ? SCALES.indexOf(normalizeScale(scale)) : magnitudeIndex(bytes, system)
  var v = toSystemUnits(bytes, system) / Math.pow(spec.base, idx)
  return v.toFixed(SCALE_DECIMALS[idx]) + " " + spec.labels[idx]
}

function formatRate(bytesPerSec, system, scale) {
  return formatIn(bytesPerSec, system, scale) + "/s"
}

// Compact form for the bar, in the style of systempulse: short unit letter
// with no space or "/s", auto never drops below kilo, kilo is a whole
// number, mega gets one decimal, giga two ("10k", "1.2M", "1.50G").
var BAR_DECIMALS = [0, 0, 1, 2]

function shortUnitLabel(system, scale) {
  var idx = SCALES.indexOf(normalizeScale(scale))
  return systemSpec(system).short[idx < 0 ? 1 : idx]
}

function formatBar(bytes, system, scale) {
  var spec = systemSpec(system)
  var idx = isFixedScale(scale) ? SCALES.indexOf(normalizeScale(scale)) : Math.max(1, magnitudeIndex(bytes, system))
  var v = toSystemUnits(bytes, system) / Math.pow(spec.base, idx)
  return v.toFixed(BAR_DECIMALS[idx]) + spec.short[idx]
}

// Widest form a bar reading realistically takes, used only to reserve a
// stable column so the pill stops shuffling its neighbours every time a
// number crosses 9 -> 10 -> 100. A reading past this still grows.
function widestReading(system, scale) {
  var spec = systemSpec(system)
  var sc = normalizeScale(scale)
  if (sc === "base") return "9999" + spec.short[0]
  if (sc === "kilo") return "9999" + spec.short[1]
  if (sc === "mega") return "999.9" + spec.short[2]
  if (sc === "giga") return "9.99" + spec.short[3]
  return "999" + spec.short[3]
}

// Number + magnitude in the active system ("10 MB/s") -> bytes/sec. 0 disables.
function thresholdBytes(value, scale, system) {
  var v = Number(value)
  if (!isFinite(v) || v <= 0) return 0
  var spec = systemSpec(system)
  var idx = SCALES.indexOf(normalizeScale(scale))
  if (idx < 0) idx = 0
  return v * Math.pow(spec.base, idx) / spec.mult
}

// ---- shared helpers (same shape as the CPU and GPU plugins) --------------

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

function isNum(v) { return typeof v === "number" && isFinite(v) }

function clampInt(v, lo, hi, fallback) {
  var n = Math.round(num(v, fallback))
  if (!isFinite(n)) n = fallback
  return Math.max(lo, Math.min(hi, n))
}

function asBool(v, fallback) {
  if (v === true || v === "true" || v === 1) return true
  if (v === false || v === "false" || v === 0) return false
  return fallback
}

// Append one sample and keep the last `size`. Returns a new array so QML
// property bindings actually fire.
function pushHistory(history, value, size) {
  var out = (history || []).slice()
  out.push(isNum(value) ? value : 0)
  var cap = Math.max(2, Math.round(num(size, 60)))
  while (out.length > cap) out.shift()
  return out
}

// ---- tooltips -----------------------------------------------------------

function padRight(s, w) {
  var out = String(s)
  while (out.length < w) out += " "
  return out
}

// Title line, then one aligned "label  value" line per row. Rows whose value
// is null/empty are dropped, so a machine that doesn't report something
// simply has no line for it rather than a dash.
function tooltip(title, rows) {
  var list = (rows || []).filter(function(r) {
    return r && r[1] !== null && r[1] !== undefined && r[1] !== "" && r[1] !== "-"
  })
  var w = 0
  for (var i = 0; i < list.length; i++) w = Math.max(w, String(list[i][0]).length)
  var out = [title]
  for (var j = 0; j < list.length; j++)
    out.push(padRight(list[j][0], w) + "   " + String(list[j][1]))

  // Bar.qml centres each line of a tooltip (Text.AlignHCenter), so the only
  // way to get a left-aligned block is to make every line the same rendered
  // width. Ordinary trailing spaces cannot do it: Qt trims trailing
  // whitespace when laying a line out, so the padding is discarded and the
  // line re-centres. A non-breaking space is not trimmed, and is the same
  // width as a space in the bar's monospace font.
  var line = 0
  for (var k = 0; k < out.length; k++) line = Math.max(line, out[k].length)
  for (var n = 0; n < out.length; n++) {
    while (out[n].length < line) out[n] += "\u00a0"
  }
  return out.join("\n")
}
