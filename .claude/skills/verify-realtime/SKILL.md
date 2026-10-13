---
name: verify-realtime
description: Cross-device realtime check — alice on the iPhone 17 simulator and bob on the Pixel_10_Pro emulator exchanging list changes over SSE (scripts/dev/realtime.sh).
---

# Cross-platform realtime

```bash
scripts/dev/stack.sh reset                 # fresh seed
scripts/dev/ios.sh build && scripts/dev/ios.sh install 89850DF1-19BE-4DAF-92D5-B6411AF061A4
scripts/dev/android.sh build
scripts/dev/realtime.sh demo               # PASS/FAIL lines + .dev/shots/demo-{ios,android}/
```

Why this pairing: the emulator is already running for Android work, it exercises both SSE clients
(URLSession bytes vs Ktor SSE) and both host routes (localhost vs adb reverse), and keeps a single
booted iOS simulator (AXe returns an empty tree for the non-current device when two are booted;
`sim.sh shutdown` + `boot` recovers it).

Expectations: a change by one user shows on the other device within 5 s without a refresh; the
server log (`.dev/logs/api.log`) shows one `/events` stream per device; `android.sh log` and
`ios.sh log <udid>` both show `events ready`.
