# syntax=docker/dockerfile:1
#
# Home Assistant Core - unofficial ARMv7 (32-bit) build
# HA dropped official armv7 images after 2025.11.3. This rebuilds from source.
#
# Copyright (C) 2026 Andrew Youll
#
# This is the FAST half. It builds FROM ha-armv7-base (Python 3.14 + toolchain +
# FFmpeg 8), which contains everything version-independent. A Home Assistant
# version bump only rebuilds the layers below - FFmpeg is in the base image and
# is never touched. Build the base once:
#   docker buildx build --platform linux/arm/v7 -f Dockerfile.base \
#     --build-arg BUILD_JOBS=8 -t ha-armv7-base:1 --load .
#
ARG BASE=ghcr.io/adyoull/ha-armv7-base:1
FROM ${BASE}

ARG BUILD_JOBS=1

# HA_VERSION is the first thing that changes per build, so everything below this
# line rebuilds on a version bump - and nothing above it (all in the base image)
# does.
ARG HA_VERSION=2026.7.2

# The long one. Expect a while under QEMU: numpy, cryptography, pydantic-core,
# orjson, aiohttp etc. all compile from source for armv7.
RUN pip install "homeassistant==${HA_VERSION}"

# --- integration requirements -------------------------------------------------
# pip install homeassistant gives you ONLY the core framework. Integrations
# declare their deps in manifest.json (hass_frontend, haffmpeg, async_upnp_client
# ...). The official image pre-installs these; we must too, or HA boots with a
# broken frontend. Doing it at build time also means the Pi never has to compile
# anything at runtime - which matters a lot on a 1 GB board.
#
# Override to add integrations you use, e.g.:
#   --build-arg INTEGRATIONS="default_config met radio_browser zha"
ARG INTEGRATIONS="default_config met radio_browser"

# Version pins lifted from the OFFICIAL arm64 image (`pip freeze`). Used purely
# as a constraints file - no arm64 binaries are used, everything still compiles
# from source for armv7. This just guarantees we install the exact versions HA
# ships, instead of whatever pip happens to resolve.
#   docker run --rm --platform linux/arm64 --entrypoint python \
#     ghcr.io/home-assistant/home-assistant:${HA_VERSION} -m pip freeze > official-${HA_VERSION}.txt
ARG CONSTRAINTS=official-2026.7.2.txt
COPY ${CONSTRAINTS} /tmp/constraints.raw.txt

# pip rejects a constraints file containing editable/VCS/URL requirements:
#     ERROR: Editable requirements are not allowed as constraints
# pip freeze emits those for anything installed with -e or from a direct URL, so
# keep only plain name==version pins.
RUN grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*==[A-Za-z0-9][A-Za-z0-9._+-]*$' \
      /tmp/constraints.raw.txt > /tmp/constraints.txt \
 && echo "constraints: $(wc -l < /tmp/constraints.txt) pins kept, \
$(( $(wc -l < /tmp/constraints.raw.txt) - $(wc -l < /tmp/constraints.txt) )) dropped"

COPY resolve_reqs.py /tmp/resolve_reqs.py
RUN python /tmp/resolve_reqs.py ${INTEGRATIONS} > /tmp/reqs.txt \
 && echo "--- resolved requirements ---" && cat /tmp/reqs.txt \
 && ( pip install -r /tmp/reqs.txt -c /tmp/constraints.txt \
      || ( echo "!!! batch install failed - retrying package-by-package" \
           && while read -r req; do \
                [ -z "$req" ] && continue; \
                pip install "$req" -c /tmp/constraints.txt \
                  || echo "$req" >> /etc/ha-armv7-failed-requirements.txt; \
              done < /tmp/reqs.txt ) ) \
 && if [ -f /etc/ha-armv7-failed-requirements.txt ]; then \
      echo "!!! these requirements did NOT install on armv7:"; \
      cat /etc/ha-armv7-failed-requirements.txt; \
    fi

# --- PyAV (av) against the base image's FFmpeg 8 ------------------------------
# av has no armv7 wheel, so it compiles from source and must find the FFmpeg 8
# we built into /usr/local (in the base image) via pkg-config. If it's pulled in
# the big batch above and the link fails, the error scrolls past and av ends up
# missing. Build it explicitly here with visible output and a hard check, so a
# broken FFmpeg link fails the build loudly instead of silently.
# The patch: Cython 3.1.7+ rejects the redeclared `seek_func: seek_func_t = ...`
# in av 17.0.1's pyio.py ("'seek_func' redeclared"). HA pins av==17.0.1, which
# predates the upstream fix (dropping the redundant annotation, as in av 18.1).
# We download the sdist, apply that same one-line fix, then build with
# --no-build-isolation so it uses the Cython already in the base image (no ~15min
# recompile) and links against the base image's FFmpeg 8.
# NB: no `#` comments INSIDE the RUN below - Docker's line-continuation parser
# mangles them and silently breaks the && chain.
COPY patch_av.sh /tmp/patch_av.sh
RUN echo "--- pkg-config sees FFmpeg:" \
 && (pkg-config --modversion libavcodec libavformat libavutil \
      || echo "!!! pkg-config CANNOT find FFmpeg - PKG_CONFIG_PATH=$PKG_CONFIG_PATH") \
 && sh /tmp/patch_av.sh /tmp/constraints.txt \
 && python -c "import av; print('PyAV OK', av.__version__, '/ libav', av.library_versions)"

