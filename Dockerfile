# syntax=docker/dockerfile:1
#
# Home Assistant Core - unofficial ARMv7 (32-bit) build
# HA dropped official armv7 images after 2025.12. This rebuilds from source.
#
ARG PY_TAG=3.14-slim-trixie
FROM python:${PY_TAG}

ARG HA_VERSION=2026.7.2

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Keep memory use sane: emulated armv7 + parallel Rust/C builds = OOM
    MAKEFLAGS=-j1 \
    CARGO_BUILD_JOBS=1 \
    NPY_NUM_BUILD_JOBS=1 \
    UV_CONCURRENT_BUILDS=1 \
    HOME=/config

# Build toolchain is intentionally KEPT in the final image.
# HA installs integration dependencies at runtime, and on armv7 there are no
# prebuilt wheels for py3.14 - so it must be able to compile on the device.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config autoconf cmake git curl ca-certificates \
      rustc cargo \
      libssl-dev libffi-dev zlib1g-dev libjpeg-dev libturbojpeg0 \
      libxml2-dev libxslt1-dev libudev-dev libpcap0.8t64 \
      libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev \
      libswscale-dev libswresample-dev libavfilter-dev ffmpeg \
      libgammu-dev bluez iputils-ping nmap tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel \
 && pip install uv

# The long one. Expect hours under QEMU: numpy, cryptography, pydantic-core,
# orjson, aiohttp etc. all compile from source for armv7.
RUN pip install "homeassistant==${HA_VERSION}"

# --- FFmpeg 8 -----------------------------------------------------------------
# Debian trixie ships FFmpeg 7.1, but current PyAV (pulled in by `stream` and
# `onvif`) uses FFmpeg 8 APIs - sws_free_context, opaque struct SwsContext - so
# it fails to compile against 7.1 headers:
#     error: implicit declaration of function 'sws_free_context'
#     error: invalid use of undefined type 'struct SwsContext'
# This is NOT an armv7 problem; it fails the same way on x86. Pulling FFmpeg 8
# from Debian testing would drag in a newer glibc, so build it into /usr/local
# instead. Placed after the HA core install so that layer stays cached.
ARG FFMPEG_VERSION=8.0

RUN apt-get update && apt-get install -y --no-install-recommends yasm nasm xz-utils \
 && apt-get purge -y \
      libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev \
      libswscale-dev libswresample-dev libavfilter-dev \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o /tmp/ffmpeg.tar.xz \
 && mkdir -p /tmp/ffmpeg && tar xf /tmp/ffmpeg.tar.xz -C /tmp/ffmpeg --strip-components=1 \
 && cd /tmp/ffmpeg \
 && ./configure \
      --prefix=/usr/local \
      --enable-shared --disable-static \
      --enable-gpl --enable-version3 \
      --disable-doc --disable-debug \
 && make -j1 && make install && ldconfig \
 && rm -rf /tmp/ffmpeg /tmp/ffmpeg.tar.xz \
 && ffmpeg -version | head -1

# Make sure PyAV's pkg-config finds FFmpeg 8 in /usr/local, not Debian's 7.1
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    LD_LIBRARY_PATH=/usr/local/lib

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
 && python -c "from pymicro_vad import MicroVad; MicroVad(); print('pymicro_vad OK')" \
 && python -c "import av; print('PyAV OK', av.__version__, '/ libav', av.library_versions)"

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
