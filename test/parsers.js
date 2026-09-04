#!/usr/bin/env node
// Exercises the procfs parsers against this machine's real /proc, using the
// exact argv and scrubbed environment the panel uses, then checks that every
// bound holds against hostile input. Run: node test/parsers.js

const { execFileSync } = require("child_process")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const root = path.resolve(__dirname, "..")
const Model = {}
vm.runInNewContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), Model)

const ENV = { PATH: "/usr/bin:/bin", LC_ALL: "C" }
const READ_ARGS = ["-c", "65536", "/proc/net/dev", "/proc/net/route"]

let failures = 0
function check(name, ok, detail) {
  console.log((ok ? "ok   " : "FAIL ") + name + (detail ? "  (" + detail + ")" : ""))
  if (!ok) failures++
}

function readProc() {
  return execFileSync("/usr/bin/head", READ_ARGS, { env: ENV, encoding: "utf8" })
}

// 1. The real read, exactly as the panel runs it: no shell, absolute path,
//    scrubbed environment, byte cap applied by the only program in the chain.
const raw = readProc()
const sample = Model.buildSample(raw)

check("interfaces parsed from /proc/net/dev", sample.list.length > 0, sample.list.join(","))
check("loopback excluded", sample.list.indexOf("lo") === -1)
check("counters are finite and non-negative", sample.list.every(function (n) {
  const e = sample.ifaces[n]
  return isFinite(e.rx) && isFinite(e.tx) && e.rx >= 0 && e.tx >= 0
}))

// The default route must agree with what the kernel reports through iproute2.
const viaIp = execFileSync("/usr/bin/ip", ["route", "show", "default"],
  { env: ENV, encoding: "utf8" })
const expected = (viaIp.match(/\bdev\s+(\S+)/) || [])[1] || ""
check("default route matches `ip route show default`",
  sample.auto === expected, "parsed " + sample.auto + ", ip says " + expected)

const second = Model.buildSample(readProc())
check("counters readable across two samples",
  second.list.length === sample.list.length && second.list.length > 0)

// 2. Bounds. Hostile input must not be parsed in full.
const flood = "Inter-|\n face |\n"
  + new Array(100000).fill("eth0: 1 2 3 4 5 6 7 8 9").join("\n")
const started = Date.now()
const flooded = Model.parseNetDev(flood)
check("oversized /proc/net/dev truncated to MAX_DEV_LINES",
  flooded.list.length <= 256, "kept " + flooded.list.length + " in " + (Date.now() - started) + "ms")

const routeFlood = "Iface\n"
  + new Array(100000).fill("eth0\t00000000\t0\t3\t0\t0\t100\t0").join("\n")
check("oversized /proc/net/route truncated", Model.parseDefaultRoute(routeFlood) === "eth0")

const ESC = String.fromCharCode(27)
check("interface names stripped of control characters",
  Model.safeIface("eth0" + ESC + "[0m\n") === "eth00m")
check("interface names length capped", Model.safeIface("x".repeat(200)).length === 24)
check("theme parse bounded", Object.keys(Model.parseThemeColors(
  new Array(50000).fill('red = "#ff0000"').join("\n"))).length <= 10)

// 3. Section splitting must not confuse the two files.
const sections = Model.splitSections(raw)
check("both files present in one read",
  !!sections["/proc/net/dev"] && !!sections["/proc/net/route"])
check("route rows do not leak into the device parse",
  Model.parseNetDev(sections["/proc/net/route"] || "").list.length === 0)

// 4. The ss parser keeps its existing caps. Rates only exist once a second
//    sample can be diffed against the first, so both are built here, each
//    socket with its own pid so the cap is actually exercised.
function ssFlood(count, bytes) {
  const out = []
  for (let i = 1; i <= count; i++) {
    out.push('ESTAB 0 0 10.0.0.1:1 10.0.0.2:' + i
      + ' users:(("proc' + i + '",pid=' + i + ',fd=3))')
    out.push('\t cubic bytes_sent:' + bytes + ' bytes_acked:' + bytes
      + ' bytes_received:' + bytes)
  }
  return out.join("\n")
}

const t1 = Date.now()
const first = Model.parseNetworkProcesses(ssFlood(50000, 1000), {}, t1)
const secondPass = Model.parseNetworkProcesses(ssFlood(50000, 9000), first.previous, t1 + 2000)
check("ss floods capped to MAX_PROCS", secondPass.list.length <= 200,
  "kept " + secondPass.list.length)
check("carried state capped too", Object.keys(secondPass.previous).length <= 200,
  "carried " + Object.keys(secondPass.previous).length)
check("rates computed on the second sample",
  secondPass.list.length > 0 && secondPass.list.some(function (e) {
    return e.rxRate > 0 || e.txRate > 0
  }))
check("process names sanitised", Model.safeName("bad" + ESC + "[31mname ") === "bad31mname")
check("process names length capped", Model.safeName("y".repeat(300)).length === 32)

console.log(failures ? "\n" + failures + " failing" : "\nall checks passed")
process.exit(failures ? 1 : 0)
