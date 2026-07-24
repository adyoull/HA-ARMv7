# Changelog

Unofficial ARMv7 (32-bit) builds of Home Assistant. All images published to
`ghcr.io/adyoull/ha-armv7`.

## 2026.7.3-r1 — 2026-07-24

- Rebuilt against Home Assistant **2026.7.3** (upstream patch release).
- Refreshed dependency pins from the official 2026.7.3 arm64 image.
- **Fix:** pre-build `pyatv` + `miniaudio` so the `apple_tv` integration works.
  `miniaudio` pins an ancient `cffi==1.15.0` that won't compile on Python 3.14
  (`implicit declaration of function ...`), so runtime install looped forever and
  apple_tv never set up. Now install a modern `cffi` first and build both with
  `--no-build-isolation`.
- **Build:** parallelism is now configurable via `--build-arg BUILD_JOBS=N`
  (default 1). On a 32 GB cross-build host `BUILD_JOBS=8` cuts hours off. Applies
  to `make`, `cargo`, numpy, and uv.
- MFA modules (`pyotp`, `PyQRCode`) still pre-baked, carried from 2026.7.2-r2.

Tags: `2026.7.3-r1`, `2026.7.3`, `latest`

## 2026.7.2-r2 — 2026-07-21

- **Fix:** pre-installed the TOTP two-factor-auth modules `pyotp` and `PyQRCode`.
  These are declared in HA's source (`auth/mfa_modules/totp.py`), not in any
  integration manifest, so the resolver missed them. With MFA enabled, r1 tried to
  install them at first boot, which fails under udocker/Termux (proot blocks the
  runtime installer) and dropped HA into recovery mode.

Tags: `2026.7.2-r2`

## 2026.7.2-r1 — 2026-07-13

- Initial working build: Home Assistant **2026.7.2** on armv7, cross-compiled from
  an x86/arm64 host.
- Notable fixes required to get here:
  - Base `python:3.14-slim-trixie` (HA 2026.x needs Python ≥3.14.2).
  - `libpcap0.8t64` for Debian trixie's 64-bit `time_t` rename.
  - **FFmpeg 8 built from source** — trixie ships 7.1, but current PyAV needs
    FFmpeg 8 APIs.
  - Relinked `pymicro_vad` / voice C++ extensions with `-lstdc++` (they ship
    sources linked with `gcc`, producing a `.so` missing the C++ runtime on armv7).
  - `resolve_reqs.py` to install per-integration manifest requirements at build
    time, plus an `ALWAYS` list for integrations HA cross-imports without
    declaring (`hassio`→`aiohasupervisor`, `usb`→`aioesphomeapi`, `gtts`, etc.).
  - Official arm64 `pip freeze` used as a version-pin constraints file.
  - Bundled the `go2rtc` armv7 binary.

Tags: `2026.7.2-r1`, `2026.7.2`

---

_Copyright (C) 2026 Andrew Youll._
