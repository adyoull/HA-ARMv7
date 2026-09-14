# Changelog

Unofficial ARMv7 (32-bit) builds of Home Assistant. All images published to
`ghcr.io/adyoull/ha-armv7`.

## 2026.9.2-r1 — 2026-09-14

- Rebuilt against Home Assistant **2026.9.2** (patch release).
- Refreshed dependency pins from the official 2026.9.2 arm64 image.
- No build-recipe changes; base+app split, PyAV patch, Apple TV, `bleak-smlight`,
  MFA, and the HTTPS healthcheck all carried over.

Tags: `2026.9.2-r1`, `2026.9.2`, `latest`

## 2026.9.1-r1 — 2026-09-07

- Rebuilt against Home Assistant **2026.9.1** (patch release).
- Refreshed dependency pins from the official 2026.9.1 arm64 image.
- No build-recipe changes; base+app split, PyAV patch (`av` still 17.0.1), Apple
  TV, `bleak-smlight`, MFA, and the HTTPS healthcheck all carried over.

Tags: `2026.9.1-r1`, `2026.9.1`, `latest`

## 2026.9.0-r1 — 2026-09-02

- Rebuilt against Home Assistant **2026.9.0** (monthly minor release).
- Refreshed dependency pins from the official 2026.9.0 arm64 image.
- No build-recipe changes; base+app split, PyAV patch, Apple TV, `bleak-smlight`,
  MFA, and the HTTPS healthcheck all carried over.

Tags: `2026.9.0-r1`, `2026.9.0`, `latest`

## 2026.8.3-r2 — 2026-08-18

- **Fix: `bluetooth_adapters` setup failure.** HA's `bluetooth_adapters` pulls the
  `smlight` scanner backend, needing `bleak-smlight==1.1.0`, which ships only
  compiled wheels (no armv7) — so setup failed and Bluetooth was degraded. It has
  an sdist with a Cython extension, so we now build it from source (base image
  Cython + toolchain). Loads even with no SMLIGHT device attached.
- **Fix: healthcheck.** The container healthcheck curled `http://` on 8123, which
  fails when `http:` has an `ssl_certificate` (HA then serves HTTPS). Now tries
  HTTPS (`-k`) then HTTP, so it works with or without SSL. Also overridable via
  `docker-compose.yml` without rebuilding.
- Build: `patch_av.sh` clears the stale `av` entry the requirements batch leaves
  in the failed-requirements file; `build.sh` verify now imports `av` and reports
  `bleak-smlight`.

Tags: `2026.8.3-r2`, `2026.8.3`, `latest`

## 2026.8.3-r1 — 2026-08-18

- Rebuilt against Home Assistant **2026.8.3**.
- **Fix: PyAV (`av==17.0.1`) no longer builds from source.** A new Cython (3.1.7+)
  rejects a redeclaration in `av/container/pyio.py` (`'seek_func' redeclared`).
  `patch_av.sh` fetches the sdist by curl (not `pip download`, which builds the
  un-patched source), applies av 18.1's one-line fix, and builds with
  `--no-build-isolation`. Affects anyone building PyAV 17.0.1 from source.
- **Build split into base + app images.** FFmpeg 8 and Cython (~30 min under
  emulation, version-independent) now live in `ghcr.io/adyoull/ha-armv7-base`,
  built once. HA version bumps rebuild only the app image. `REBUILD_BASE=1` forces
  a base rebuild.
- `build.sh` now orchestrates base + app + verify + push; parallelism defaults to
  `BUILD_JOBS=8`.

Tags: `2026.8.3-r1`, `2026.8.3`, `latest`

## 2026.8.2-r1 — 2026-08-13

- Rebuilt against Home Assistant **2026.8.2** (upstream patch release).
- Refreshed dependency pins from the official 2026.8.2 arm64 image.
- Docs: troubleshooting notes for binary-only packages with no armv7 sdist
  (e.g. `bleak-smlight` — benign unless you own the device) and corrupted
  `.dist-info/METADATA` installs (e.g. `midea-lan`).

Tags: `2026.8.2-r1`, `2026.8.2`, `latest`

## 2026.8.1-r1 — 2026-08-08

- Rebuilt against Home Assistant **2026.8.1** (upstream patch release).
- Refreshed dependency pins from the official 2026.8.1 arm64 image.
- No build-recipe changes; FFmpeg caching, Apple TV (`pyatv`/`miniaudio`), MFA
  (`pyotp`, `PyQRCode`), and the libstdc++ relink all carried over.

Tags: `2026.8.1-r1`, `2026.8.1`, `latest`

## 2026.8.0-r1 — 2026-08-05

- Rebuilt against Home Assistant **2026.8.0** (monthly minor release).
- Refreshed dependency pins from the official 2026.8.0 arm64 image.
- **Build:** FFmpeg 8 now compiles *before* the HA install, so it lands in a
  cached layer and survives `HA_VERSION` bumps instead of recompiling each time.
- Apple TV (`pyatv`/`miniaudio`), MFA (`pyotp`, `PyQRCode`), and the libstdc++
  relink all carried over.

Tags: `2026.8.0-r1`, `2026.8.0`, `latest`

## 2026.7.4-r1 — 2026-07-24

- Rebuilt against Home Assistant **2026.7.4** (upstream patch release).
- Refreshed dependency pins from the official 2026.7.4 arm64 image.
- No build-recipe changes; Apple TV (`pyatv`/`miniaudio`), MFA (`pyotp`,
  `PyQRCode`), FFmpeg 8, and the libstdc++ relink all carried over from r1.

Tags: `2026.7.4-r1`, `2026.7.4`, `latest`

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
