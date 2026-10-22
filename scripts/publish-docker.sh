#!/usr/bin/env bash
# Build image and push to Docker Hub (+ optional GHCR).
# Prefers docker buildx for multi-arch; falls back to single-arch docker build.
# Requires: .env with credentials (see .env.example)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example to .env and fill in tokens." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
source .env
set +a

: "${DOCKER_HUB_USER:?Set DOCKER_HUB_USER in .env}"
: "${DOCKER_HUB_TOKEN:?Set DOCKER_HUB_TOKEN in .env}"

DOCKER_HUB_IMAGE="${DOCKER_HUB_IMAGE:-lovemilk233/lx-music-sync-server}"
GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/lovemilk2333/lx-music-sync-server}"
VERSION="${VERSION:-$(node -p "require('./package.json').version")}"
IMAGE_TAGS="${IMAGE_TAGS:-latest ${VERSION}}"
# Local script defaults to Docker Hub only; GHCR is published via GitHub Actions.
PUSH_GHCR="${PUSH_GHCR:-0}"

PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}"
BUILDER_NAME="${BUILDER_NAME:-lx-music-sync-builder}"

has_buildx() {
  docker buildx version >/dev/null 2>&1
}

echo "==> Logging in to Docker Hub as ${DOCKER_HUB_USER}"
echo "${DOCKER_HUB_TOKEN}" | docker login docker.io -u "${DOCKER_HUB_USER}" --password-stdin

if [[ "${PUSH_GHCR}" == "1" ]]; then
  : "${GHCR_USER:?Set GHCR_USER in .env when PUSH_GHCR=1}"
  : "${GHCR_TOKEN:?Set GHCR_TOKEN in .env when PUSH_GHCR=1}"
  echo "==> Logging in to GHCR as ${GHCR_USER}"
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
fi

TAG_ARGS=()
ALL_TAGS=()
for tag in ${IMAGE_TAGS}; do
  TAG_ARGS+=(-t "${DOCKER_HUB_IMAGE}:${tag}")
  ALL_TAGS+=("${DOCKER_HUB_IMAGE}:${tag}")
  if [[ "${PUSH_GHCR}" == "1" ]]; then
    TAG_ARGS+=(-t "${GHCR_IMAGE}:${tag}")
    ALL_TAGS+=("${GHCR_IMAGE}:${tag}")
  fi
done

echo "==> Targets:"
echo "    Hub:  ${DOCKER_HUB_IMAGE}  tags: ${IMAGE_TAGS}"
if [[ "${PUSH_GHCR}" == "1" ]]; then
  echo "    GHCR: ${GHCR_IMAGE}  tags: ${IMAGE_TAGS}"
else
  echo "    GHCR: skipped (use GitHub Actions, or PUSH_GHCR=1)"
fi

if has_buildx; then
  echo "==> Using buildx (${PLATFORMS})"
  if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
    echo "==> Creating buildx builder ${BUILDER_NAME}"
    docker buildx create --name "${BUILDER_NAME}" --use
  else
    docker buildx use "${BUILDER_NAME}"
  fi
  docker buildx inspect --bootstrap >/dev/null

  docker buildx build \
    --platform "${PLATFORMS}" \
    "${TAG_ARGS[@]}" \
    --push \
    .
else
  echo "==> buildx not found — single-arch fallback (current host only)"
  echo "    Install multi-arch support on Arch/CachyOS:"
  echo "      sudo pacman -S docker-buildx"
  echo "    Then re-run this script."
  echo

  docker build "${TAG_ARGS[@]}" .

  echo "==> Pushing tags"
  for ref in "${ALL_TAGS[@]}"; do
    echo "    push ${ref}"
    docker push "${ref}"
  done
fi

echo "==> Done."
echo "    docker pull ${DOCKER_HUB_IMAGE}:latest"
if [[ "${PUSH_GHCR}" == "1" ]]; then
  echo "    docker pull ${GHCR_IMAGE}:latest"
fi
