# Home Assistant 2026.8.3 for ARMv7 — `2026.8.3-r1`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.8.3**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.8.3-r1
```

Also tagged `2026.8.3` and `latest`. Pin to **`2026.8.3-r1`** for a stable,
unchanging reference.

| Tag | Meaning |
|---|---|
| `2026.8.3-r1` | This exact image. Immutable — safe to pin. |
| `2026.8.3` | Rolling pointer for HA 2026.8.3 (currently = r1). |
| `latest` | Newest build overall. Will change under you. |

## What changed since `2026.8.2-r1`

This is a bigger release than a normal patch — the build architecture was
reworked and a new upstream breakage was fixed.

### PyAV no longer builds from source (fixed)

A **new Cython release (3.1.7+)** started rejecting a pattern in PyAV's source:

```
av/container/pyio.py:40:12: 'seek_func' redeclared
```

HA pins `av==17.0.1`, whose `pyio.py` redeclares `seek_func: seek_func_t = …`.
Cython 3.1.7 made that a hard error, so `av` fails to compile from source. This
breaks **anyone** building PyAV 17.0.1 from source right now — armv7 just hits it
first, because it's the only architecture with no prebuilt `av` wheel to fall back
on. PyAV fixed it in `av 18.1` by dropping the redundant type annotation; we apply
that same one-line fix to the 17.0.1 source at build time (`patch_av.sh`), then
build with `--no-build-isolation` so it uses a known Cython instead of the broken
latest.

### Build split into a base + app image (much faster rebuilds)

FFmpeg 8 and Cython take ~30 minutes to compile under emulation and don't depend
on the Home Assistant version. They now live in a **separate base image**
(`ghcr.io/adyoull/ha-armv7-base`), built once and reused. A Home Assistant version
bump now recompiles only the HA Python packages — FFmpeg and Cython are never
rebuilt. Force a base rebuild with `REBUILD_BASE=1 ./build.sh <ver>`.

Carried over: FFmpeg 8 for PyAV, libstdc++ relink for the voice C++ extensions,
`pyatv`/`miniaudio` (Apple TV), and MFA modules (`pyotp`, `PyQRCode`).

## Who should update

Anyone on 2026.8.2-r1. If you build your own image, you **need** this — PyAV
17.0.1 no longer compiles from source against current Cython without the patch.

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.8.3-r1 \
  -c "from homeassistant.const import __version__; from importlib.metadata import version; \
      print(__version__, '| av', version('av'), '| pyatv', version('pyatv'), '| pyotp', version('pyotp'))"
```

Expected: `2026.8.3 | av 17.0.1 | pyatv 0.18.0 | pyotp 2.9.0`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting (including the udocker/Termux limitations)
are in [`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
