# Home Assistant 2026.9.3 for ARMv7 — `2026.9.3-r1`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.9.3**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.9.3-r1
```

Also tagged `2026.9.3` and `latest`. Pin to **`2026.9.3-r1`** for a stable,
unchanging reference.

| Tag | Meaning |
|---|---|
| `2026.9.3-r1` | This exact image. Immutable — safe to pin. |
| `2026.9.3` | Rolling pointer for HA 2026.9.3. |
| `latest` | Newest build overall. Will change under you. |

## What changed since `#-r1`

**Home Assistant upstream bumped # → 2026.9.3.** This image rebuilds against it
with the official 2026.9.3 dependency pins. Still Python 3.14.

bump

Everything carried over from `#-r1`: base + app image split, PyAV source
patch (`patch_av.sh`), libstdc++ relink, `pyatv`/`miniaudio` (Apple TV),
`bleak-smlight` from source, MFA modules, and the HTTPS-aware healthcheck.

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.9.3-r1 \
  -c "from homeassistant.const import __version__; from importlib.metadata import version; import av; \
      print(__version__, '| av', version('av'), '| pyatv', version('pyatv'), \
            '| pyotp', version('pyotp'), '| bleak-smlight', version('bleak-smlight'))"
```

Expected: `2026.9.3 | av <pin> | pyatv 0.18.0 | pyotp 2.9.0 | bleak-smlight 1.1.0`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting are in
[`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
