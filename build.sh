#!/usr/bin/env bash
# Cross-build Home Assistant for ARMv7 (32-bit) on an x86/Apple-Silicon Mac.
# Copyright (C) 2026 Andrew Youll
#
#   ./build.sh                     build latest HA from source for armv7
#   ./build.sh 2026.7.4            build a specific version
#   ./build.sh 2026.7.4 --push     build, then push all tags to GHCR
#   ./build.sh --fallback          skip the build, grab the last OFFICIAL armv7 image
#
# Does the whole routine: refresh the version-pin constraints from the official
# arm64 image, cross-build, verify the tricky packages actually landed, tag, and
# (optionally) push. Config via the vars below or matching env overrides.
#
set -euo pipefail
cd "$(dirname "$0")"

# ------------------------------------------------------------------ config ---
PLATFORM="linux/arm/v7"
IMAGE="ha-armv7"                                   # local tag
GHCR_OWNER="${GHCR_OWNER:-adyoull}"                # ghcr.io/<owner>/ha-armv7
REGISTRY="ghcr.io/${GHCR_OWNER}/ha-armv7"
REV="${REV:-r1}"                                   # revision suffix, e.g. 2026.7.4-r1
BUILD_JOBS="${BUILD_JOBS:-8}"                      # compile parallelism (32 GB host -> 8)
INTEGRATIONS="${INTEGRATIONS:-default_config androidtv_remote backup cast co2signal \
dlna_dmr dlna_dms duckdns forecast_solar hue ipp met mobile_app modbus nest onvif \
openuv radio_browser samsungtv shelly sun tuya upnp wiz zha}"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker not found. Install Docker Desktop and start it."
docker info >/dev/null 2>&1 || die "Docker daemon not running."

# ----------------------------------------------------------- arg parsing ---
PUSH=0; FALLBACK=0; HA_VERSION=""
for arg in "$@"; do
  case "$arg" in
    --push)     PUSH=1 ;;
    --fallback) FALLBACK=1 ;;
    --*)        die "Unknown flag: $arg" ;;
    *)          HA_VERSION="$arg" ;;
  esac
done

# ---------------------------------------------------------------- fallback ---
# The multi-arch 'home-assistant' manifest has NO armv7 entry. The armv7 builds
# live in the arch-specific repo: ghcr.io/home-assistant/armv7-homeassistant
OFFICIAL_REPO="ghcr.io/home-assistant/armv7-homeassistant"

fallback() {
  log "Falling back to the last OFFICIAL armv7 image ($OFFICIAL_REPO)"
  TOKEN=$(curl -fsSL "https://ghcr.io/token?scope=repository:home-assistant/armv7-homeassistant:pull&service=ghcr.io" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])') \
    || die "Could not get a ghcr.io pull token."
  TAGS=$(curl -fsSL -H "Authorization: Bearer $TOKEN" \
           "https://ghcr.io/v2/home-assistant/armv7-homeassistant/tags/list?n=10000" \
    | python3 -c '
import sys, json, re
tags = json.load(sys.stdin).get("tags", [])
stable = [t for t in tags if re.fullmatch(r"\d{4}\.\d+\.\d+", t)]
stable.sort(key=lambda s: [int(p) for p in s.split(".")], reverse=True)
print("\n".join(stable[:10]))')
  [[ -n "$TAGS" ]] || die "No stable tags found in $OFFICIAL_REPO."
  echo "  newest stable armv7 tags: $(echo "$TAGS" | tr '\n' ' ')"
  for tag in $TAGS; do
    echo "  pulling $OFFICIAL_REPO:$tag ..."
    if docker pull --platform "$PLATFORM" "$OFFICIAL_REPO:$tag"; then
      docker tag "$OFFICIAL_REPO:$tag" "$IMAGE:$tag"
      docker tag "$IMAGE:$tag" "$IMAGE:latest"
      log "Got official armv7 image -> $IMAGE:$tag"
      FINAL_TAG="$tag"
      return 0
    fi
  done
  die "Could not pull any official armv7 image."
}

setup_qemu() {
  log "Registering QEMU binfmt handlers (needed to run armv7 binaries on this Mac)"
  docker run --privileged --rm tonistiigi/binfmt --install arm >/dev/null
  docker buildx inspect ha-armv7-builder >/dev/null 2>&1 \
    || docker buildx create --name ha-armv7-builder --use >/dev/null
  docker buildx use ha-armv7-builder
}

if [[ "$FALLBACK" == 1 ]]; then
  fallback
  OUT="ha-armv7-${FINAL_TAG}.tar.gz"
  log "Exporting -> $OUT"
  docker save "$IMAGE:$FINAL_TAG" | gzip -1 > "$OUT"
  echo "Done. $IMAGE:$FINAL_TAG  ->  $(pwd)/$OUT"
  exit 0
fi