# --- fix C++ extensions linked without libstdc++ -------------------------------
# Several HA voice packages ship C++ sources whose setup.py links with `gcc`
# instead of `g++`. On x86/arm64 they get prebuilt wheels so nobody notices; on
# armv7 they compile from source and produce a .so missing the C++ runtime:
#   ImportError: undefined symbol: _ZTVN10__cxxabiv120__function_type_infoE
# Forcing -lstdc++ into the link step fixes it. Rebuilt individually so one
# failure doesn't nuke the layer.
RUN for pkg in pymicro_vad pymicro_features pyspeex-noise webrtc-noise-gain; do \
      if pip show "$pkg" >/dev/null 2>&1; then \
        echo "--- relinking $pkg against libstdc++"; \
        CXX=g++ LDFLAGS="-lstdc++" \
        pip install --force-reinstall --no-cache-dir \
                    --no-binary "$pkg" "$pkg" -c /tmp/constraints.txt \
          || echo "$pkg (relink)" >> /etc/ha-armv7-failed-requirements.txt; \
      fi; \
    done \
 && echo "--- verifying C++ extensions import" \
 && python -c "from pymicro_vad import MicroVad; MicroVad(); print('pymicro_vad OK')"

# --- pyatv / Apple TV ---------------------------------------------------------
# apple_tv needs pyatv, which depends on miniaudio, whose build-system.requires
# pins an ancient cffi==1.15.0. That cffi predates Python 3.14 and won't compile
# against its headers:
#     c/_cffi_backend.c: error: implicit declaration of function ...
#     error: command '/usr/bin/gcc' failed with exit code 1
# So on armv7+py3.14 the runtime install loops forever and apple_tv never sets up.
# Fix: install a MODERN cffi first, then build miniaudio + pyatv with build
# isolation DISABLED so they use the already-present cffi instead of the pin.
RUN pip install "cffi>=1.17.1" -c /tmp/constraints.txt \
 && pip install --no-build-isolation miniaudio \
 && pip install --no-build-isolation "pyatv==0.18.0" -c /tmp/constraints.txt \
 && python -c "import pyatv, miniaudio; from importlib.metadata import version; print('pyatv', version('pyatv'), '/ miniaudio', version('miniaudio'))" \
      || echo "pyatv/miniaudio" >> /etc/ha-armv7-failed-requirements.txt

# --- auth MFA modules ---------------------------------------------------------
# TOTP MFA requirements live in homeassistant/auth/mfa_modules/totp.py, NOT in
# any manifest.json, so resolve_reqs.py can't find them. HA installs them at
# runtime the first time an MFA-enabled account logs in. That runtime install
# fails on proot/Android (Termux), where /config can't do atomic rename:
#     Could not persist temporary file /config/.cache/uv/... : Operation not permitted
# Baking them in means HA never tries to install anything at runtime.
RUN pip install pyotp==2.9.0 PyQRCode==1.2.1 -c /tmp/constraints.txt \
      || pip install pyotp PyQRCode

# --- go2rtc -------------------------------------------------------------------
# HA's go2rtc integration shells out to a go2rtc binary that the official image
# bundles: "ERROR ... Could not find go2rtc docker binary". Upstream ships a
# 32-bit ARM build, so grab it.
RUN curl -fsSL -o /usr/local/bin/go2rtc \
      "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm" \
 && chmod +x /usr/local/bin/go2rtc \
 && /usr/local/bin/go2rtc --version || echo "!!! go2rtc unavailable - camera WebRTC will be degraded"

LABEL org.opencontainers.image.title="home-assistant-armv7" \
      org.opencontainers.image.description="Unofficial ARMv7 build of Home Assistant Core" \
      org.opencontainers.image.version="${HA_VERSION}"

VOLUME /config
EXPOSE 8123

HEALTHCHECK --interval=60s --timeout=10s --start-period=15m --retries=3 \
  CMD curl -fsS http://127.0.0.1:8123/manifest.json || exit 1

CMD ["python", "-m", "homeassistant", "--config", "/config"]
