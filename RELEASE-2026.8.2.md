# Home Assistant 2026.8.2 for ARMv7 — `2026.8.2-r1`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.8.2**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.8.2-r1
```

Also tagged `2026.8.2` and `latest`. Pin to **`2026.8.2-r1`** for a stable,
unchanging reference — `latest` will move when a newer HA build is published.

| Tag | Meaning |
|---|---|
| `2026.8.2-r1` | This exact image. Immutable — safe to pin. |
| `2026.8.2` | Rolling pointer for HA 2026.8.2 (currently = r1). |
| `latest` | Newest build overall. Will change under you. |

## What changed since `2026.8.1-r1`

**Home Assistant upstream bumped 2026.8.1 → 2026.8.2** (patch release). This image
rebuilds against it, with the official 2026.8.2 dependency pins. Still Python
3.14; no base-image change.

No changes to the build recipe. Everything carried over from 2026.8.1-r1:

- Base `python:3.14-slim-trixie`, FFmpeg 8 (cached above the HA install, so it did
  not recompile for this bump)
- libstdc++ relink for the voice C++ extensions
- `pyatv` + `miniaudio` pre-built (Apple TV fix)
- MFA modules (`pyotp`, `PyQRCode`) pre-baked

Documentation added troubleshooting for two classes of failure seen in the wild:
packages that ship only binary wheels with no armv7 source (e.g. `bleak-smlight`
— benign log noise unless you own the hardware), and corrupted
`.dist-info/METADATA` installs (e.g. `midea-lan`).

Version pins refreshed from the official arm64 image:

```bash
docker run --rm --platform linux/arm64 --entrypoint python \
  ghcr.io/home-assistant/home-assistant:2026.8.2 -m pip freeze > official-2026.8.2.txt
```

For the upstream Home Assistant 2026.8 changelog, see the
[Home Assistant release notes](https://www.home-assistant.io/blog/categories/core/).

## Who should update

Anyone on 2026.8.1-r1 who wants the upstream patch fixes. Routine patch — no
migration steps, restores forward from any earlier 2026.x backup.

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.8.2-r1 \
  -c "from homeassistant.const import __version__; from importlib.metadata import version; \
      print(__version__, '| pyatv', version('pyatv'), '| pyotp', version('pyotp'))"
```

Expected: `2026.8.2 | pyatv 0.18.0 | pyotp 2.9.0`

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting (including the udocker/Termux limitations)
are in [`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
