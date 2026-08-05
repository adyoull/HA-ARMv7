# Home Assistant 2026.8.0 for ARMv7 — `2026.8.0-r1`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.8.0**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.8.0-r1
```

Also tagged `2026.8.0` and `latest`. Pin to **`2026.8.0-r1`** for a stable,
unchanging reference — `latest` will move when a newer HA build is published.

| Tag | Meaning |
|---|---|
| `2026.8.0-r1` | This exact image. Immutable — safe to pin. |
| `2026.8.0` | Rolling pointer for HA 2026.8.0 (currently = r1). |
| `latest` | Newest build overall. Will change under you. |

## What changed since `2026.7.4-r1`

**Home Assistant upstream bumped 2026.7.x → 2026.8.0** — the monthly minor
release. This image rebuilds against it, with the official 2026.8.0 dependency
pins. Still Python 3.14; no base-image change.

**Build improvement:** the FFmpeg 8 compile now runs *before* the Home Assistant
install in the Dockerfile. FFmpeg doesn't depend on HA, so it now lands in a
cached layer that survives version bumps — future releases reuse it instead of
recompiling FFmpeg from scratch each time. (This build recompiles it once, as the
layer moved.)

Carried over from 2026.7.4-r1: FFmpeg 8 for PyAV, libstdc++ relink for the voice
C++ extensions, pre-built `pyatv`/`miniaudio` (Apple TV), and pre-baked MFA
modules (`pyotp`, `PyQRCode`).

Version pins refreshed from the official arm64 image:

```bash
docker run --rm --platform linux/arm64 --entrypoint python \
  ghcr.io/home-assistant/home-assistant:2026.8.0 -m pip freeze > official-2026.8.0.txt
```

For the upstream Home Assistant 2026.8 changelog, see the
[Home Assistant release notes](https://www.home-assistant.io/blog/categories/core/).

## Who should update

Anyone on 2026.7.4-r1 who wants the 2026.8 feature release. A minor release can
change integration dependencies, so review your setup after upgrading. Restores
forward from any earlier 2026.x backup.

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.8.0-r1 \
  -c "from homeassistant.const import __version__; from importlib.metadata import version; \
      print(__version__, '| pyatv', version('pyatv'), '| pyotp', version('pyotp'))"
```

Expected: `2026.8.0 | pyatv 0.18.0 | pyotp 2.9.0`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting (including the udocker/Termux limitations)
are in [`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
