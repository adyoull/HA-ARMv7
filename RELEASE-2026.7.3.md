# Home Assistant 2026.7.3 for ARMv7 — `2026.7.3-r1`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.7.3**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.7.3-r1
```

Also tagged `2026.7.3` and `latest`. Pin to **`2026.7.3-r1`** for a stable,
unchanging reference — `latest` will move when a newer HA build is published.

| Tag | Meaning |
|---|---|
| `2026.7.3-r1` | This exact image. Immutable — safe to pin. |
| `2026.7.3` | Rolling pointer for HA 2026.7.3 (currently = r1). |
| `latest` | Newest build overall. Will change under you. |

## What changed since `2026.7.2-r2`

**Home Assistant upstream bumped 2026.7.2 → 2026.7.3** (patch release). This image
rebuilds against it, with the official 2026.7.3 dependency pins — plus two build
improvements.

**Apple TV now works.** The `apple_tv` integration needs `pyatv` → `miniaudio`,
whose build pins an ancient `cffi==1.15.0` that won't compile against Python 3.14:

```
c/_cffi_backend.c: error: implicit declaration of function ...
error: command '/usr/bin/gcc' failed with exit code 1
hint: miniaudio (v1.58) was included because pyatv (v0.18.0) depends on miniaudio
```

Left unfixed, the runtime install retried every ~15 minutes forever (each failure
logged as `Task exception was never retrieved`). r1 pre-builds both at image build
time, installing a modern `cffi` first and building with `--no-build-isolation`:

```dockerfile
RUN pip install "cffi>=1.17.1" -c /tmp/constraints.txt \
 && pip install --no-build-isolation miniaudio \
 && pip install --no-build-isolation "pyatv==0.18.0" -c /tmp/constraints.txt
```

**Faster builds.** Parallelism is now a build arg — `--build-arg BUILD_JOBS=N`
(default 1). On a 32 GB cross-build host, `BUILD_JOBS=8` cuts hours off the build.

Otherwise unchanged from r2: same base (`python:3.14-slim-trixie`), FFmpeg 8 build
for PyAV, libstdc++ relink for the voice C++ extensions, and the pre-baked MFA
modules (`pyotp`, `PyQRCode`).

Version pins refreshed from the official arm64 image:

```bash
docker run --rm --platform linux/arm64 --entrypoint python \
  ghcr.io/home-assistant/home-assistant:2026.7.3 -m pip freeze > official-2026.7.3.txt
```

For the upstream Home Assistant 2026.7.3 changelog, see the
[Home Assistant release notes](https://www.home-assistant.io/blog/categories/core/).

## Who should update

Anyone on 2026.7.2-r2 who wants the upstream patch fixes, and anyone using — or
being nagged by discovery of — an **Apple TV**. It's a routine patch: no migration
steps, restores forward from any earlier 2026.7.x backup.

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.7.3-r1 \
  -c "from homeassistant.const import __version__; from importlib.metadata import version; \
      print(__version__, '| pyotp', version('pyotp'), '| PyQRCode', version('PyQRCode'))"
```

Expected: `2026.7.3 | pyotp 2.9.0 | PyQRCode 1.2.1`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting (including the udocker/Termux limitations)
are in [`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
