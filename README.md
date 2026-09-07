# Home Assistant on ARMv7 (32-bit) — unofficial build

Home Assistant [deprecated 32-bit](https://www.home-assistant.io/blog/2025/05/22/deprecating-core-and-supervised-installation-methods-and-32-bit-systems/)
(i386 / armhf / armv7) in May 2025. **The last official armv7 image is
`2025.11.3`** — despite the blog saying support ran "until 2025.12", the armv7
image builds stopped a release earlier.

This kit cross-compiles a *current* Home Assistant for armv7 on a Mac (or any
x86/arm64 Docker host) and produces an image you can run on a Raspberry Pi 2/3
on a 32-bit OS.

Status: **working.** 2026.9.1 builds, boots, and restores a 2025.11.3 backup. In
production on a Raspberry Pi 3. Published images: `ghcr.io/adyoull/ha-armv7`.

## Quick start

```bash
chmod +x build.sh
./build.sh              # latest HA from source, armv7
./build.sh 2026.5.4     # a specific version
./build.sh --fallback   # skip the build, pull the last official armv7 image (2025.11.3)
```

`build.sh` orchestrates the whole thing — refreshes the version pins, builds the
base image if needed, builds the app on top, verifies the tricky packages
(PyAV/pyatv/MFA) landed, and optionally pushes:

```bash
./build.sh 2026.9.1 --push
```

Config is via env: `GHCR_OWNER`, `REV`, `BUILD_JOBS`, `INTEGRATIONS`, and
`REBUILD_BASE=1` to force a base rebuild. Edit the `INTEGRATIONS` default in
`build.sh` to match what you actually run.

## Before you build

- **Docker Desktop → Settings → Resources: ≥8 GB RAM, ≥40 GB disk.** The Rust
  builds (`cryptography`, `pydantic-core`) get OOM-killed at 4 GB under QEMU.
- **`BUILD_JOBS` controls parallelism.** Default is `1` (safe on a low-RAM host).
  On a beefy cross-build machine set it higher — rule of thumb ~2 GB RAM per job
  for the heavy compiles, so `BUILD_JOBS=8` is comfortable on a 32 GB host and
  cuts hours off. Drop it if you see `signal: killed` (OOM).
- **Budget several hours** regardless. FFmpeg, numpy, PyAV and friends all compile
  from scratch on an emulated 32-bit CPU.
- **Changing `HA_VERSION` only rebuilds the app image.** FFmpeg, Cython, and the
  toolchain live in the separate base image (`ghcr.io/adyoull/ha-armv7-base`), so
  a version bump recompiles the HA Python packages, not the ~30-min base. Force a
  base rebuild (e.g. to move FFmpeg) with `REBUILD_BASE=1 ./build.sh <ver>`.

## What the Dockerfile does, and why

Each of these was an actual failure hit during this build. They're not
speculative:

The build is split into two images: **`Dockerfile.base`** (Python + toolchain +
FFmpeg 8 + Cython — the slow, version-independent half, built once and pushed to
`ghcr.io/adyoull/ha-armv7-base`) and **`Dockerfile`** (Home Assistant + the fixes,
built `FROM` the base). A Home Assistant version bump only rebuilds the app half;
FFmpeg and Cython never recompile.

| Step | Reason |
|---|---|
| Base `python:3.14-slim-trixie` | HA 2026.x requires Python ≥3.14.2. This tag has an official `linux/arm/v7` variant. |
| `libpcap0.8t64` (not `libpcap0.8`) | Debian trixie renamed it in the 64-bit `time_t` transition. |
| **Base image split** (`Dockerfile.base`) | FFmpeg 8 and Cython take ~30 min to compile under emulation and don't depend on the HA version. Putting them in a separate base image (pushed to GHCR) means version bumps reuse them instead of recompiling. The base is resolved via a registry because the buildx `docker-container` driver resolves `FROM` against registries, not the local image store. |
| **Build FFmpeg 8 from source** | Trixie ships FFmpeg 7.1, but current PyAV (`av==17.x`) uses FFmpeg 8 APIs (`sws_free_context`, opaque `SwsContext`) and won't compile against 7.1. Not an armv7 issue — fails the same on x86. Pulling FFmpeg 8 from Debian testing would drag in a newer glibc, so it's built into `/usr/local` in the base image. |
| **Patch PyAV before building** (`patch_av.sh`) | HA pins `av==17.0.1`, whose `pyio.py` redeclares `seek_func: seek_func_t = …`. Cython 3.1.7+ (a *new* release) rejects that as `'seek_func' redeclared`, so `av` no longer builds from source. We fetch the sdist (via curl, not `pip download` — that runs the build hook on the un-patched source), apply the one-line fix av 18.1 shipped, and build with `--no-build-isolation` against the base's Cython + FFmpeg 8. armv7 hits this because it's the only arch with no prebuilt `av` wheel. |
| `resolve_reqs.py` | `pip install homeassistant` installs **only the core framework**. Integration requirements live in per-integration `manifest.json`. This walks the graph and installs them at build time, so the Pi compiles nothing for core. |
| `ALWAYS` list in `resolve_reqs.py` | HA components import each other *without* declaring it in `dependencies`, so a pure graph walk misses them: `analytics`/`homeassistant_alerts` → `hassio` → `aiohasupervisor`; `usb` → `serialx` → `aioesphomeapi`; plus `gtts`, `infrared_protocols`, `rf_protocols`. |
| `official-<ver>.txt` constraints | Version pins lifted from the **official arm64 image** via `pip freeze`. No arm64 binaries are used — it's a parts list, so we install the exact versions HA ships. |
| Relink `pymicro_vad` etc. with `-lstdc++` | These ship C++ sources whose `setup.py` links with `gcc`, not `g++`. On x86/arm64 nobody notices (prebuilt wheels); on armv7 they compile and produce a `.so` missing the C++ runtime → `undefined symbol: _ZTVN10__cxxabiv120__function_type_infoE`. |
| Pre-build `pyatv` + `miniaudio` | `apple_tv` → `pyatv` → `miniaudio`, whose build pins an ancient `cffi==1.15.0` that won't compile on Python 3.14. Install a modern `cffi` first, then build both with `--no-build-isolation`. |
| Pre-install `pyotp` + `PyQRCode` | TOTP two-factor-auth modules, declared in HA source not a manifest, so the resolver misses them. Needed so HA doesn't try to install at runtime — which fails under udocker/Termux. |
| `go2rtc` binary | HA's `go2rtc` integration shells out to a binary the official image bundles. Pulled from upstream's 32-bit ARM release. |
| **Build toolchain kept in the image** (~2 GB) | Deliberate. HACS custom components install their pip deps *at runtime on the Pi*, and there are no armv7 wheels for Python 3.14 — so gcc/rustc must be present on the device. |

To refresh the constraints file for a different HA version:

```bash
docker run --rm --platform linux/arm64 --entrypoint python \
  ghcr.io/home-assistant/home-assistant:<version> -m pip freeze > official-<version>.txt
```

## Test on the Mac before touching the Pi

```bash
rm -rf /tmp/hatest && mkdir -p /tmp/hatest
docker run -d --name ha-test --platform linux/arm/v7 \
  -p 8123:8123 -v /tmp/hatest:/config ha-armv7:2026.9.1
docker logs -f ha-test
```

Wait for `Home Assistant initialized` — under emulation the frontend serves
*before* the backend is ready, which produces confusing "Unknown command" errors
if you rush it. Then open `http://localhost:8123`.

**Test the restore, not just onboarding.** Drop a backup into
`/tmp/hatest/backups/` and restart, or upload it via onboarding. If a 2025.11.3
backup restores cleanly into 2026.9.1 here, the Pi migration is de-risked.

Verify nothing gets compiled at runtime (this should be empty):

```bash
ls /tmp/hatest/deps
```

## Deploy to the Pi

Transfer the image:

```bash
# Mac
docker save ha-armv7:2026.9.1 | gzip -1 > ha-armv7-2026.9.1.tar.gz
scp ha-armv7-2026.9.1.tar.gz pi@192.168.0.10:~/

# Pi
gunzip -c ha-armv7-2026.9.1.tar.gz | docker load
docker compose up -d
```

Or via a registry:

```bash
docker tag ha-armv7:2026.9.1 ghcr.io/<user>/ha-armv7:2026.9.1
docker push ghcr.io/<user>/ha-armv7:2026.9.1   # needs a classic PAT with write:packages
```

**Add swap on the Pi first.** A 1 GB Pi 2/3 will get OOM-killed compiling HACS
component deps on first run:

```bash
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo dphys-swapfile setup && sudo dphys-swapfile swapon
```

Keep the old image loaded as a rollback:

```bash
docker pull --platform linux/arm/v7 ghcr.io/home-assistant/armv7-homeassistant:2025.11.3
```

## Gotchas found the hard way

- **A missing SSL cert takes down everything.** If `http:` in `configuration.yaml`
  points at a cert file that doesn't exist, `http` fails validation — and
  `websocket_api`, `network`, `zeroconf`, `frontend`, `camera`, `zha`, `hacs` all
  depend on it. You get a hundred tracebacks and `KeyError: 'network'` from one
  missing file. Check this first before blaming the build.
- **`duckdns` no longer supports YAML setup** in 2026 (breaking change since
  2025.11.3) — it must be configured via the UI. Sort this out *before* cutting
  over, since DuckDNS renews the certs `http` depends on.
- **Benign noise:** `Failed to load integration for translation: Invalid domain
  sun.sensor` and similar. Ignore.
- **First boot after restore is slow.** HACS components compile their deps on the
  Pi. HA may exit mid-way; start it again and it continues.

## Reality check

This is unsupported. HA won't accept issue reports for it. It works today, and it
will keep working until some upstream dependency drops 32-bit entirely — at which
point the answer is a 64-bit OS (a Pi 3 *can* run 64-bit Raspberry Pi OS) or new
hardware. Treat this as buying time, not as a permanent position.

## Sources

- [Deprecating Core and Supervised installation methods, and 32-bit systems](https://www.home-assistant.io/blog/2025/05/22/deprecating-core-and-supervised-installation-methods-and-32-bit-systems/)
- [Drop support for the armv7 architecture (architecture discussion #1230)](https://github.com/home-assistant/architecture/discussions/1230)
- [Install Home Assistant Core 2025.12 on armv7 — Lesterpig's Blog](https://blog.lesterpig.com/post/install-home-assistant-core-2025.12-on-armv7/)
- [python — Docker Official Image (arm32v7 variants)](https://hub.docker.com/_/python)

---

## License & attribution

The build tooling in this repository (Dockerfile, scripts, documentation) is
licensed **MIT** — see [`LICENSE`](./LICENSE).

This is an **unofficial, unaffiliated** build. The image it produces contains
[Home Assistant](https://www.home-assistant.io/), which is licensed under the
[Apache License 2.0](https://github.com/home-assistant/core/blob/dev/LICENSE.md)
by the Home Assistant authors, plus many third-party packages that each retain
their own licenses. The MIT license here covers only this repository's tooling,
not Home Assistant or the bundled dependencies.

_Copyright (C) 2026 Andrew Youll._
