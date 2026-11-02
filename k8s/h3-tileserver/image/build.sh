#!/usr/bin/env bash
# Builds the h3-tileserver image: tileserver-gl-light at a pinned upstream
# master commit, plus pmtiles-gzip-passthrough.patch.
#
# Master serves gzipped tiles without recompressing them (5.6.0 gunzips and
# re-gzips every tile). The patch makes gzipped PMTiles vector tiles reach that
# path still gzipped.
#
# Usage: k8s/h3-tileserver/image/build.sh [IMAGE] [PLATFORM]
# Needs git, node, rsync, and docker or podman.
set -euo pipefail

COMMIT=2264416ceb5b18524d0c07fee7c97d0266c1e2fc
IMAGE="${1:-us-central1-docker.pkg.dev/climateiq/frontend-artifacts/h3-tileserver:${COMMIT:0:7}-passthrough}"
PLATFORM="${2:-linux/amd64}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${CONTAINER_ENGINE:-$(command -v docker || command -v podman)}"

SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT
git -C "$SRC" init --quiet
git -C "$SRC" fetch --quiet --depth 1 https://github.com/maptiler/tileserver-gl.git "$COMMIT"
git -C "$SRC" checkout --quiet FETCH_HEAD
git -C "$SRC" apply "$HERE/pmtiles-gzip-passthrough.patch"
(cd "$SRC" && node publish.js --no-publish >/dev/null)

"$ENGINE" build --platform "$PLATFORM" -f "$SRC/light/Dockerfile" -t "$IMAGE" "$SRC/light"
echo "$IMAGE"
