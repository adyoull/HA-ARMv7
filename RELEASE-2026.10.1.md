# Home Assistant 2026.10.1 for ARMv7 — `2026.10.1-r1`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.10.1**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.10.1-r1
```

Also tagged `2026.10.1` and `latest`. Pin to **`2026.10.1-r1`** for a stable,
unchanging reference.

| Tag | Meaning |
|---|---|
| `2026.10.1-r1` | This exact image. Immutable — safe to pin. |
| `2026.10.1` | Rolling pointer for HA 2026.10.1. |
| `latest` | Newest build overall. Will change under you. |

## What changed since `2026.9.3-r1`

**Home Assistant upstream bumped 2026.9.3 → 2026.10.1.** This image rebuilds against it
with the official 2026.10.1 dependency pins. Still Python 3.14.

**Build change: FFmpeg 8.0 → 9.0.2 in the base image.** HA 2026.10 bumped PyAV
`av` from 17.0.1 to 19.0.0, and PyAV 19 requires FFmpeg 9 (it uses `SWS_UNSTABLE`,
`AVCOL_TRC_V_LOG`, `AVCOL_PRI_V_GAMUT`, absent in FFmpeg 8). The base image was
rebuilt with `FFMPEG_VERSION=9.0.2`. The `patch_av.sh` Cython fix now no-ops (av
18.1+ fixed it upstream) but is kept as a guard for older pins.

Everything carried over from `2026.9.3-r1`: base + app image split, PyAV source
patch (`patch_av.sh`), libstdc++ relink, `pyatv`/`miniaudio` (Apple TV),
`bleak-smlight` from source, MFA modules, and the HTTPS-aware healthcheck.

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.10.1-r1 \
  -c "from homeassistant.const import __version__; from importlib.metadata import version; import av; \
      print(__version__, '| av', version('av'), '| pyatv', version('pyatv'), \
            '| pyotp', version('pyotp'), '| bleak-smlight', version('bleak-smlight'))"
```

Expected: `2026.10.1 | av <pin> | pyatv 0.18.0 | pyotp 2.9.0 | bleak-smlight 1.1.0`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting are in
[`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
