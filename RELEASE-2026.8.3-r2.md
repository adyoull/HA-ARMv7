# Home Assistant 2026.8.3 for ARMv7 — `2026.8.3-r2`

Revision of the 2026.8.3 image. Same Home Assistant 2026.8.3; two fixes on top of
`-r1`. Pull:

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.8.3-r2
```

## What changed since `2026.8.3-r1`

- **`bluetooth_adapters` setup failure fixed.** HA's `bluetooth_adapters` pulls
  the `smlight` scanner backend, which needs `bleak-smlight==1.1.0` — a package
  that ships only compiled wheels (none for armv7), so setup failed and Bluetooth
  was degraded:
  ```
  Setup failed for 'bluetooth_adapters': Requirements for smlight not found:
  ['bleak-smlight==1.1.0']
  ```
  It has an sdist with a Cython extension, so we now build it from source (the
  base image already has Cython + the toolchain). The backend loads even with no
  SMLIGHT device attached, so `bluetooth_adapters` sets up cleanly.

- **Container healthcheck fixed.** The old healthcheck curled `http://` on 8123,
  which fails when `http:` has an `ssl_certificate` (HA then serves HTTPS) — so
  the container showed unhealthy while actually running fine. It now tries HTTPS
  (`-k`, since `127.0.0.1` won't match the cert name) then falls back to HTTP.
  Also settable via `docker-compose.yml` (`healthcheck:`) without rebuilding.

Everything from `-r1` (PyAV Cython patch, base+app split, Apple TV, MFA) carries
over unchanged.

## Verify

```bash
docker run --rm --platform linux/arm/v7 --entrypoint python \
  ghcr.io/adyoull/ha-armv7:2026.8.3-r2 \
  -c "from importlib.metadata import version; import av; \
      print('av', version('av'), '| bleak-smlight', version('bleak-smlight'))"
```

Expected: `av 17.0.1 | bleak-smlight 1.1.0`

---

_Copyright (C) 2026 Andrew Youll._
