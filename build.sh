#!/usr/bin/env bash
# Cross-build Home Assistant for ARMv7 (32-bit) on an x86/Apple-Silicon Mac.
# Copyright (C) 2026 Andrew Youll
#
#   ./build.sh              # build latest HA from source for armv7
#   ./build.sh 2026.5.4     # build a specific version
#   ./build.sh --fallback   # skip the source build, grab the last OFFICIAL armv7 image
#
set -euo pipefail
cd "$(dirname "$0")"

PLATFORM="linux/arm/v7"
IMAGE="ha-armv7"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker not found. Install Docker Desktop and start it."
docker info >/dev/null 2>&1 || die "Docker daemon not running."

# ---------------------------------------------------------------- fallback ---
# The multi-arch 'home-assistant' manifest has NO armv7 entry. The armv7 builds
# live in the arch-specific repo: ghcr.io/home-assistant/armv7-homeassistant
REPO="ghcr.io/home-assistant/armv7-homeassistant"

fallback() {
  log "Falling back to the last OFFICIAL armv7 image ($REPO)"
  echo "  querying available tags ..."

  TOKEN=$(curl -fsSL "https://ghcr.io/token?scope=repository:home-assistant/armv7-homeassistant:pull&service=ghcr.io" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])') \
    || die "Could not get a ghcr.io pull token."

  # Newest stable X.Y.Z tag (no betas/dev builds), highest version first
  TAGS=$(curl -fsSL -H "Authorization: Bearer $TOKEN" \
           "https://ghcr.io/v2/home-assistant/armv7-homeassistant/tags/list?n=10000" \
    | python3 -c '
import sys, json, re
tags = json.load(sys.stdin).get("tags", [])
stable = [t for t in tags if re.fullmatch(r"\d{4}\.\d+\.\d+", t)]
stable.sort(key=lambda s: [int(p) for p in s.split(".")], reverse=True)
print("\n".join(stable[:10]))')

  [[ -n "$TAGS" ]] || die "No stable tags found in $REPO."
  echo "  newest stable armv7 tags: $(echo "$TAGS" | tr '\n' ' ')"

  for tag in $TAGS; do
    echo "  pulling $REPO:$tag ..."
    if docker pull --platform "$PLATFORM" "$REPO:$tag"; then
      docker tag "$REPO:$tag" "$IMAGE:$tag"
      docker tag "$IMAGE:$tag" "$IMAGE:latest"
      log "Got official armv7 image -> $IMAGE:$tag"
      FINAL_TAG="$tag"
      return 0
    fi
  done
  die "Could not pull any official armv7 image."
}

if [[ "${1:-}" == "--fallback" ]]; then
  setup_qemu() { :; }
else
  setup_qemu() {
    log "Registering QEMU binfmt handlers (needed to run armv7 binaries on this Mac)"
    docker run --privileged --rm tonistiigi/binfmt --install arm >/dev/null
    docker buildx inspect ha-armv7-builder >/dev/null 2>&1 \
      || docker buildx create --name ha-armv7-builder --use >/dev/null
    docker buildx use ha-armv7-builder
  }
fi

# ------------------------------------------------------------------- build ---
if [[ "${1:-}" == "--fallback" ]]; then
  fallback
else
  HA_VERSION="${1:-}"
  if [[ -z "$HA_VERSION" ]]; then
    log "Resolving latest Home Assistant version from PyPI"
    HA_VERSION=$(curl -fsSL https://pypi.org/pypi/homeassistant/json \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["info"]["version"])')
  fi
  log "Target: Home Assistant $HA_VERSION  |  platform: $PLATFORM"
  echo "    This compiles numpy / cryptography / pydantic-core / orjson from"
  echo "    source under emulation. Budget 3-8+ hours. Give Docker Desktop at"
  echo "    least 8 GB RAM (Settings > Resources) or it will OOM."

  setup_qemu

  if docker buildx build \
        --platform "$PLATFORM" \
        --build-arg "HA_VERSION=$HA_VERSION" \
        --tag "$IMAGE:$HA_VERSION" \
        --tag "$IMAGE:latest" \
        --load \
        . ; then
    log "Built $IMAGE:$HA_VERSION"
    FINAL_TAG="$HA_VERSION"
  else
    log "Source build of $HA_VERSION FAILED on armv7"
    fallback
  fi
fi

# ------------------------------------------------------------------ export ---
OUT="ha-armv7-${FINAL_TAG}.tar.gz"
log "Exporting image for transfer to the Pi -> $OUT"
docker save "$IMAGE:$FINAL_TAG" | gzip -1 > "$OUT"

cat <<EOF

Done. Image: $IMAGE:$FINAL_TAG
Archive:    $(pwd)/$OUT

Copy it to the Pi and load it:
    scp "$OUT" pi@raspberrypi.local:~/
    ssh pi@raspberrypi.local
    gunzip -c $OUT | docker load
    docker tag $IMAGE:$FINAL_TAG $IMAGE:latest

Then start it with the included docker-compose.yml:
    docker compose up -d
EOF
