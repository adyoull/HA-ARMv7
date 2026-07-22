# Running current Home Assistant on 32-bit ARM (armv7) — 2026 edition

**TL;DR:** Home Assistant stopped publishing armv7 images after `2025.11.3`. You
can still run a *current* release (2026.7.2 and beyond) on a Raspberry Pi 2/3 or
other armv7 board. Either pull a prebuilt image, or rebuild it yourself from the
Dockerfile below. Both are covered here.

This is **unofficial and unsupported**. Home Assistant will not accept issue
reports for it. It works — it's running in production on a Pi 3 — but you are the
maintainer now.

---

## Background: what actually happened

Home Assistant [deprecated 32-bit architectures](https://www.home-assistant.io/blog/2025/05/22/deprecating-core-and-supervised-installation-methods-and-32-bit-systems/)
(i386 / armhf / armv7) in May 2025, citing <1% install share and mounting CI pain.

Two things people get wrong:

- **The last official armv7 image is `2025.11.3`**, not 2025.12.x. The blog said
  support ran "until release 2025.12", but the armv7 image builds stopped a
  release earlier. If you're scripting a fallback, look for 2025.11.3.
- **The blocker isn't the code, it's the wheels.** HA's wheel index no longer
  publishes armv7 wheels, and HA 2026.x requires Python ≥3.14.2. So every native
  dependency — numpy, cryptography, pydantic-core, orjson, PyAV — has to be
  compiled from source for armv7. That's the entire difficulty.

Nothing in Home Assistant itself is 64-bit-only. It's a build problem.

---

## Option A — Pull the prebuilt image

```bash
docker pull ghcr.io/adyoull/ha-armv7:2026.7.2
```

`docker-compose.yml`:

```yaml
services:
  homeassistant:
    image: ghcr.io/adyoull/ha-armv7:2026.7.2
    container_name: homeassistant
    restart: unless-stopped
    network_mode: host          # required for mDNS/SSDP discovery
    privileged: true
    volumes:
      - ./config:/config
      - /run/dbus:/run/dbus:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      - TZ=Europe/London
    # Zigbee/Z-Wave stick:
    # devices:
    #   - /dev/ttyUSB0:/dev/ttyUSB0
```

```bash
docker compose up -d
docker compose logs -f
```

**Trusting a stranger's image is a real decision.** It's a container with your
home automation in it. If that bothers you — and it reasonably might — use
Option B and build it yourself from the Dockerfile. That's why the full recipe is
here rather than just a `docker pull` line.

---

## Option B — Build it yourself

You need a **build host that isn't the Pi**: any x86 or Apple Silicon machine with
Docker. Building on the Pi itself would take days and probably OOM.

### Requirements

- Docker with `buildx` (Docker Desktop has it)
- **≥8 GB RAM allocated to Docker.** The Rust builds (`cryptography`,
  `pydantic-core`) get OOM-killed at 4 GB under emulation. This is the single most
  common failure.
- ≥40 GB free disk
- **Several hours.** FFmpeg, numpy and PyAV all compile from scratch on an
  emulated 32-bit CPU. Start it and go to bed.

### 1. Get the official version pins

Not required, but strongly recommended — it makes the build reproducible and
avoids version-skew bugs. This reads the *package list* out of the official arm64
image. **No arm64 binaries are used**; it's a parts list.

```bash
docker run --rm --platform linux/arm64 --entrypoint python \
  ghcr.io/home-assistant/home-assistant:2026.7.2 \
  -m pip freeze > official-2026.7.2.txt
```

### 2. `resolve_reqs.py`

`pip install homeassistant` installs **only the core framework**. Every
integration's dependencies live in its own `manifest.json`, and the official image
pre-installs them. This script walks that graph so we can too.

```python
#!/usr/bin/env python3
"""Resolve the pip requirements for a set of Home Assistant integrations."""

import json
import pathlib
import sys

import homeassistant.components

COMPONENTS = pathlib.Path(homeassistant.components.__file__).parent

# HA components import each other WITHOUT declaring it in manifest "dependencies",
# so a pure dependency walk misses them. Each of these was a real boot failure:
#   analytics, homeassistant_alerts -> components.hassio -> aiohasupervisor
#   usb                             -> serialx           -> aioesphomeapi
#   infrared                        -> infrared_protocols
#   radio_frequency                 -> rf_protocols
#   google_translate (default TTS)  -> gtts
ALWAYS = [
    "hassio", "esphome", "google_translate", "infrared",
    "radio_frequency", "usb", "bluetooth", "stream",
]

EXTRA_PACKAGES = ["zlib-ng", "isal"]   # silences an aiohttp perf warning


def manifest(domain: str) -> dict | None:
    path = COMPONENTS / domain / "manifest.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def main() -> int:
    roots = sys.argv[1:] or ["default_config"]

    seen: set[str] = set()
    queue: list[str] = list(roots) + ALWAYS
    reqs: set[str] = set(EXTRA_PACKAGES)
    missing: list[str] = []

    while queue:
        domain = queue.pop()
        if domain in seen:
            continue
        seen.add(domain)

        m = manifest(domain)
        if m is None:
            missing.append(domain)      # custom/HACS component - expected
            continue

        reqs.update(m.get("requirements", []))
        queue.extend(m.get("dependencies", []))
        queue.extend(m.get("after_dependencies", []))

    print(f"# {len(seen)} integrations -> {len(reqs)} requirements", file=sys.stderr)
    if missing:
        print(f"# not built-in: {', '.join(sorted(missing))}", file=sys.stderr)

    for r in sorted(reqs):
        print(r)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

### 3. `Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
ARG PY_TAG=3.14-slim-trixie
FROM python:${PY_TAG}

ARG HA_VERSION=2026.7.2

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    MAKEFLAGS=-j1 \
    CARGO_BUILD_JOBS=1 \
    NPY_NUM_BUILD_JOBS=1 \
    UV_CONCURRENT_BUILDS=1 \
    HOME=/config

# Toolchain is intentionally KEPT in the final image: HACS custom components
# install their pip deps at runtime on the Pi, and there are no armv7 wheels for
# Python 3.14 - so gcc/rustc must be present on the device.
# NOTE: libpcap0.8t64, not libpcap0.8 - Debian trixie renamed it in the 64-bit
# time_t transition.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config autoconf cmake git curl ca-certificates \
      rustc cargo \
      libssl-dev libffi-dev zlib1g-dev libjpeg-dev libturbojpeg0 \
      libxml2-dev libxslt1-dev libudev-dev libpcap0.8t64 \
      libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev \
      libswscale-dev libswresample-dev libavfilter-dev ffmpeg \
      libgammu-dev bluez iputils-ping nmap tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel && pip install uv

# The long one: numpy, cryptography, pydantic-core, orjson, aiohttp all compile
# from source for armv7. Hours.
RUN pip install "homeassistant==${HA_VERSION}"

# --- FFmpeg 8 -----------------------------------------------------------------
# Debian trixie ships FFmpeg 7.1, but current PyAV (needed by `stream` and
# `onvif`) uses FFmpeg 8 APIs and won't compile against 7.1 headers:
#     error: implicit declaration of function 'sws_free_context'
#     error: invalid use of undefined type 'struct SwsContext'
# This is NOT an armv7 problem - it fails identically on x86. Taking FFmpeg 8 from
# Debian testing would drag in a newer glibc, so build it into /usr/local.
ARG FFMPEG_VERSION=8.0
RUN apt-get update && apt-get install -y --no-install-recommends yasm nasm xz-utils \
 && apt-get purge -y \
      libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev \
      libswscale-dev libswresample-dev libavfilter-dev \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o /tmp/ffmpeg.tar.xz \
 && mkdir -p /tmp/ffmpeg && tar xf /tmp/ffmpeg.tar.xz -C /tmp/ffmpeg --strip-components=1 \
 && cd /tmp/ffmpeg \
 && ./configure --prefix=/usr/local --enable-shared --disable-static \
      --enable-gpl --enable-version3 --disable-doc --disable-debug \
 && make -j1 && make install && ldconfig \
 && rm -rf /tmp/ffmpeg /tmp/ffmpeg.tar.xz \
 && ffmpeg -version | head -1

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    LD_LIBRARY_PATH=/usr/local/lib

# --- integration requirements -------------------------------------------------
# Override with the integrations you actually use, e.g.
#   --build-arg INTEGRATIONS="default_config zha mqtt hue shelly"
ARG INTEGRATIONS="default_config met radio_browser"

ARG CONSTRAINTS=official-2026.7.2.txt
COPY ${CONSTRAINTS} /tmp/constraints.raw.txt

# pip rejects editable/VCS/URL entries in a constraints file, and pip freeze emits
# them. Keep only plain name==version pins.
RUN grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*==[A-Za-z0-9][A-Za-z0-9._+-]*$' \
      /tmp/constraints.raw.txt > /tmp/constraints.txt

COPY resolve_reqs.py /tmp/resolve_reqs.py
RUN python /tmp/resolve_reqs.py ${INTEGRATIONS} > /tmp/reqs.txt \
 && cat /tmp/reqs.txt \
 && ( pip install -r /tmp/reqs.txt -c /tmp/constraints.txt \
      || ( echo "!!! batch failed - retrying package-by-package"; \
           while read -r req; do \
             [ -z "$req" ] && continue; \
             pip install "$req" -c /tmp/constraints.txt \
               || echo "$req" >> /etc/ha-armv7-failed-requirements.txt; \
           done < /tmp/reqs.txt ) ) \
 && if [ -f /etc/ha-armv7-failed-requirements.txt ]; then \
      echo "!!! did NOT install:"; cat /etc/ha-armv7-failed-requirements.txt; fi

# --- fix C++ extensions linked without libstdc++ -------------------------------
# Several HA voice packages ship C++ sources whose setup.py links with `gcc`
# instead of `g++`. On x86/arm64 they get prebuilt wheels so nobody notices; on
# armv7 they compile from source and produce a .so missing the C++ runtime:
#   ImportError: undefined symbol: _ZTVN10__cxxabiv120__function_type_infoE
RUN for pkg in pymicro_vad pymicro_features pyspeex-noise webrtc-noise-gain; do \
      if pip show "$pkg" >/dev/null 2>&1; then \
        CXX=g++ LDFLAGS="-lstdc++" \
        pip install --force-reinstall --no-cache-dir \
                    --no-binary "$pkg" "$pkg" -c /tmp/constraints.txt \
          || echo "$pkg (relink)" >> /etc/ha-armv7-failed-requirements.txt; \
      fi; \
    done \
 && python -c "from pymicro_vad import MicroVad; MicroVad(); print('pymicro_vad OK')" \
 && python -c "import av; print('PyAV OK', av.__version__)"

# --- go2rtc -------------------------------------------------------------------
# HA's go2rtc integration shells out to a binary the official image bundles.
RUN curl -fsSL -o /usr/local/bin/go2rtc \
      "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm" \
 && chmod +x /usr/local/bin/go2rtc

VOLUME /config
EXPOSE 8123
CMD ["python", "-m", "homeassistant", "--config", "/config"]
```

### 4. Build

```bash
docker run --privileged --rm tonistiigi/binfmt --install arm   # QEMU handlers
docker buildx create --name ha-armv7-builder --use

docker buildx build --platform linux/arm/v7 \
  --build-arg HA_VERSION=2026.7.2 \
  --build-arg INTEGRATIONS="default_config zha hue shelly mqtt" \
  -t ha-armv7:2026.7.2 --load .
```

Adjust `INTEGRATIONS` to what you actually run. More integrations = longer build
and a bigger image, but everything is then pre-compiled and the Pi never has to.

### 5. Ship it to the Pi

```bash
docker save ha-armv7:2026.7.2 | gzip -1 > ha-armv7-2026.7.2.tar.gz
scp ha-armv7-2026.7.2.tar.gz pi@<pi-ip>:~/

# on the Pi
gunzip -c ha-armv7-2026.7.2.tar.gz | docker load
```

---

## Before you switch over

**Add swap on the Pi.** A 1 GB Pi 2/3 will get OOM-killed compiling HACS
component dependencies on first run:

```bash
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo dphys-swapfile setup && sudo dphys-swapfile swapon
```

**Keep the last official image as a rollback:**

```bash
docker pull --platform linux/arm/v7 \
  ghcr.io/home-assistant/armv7-homeassistant:2025.11.3
```

**Test the restore on your build machine first.** Take a backup from your existing
install, boot the new image with an empty config dir, and restore into it. If a
2025.11.3 backup restores cleanly into 2026.7.2 there, the migration is de-risked
before you touch the Pi. (Restoring *forward* is fine; HA won't restore a newer
backup into an older version.)

---

## Troubleshooting

**A hundred tracebacks and `KeyError: 'network'` everywhere.**
Look further up the log for a failed `http` setup. If `configuration.yaml` points
`ssl_certificate` at a file that doesn't exist, `http` fails validation — and
`websocket_api`, `network`, `zeroconf`, `frontend`, `camera`, `zha` and `hacs` all
depend on it. One missing file, a hundred errors. Check this before blaming the
build.

**`duckdns` errors after upgrading.**
DuckDNS no longer supports YAML setup in 2026 — configure it via the UI. Relevant
because it's often what renews the certs `http` depends on.

**`undefined symbol: _ZTVN10__cxxabiv120__function_type_infoE`**
A C++ extension got linked without libstdc++. Rebuild it with
`CXX=g++ LDFLAGS="-lstdc++" pip install --force-reinstall --no-binary <pkg> <pkg>`.

**`implicit declaration of function 'sws_free_context'` when building PyAV.**
Your FFmpeg is 7.x; current PyAV needs FFmpeg 8. Build FFmpeg 8 (see Dockerfile).

**Build killed with no error.**
OOM. Raise Docker's memory limit to 8 GB+.

**`ModuleNotFoundError` for some package at boot.**
An integration requirement the resolver missed. Add the integration to
`INTEGRATIONS`, or the package to `EXTRA_PACKAGES` in `resolve_reqs.py`.

**"Unknown command" / weird frontend errors on first boot.**
The frontend serves before the backend finishes starting. Wait for
`Home Assistant initialized` in the log, then reload.

---

## Running under udocker / Termux (Android)

This image also runs on Android via [Termux](https://termux.dev/) + `udocker`
(e.g. the `HomeAssistant-Termux` scripts), not just real Docker. It mostly works —
but with one important limitation:

> **udocker/proot cannot install Python packages at runtime.**

Real Docker on a Pi lets Home Assistant `pip install` things on demand. udocker
uses proot, a much weaker sandbox, and HA's installer (`uv`) fails inside it — in
several different ways depending on the run, all from the same cause:

```
Could not persist temporary file /config/.cache/uv/... : Operation not permitted
failed to open /config/deps/<pkg>.dist-info/METADATA: No such file or directory
Unexpected netlink response of size 11 on descriptor 11 (address family 16)
```

`Operation not permitted` (no atomic rename on Android storage), the missing
`METADATA` (uv can't read back what it wrote), and the `netlink … address family
16` error (proot blocks `AF_NETLINK`) are all the same problem: **the in-container
installer doesn't work here.** So anything HA tries to install on demand must be
provided ahead of time instead.

### The usual culprit: MFA (two-factor auth)

If your account has TOTP two-factor enabled, HA tries to install `pyotp` and
`PyQRCode` on first boot — and crashes into recovery mode when the install fails:

```
ERROR [homeassistant.util.package] Unable to install package pyotp==2.9.0: ...
ERROR [homeassistant.bootstrap] Home Assistant core failed to initialize.
WARNING [homeassistant.bootstrap] ... Activating recovery mode
```

These requirements live in HA's source (`auth/mfa_modules/totp.py`), not in any
integration manifest, so they aren't pre-baked.

### Fix: install the modules into `/config/deps` yourself

HA reads runtime packages from **`/config/deps`**. Both packages are pure Python
(nothing to compile), so you can drop them in from Termux directly, bypassing the
broken in-container installer. Point `--target` at the `deps` folder inside the
config directory that udocker maps to `/config`:

```bash
# from your HA config dir (the one mounted as /config); create deps/ if absent
mkdir -p config/deps
pip install --target config/deps pyotp==2.9.0 PyQRCode==1.2.1
```

If Termux's `pip` won't cooperate, download the wheels and unzip them (a `.whl`
is just a zip):

```bash
mkdir -p config/deps && cd config/deps
pip download --no-deps pyotp==2.9.0 PyQRCode==1.2.1
for w in *.whl; do unzip -o "$w" && rm "$w"; done
```

Restart HA. It will find the packages already present and skip the installer.

### The same trick for anything else HA can't install

If a **HACS custom component** or any other integration crashes with a similar
"Unable to install package X" under udocker, install `X` into `config/deps` the
same way. If `X` needs compiling (not pure Python), it won't work under Termux at
all — it has to be baked into the image at build time instead (see Option B), or
run on real Docker.

### Better: bake it into the image

So users never hit this, the published image pre-installs the MFA modules:

```dockerfile
RUN pip install pyotp==2.9.0 PyQRCode==1.2.1 -c /tmp/constraints.txt \
      || pip install pyotp PyQRCode
```

If you maintain your own build, add any package your setup installs at runtime to
the image the same way — on udocker/Termux, pre-baking is the only reliable path.

---

## Reality check

This buys you time; it isn't a permanent answer. When some upstream dependency
drops 32-bit entirely, this stops working, and no amount of Dockerfile cleverness
will help.

The real fix, if your hardware allows it: **a Pi 3 can run 64-bit Raspberry Pi
OS.** Reflash to arm64 and you're back on officially supported images forever. The
build above is for when you can't or won't do that yet.
