# Home Assistant 2026.7.2 for ARMv7 — `2026.7.2-r2`

Unofficial 32-bit ARM (armv7) build of Home Assistant **2026.7.2**, for Raspberry
Pi 2/3 and other armv7 boards on a 32-bit OS. Home Assistant stopped publishing
official armv7 images after `2025.11.3`; this rebuilds a current release from
source.

## Pull

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.7.2-r2
```

Also tagged `2026.7.2` and `latest`. Pin to **`2026.7.2-r2`** for a stable,
unchanging reference — `latest` will move when a newer HA build is published.

| Tag | Meaning |
|---|---|
| `2026.7.2-r2` | This exact image. Immutable — safe to pin. |
| `2026.7.2` | Rolling pointer for HA 2026.7.2 (currently = r2). |
| `latest` | Newest build overall. Will change under you. |

## What changed since `2026.7.2` (r1)

**Baked in the TOTP two-factor-auth modules — `pyotp` and `PyQRCode`.**

These are declared inside Home Assistant's source
(`auth/mfa_modules/totp.py`), not in any integration `manifest.json`, so the
dependency resolver didn't pick them up. If your account has two-factor auth
enabled, r1 tried to install them at first boot — which fails under **udocker /
Termux**, where proot blocks the runtime installer:

```
ERROR [homeassistant.util.package] Unable to install package pyotp==2.9.0: ...
       Operation not permitted / Unexpected netlink response ... address family 16
WARNING [homeassistant.bootstrap] ... Activating recovery mode
```

r2 pre-installs both, so Home Assistant never invokes the installer and boots
straight through.

Dockerfile change:

```dockerfile
RUN pip install pyotp==2.9.0 PyQRCode==1.2.1 -c /tmp/constraints.txt \
      || pip install pyotp PyQRCode
```

No change to Home Assistant itself — still 2026.7.2. This is a packaging fix only.

## Who should update

- **On udocker / Termux with two-factor auth enabled:** yes — r1 boots into
  recovery mode for you, r2 fixes it.
- **On real Docker (e.g. a Raspberry Pi):** optional. r1 installs these at runtime
  fine there; r2 just skips a first-boot step. Harmless to update.

### Already on r1 and don't want to re-pull?

The two packages are pure Python. Drop them into the deps dir Home Assistant reads
(`/config/deps`) from the host, and restart:

```bash
mkdir -p config/deps
pip install --target config/deps pyotp==2.9.0 PyQRCode==1.2.1
```

## Verify the image

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.7.2-r2 \
  -c "from importlib.metadata import version; \
      print('pyotp', version('pyotp'), '/ PyQRCode', version('PyQRCode'))"
```

## Notes

Unofficial and unsupported — Home Assistant will not accept issue reports for it.
Full build recipe and troubleshooting (including the udocker/Termux limitations)
are in [`HOWTO-armv7-home-assistant.md`](./HOWTO-armv7-home-assistant.md).

If your hardware allows it, the durable fix remains reflashing to **64-bit
Raspberry Pi OS** — a Pi 3 supports it — which puts you back on official images.

---

_Copyright (C) 2026 Andrew Youll._