# ----------------------------------------------------- resolve HA version ---
if [[ -z "$HA_VERSION" ]]; then
  log "Resolving latest Home Assistant version from PyPI"
  HA_VERSION=$(curl -fsSL https://pypi.org/pypi/homeassistant/json \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["info"]["version"])')
fi
TAG_VER="$HA_VERSION"
TAG_REV="${HA_VERSION}-${REV}"

# ------------------------------------------------- refresh constraints pins ---
# Read the package list from the OFFICIAL arm64 image (no arm64 binaries used -
# it's a parts list) so we install the exact versions HA ships.
CONSTRAINTS="official-${HA_VERSION}.txt"
if [[ -f "$CONSTRAINTS" ]]; then
  log "Using existing constraints: $CONSTRAINTS"
else
  log "Fetching version pins from official arm64 image -> $CONSTRAINTS"
  docker run --rm --platform linux/arm64 --entrypoint python \
    "ghcr.io/home-assistant/home-assistant:${HA_VERSION}" \
    -m pip freeze > "$CONSTRAINTS" \
    || die "Could not pull official arm64 image for $HA_VERSION (does the version exist yet?)"
fi

# --------------------------------------------------------------- base image ---
# The slow half (toolchain + FFmpeg 8) lives in a separate base image, built
# once. HA version bumps reuse it - FFmpeg never recompiles. Force a rebuild with
# REBUILD_BASE=1 (e.g. to move FFmpeg or the Python base).
#
# It lives in GHCR, not the local docker store, on purpose: the docker-container
# buildx driver resolves `FROM` against REGISTRIES, not `docker images`, so a
# locally-loaded base can't be used as a FROM. Pushing it to GHCR makes it work
# (and reusable from any build host).
BASE_TAG="${BASE_TAG:-${REGISTRY}-base:1}"
setup_qemu

if [[ "${REBUILD_BASE:-0}" == 1 ]] || ! docker manifest inspect "$BASE_TAG" >/dev/null 2>&1; then
  log "Building + pushing base image $BASE_TAG (toolchain + FFmpeg 8) - one-time, slow"
  echo "    (requires: docker login ghcr.io)"
  docker buildx build \
      --platform "$PLATFORM" \
      -f Dockerfile.base \
      --build-arg "BUILD_JOBS=$BUILD_JOBS" \
      --tag "$BASE_TAG" \
      --push \
      . || die "Base image build/push FAILED (are you logged in: docker login ghcr.io ?)"
else
  log "Reusing existing base image $BASE_TAG (FFmpeg not recompiled)"
fi

# -------------------------------------------------------------------- build ---
log "Target: HA $HA_VERSION  |  $PLATFORM  |  BUILD_JOBS=$BUILD_JOBS  |  base=$BASE_TAG"
echo "    HA version bump recompiles the Python packages only; FFmpeg is cached"
echo "    in the base image. Give Docker Desktop >=8 GB RAM or it will OOM."

if docker buildx build \
      --platform "$PLATFORM" \
      --build-arg "BASE=$BASE_TAG" \
      --build-arg "HA_VERSION=$HA_VERSION" \
      --build-arg "CONSTRAINTS=$CONSTRAINTS" \
      --build-arg "BUILD_JOBS=$BUILD_JOBS" \
      --build-arg "INTEGRATIONS=$INTEGRATIONS" \
      --tag "$IMAGE:$TAG_VER" \
      --tag "$REGISTRY:$TAG_VER" \
      --tag "$REGISTRY:$TAG_REV" \
      --tag "$REGISTRY:latest" \
      --load \
      . ; then
  log "Built $REGISTRY:$TAG_REV"
  FINAL_TAG="$TAG_VER"
else
  die "Source build of $HA_VERSION FAILED on armv7 (run with --fallback for the last official image)"
fi

# ------------------------------------------------------------------- verify ---
log "Verifying the tricky packages actually landed"
docker run --rm --platform "$PLATFORM" --entrypoint python "$IMAGE:$TAG_VER" -c "
from homeassistant.const import __version__
from importlib.metadata import version
print('HA', __version__,
      '| pyatv', version('pyatv'),
      '| miniaudio', version('miniaudio'),
      '| pyotp', version('pyotp'),
      '| PyQRCode', version('PyQRCode'))" \
  || die "Verify failed - a required package is missing from the image."

FAILED=$(docker run --rm --platform "$PLATFORM" --entrypoint sh "$IMAGE:$TAG_VER" \
  -c 'cat /etc/ha-armv7-failed-requirements.txt 2>/dev/null || true')
if [[ -n "$FAILED" ]]; then
  printf '\n\033[1;33m!!! some requirements did NOT install:\033[0m\n%s\n' "$FAILED"
else
  echo "  no failed requirements."
fi

# --------------------------------------------------------------------- push ---
if [[ "$PUSH" == 1 ]]; then
  log "Pushing tags to $REGISTRY"
  docker push "$REGISTRY:$TAG_VER"
  docker push "$REGISTRY:$TAG_REV"
  docker push "$REGISTRY:latest"
fi

# ------------------------------------------------------------------- export ---
OUT="ha-armv7-${TAG_REV}.tar.gz"
log "Exporting image for transfer to the Pi -> $OUT"
docker save "$IMAGE:$TAG_VER" | gzip -1 > "$OUT"

cat <<EOF

Done. Image: $REGISTRY:$TAG_REV
Archive:    $(pwd)/$OUT
Pushed:     $([[ "$PUSH" == 1 ]] && echo yes || echo "no  (re-run with --push, or: docker push $REGISTRY:$TAG_REV)")

On the Pi:
    docker pull $REGISTRY:$TAG_REV
    # or, offline:
    scp "$OUT" pi@raspberrypi.local:~/ && ssh pi@raspberrypi.local \\
      'gunzip -c $OUT | docker load && docker compose up -d'
EOF
