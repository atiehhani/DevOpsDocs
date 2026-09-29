#!/usr/bin/env bash
#
# load-tag-push.sh
#
# Usage:
#   ./load-tag-push.sh /path/to/tgz-dir
#
# Example:
#   ./load-tag-push.sh ./images-export
#
# Override container engine if needed:
#   CONTAINER_CMD=podman ./load-tag-push.sh ./images-export
#

set -uo pipefail

CMD="${CONTAINER_CMD:-docker}"
PRIVATE_REG="192.168.227.138:8089"
#PRIVATE_REG="192.168.248.40:8083"
TGZ_DIR="${1:-.}"

OK=0
FAILED=()

if [ ! -d "$TGZ_DIR" ]; then
  echo "Directory not found: $TGZ_DIR"
  exit 1
fi

shopt -s nullglob
FILES=("$TGZ_DIR"/*.tgz)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No .tgz files found in: $TGZ_DIR"
  exit 1
fi

for SRC_FILE in "${FILES[@]}"; do
  echo "========================================"
  echo "Archive: $SRC_FILE"

  echo "Loading..."
  LOAD_OUTPUT="$($CMD load -i "$SRC_FILE" 2>&1)"
  LOAD_RC=$?
  echo "$LOAD_OUTPUT"

  if [ $LOAD_RC -ne 0 ]; then
    echo "  Load failed - skipping."
    FAILED+=("$SRC_FILE (load failed)")
    continue
  fi

  # Try to extract the loaded image reference from docker/podman output.
  # Common outputs:
  #   Loaded image: repo/name:tag
  #   Loaded image(s): repo/name:tag
  IMAGE="$(echo "$LOAD_OUTPUT" | sed -n 's/^Loaded image[s]*: //p' | tail -n1)"

  if [ -z "$IMAGE" ]; then
    echo "  Could not determine loaded image name from load output."
    FAILED+=("$SRC_FILE (could not determine loaded image)")
    continue
  fi

  # Drop source registry hostname (first path component) and prepend private registry
  # Example:
  #   aajfrog.caspian.ir/aadocker/harbor.jibit.cloud/alpha/aio:2.6.0
  # -> 192.168.248.40:8083/aadocker/harbor.jibit.cloud/alpha/aio:2.6.0
  NAME_WITH_TAG="${IMAGE#*/}"
  DEST="${PRIVATE_REG}/${NAME_WITH_TAG}"

  echo "Loaded image: $IMAGE"
  echo "Tagging -> $DEST"
  if ! $CMD tag "$IMAGE" "$DEST"; then
    echo "  Tag failed - skipping."
    FAILED+=("$SRC_FILE (tag failed for $IMAGE)")
    continue
  fi

  echo "Pushing -> $DEST"
  if ! $CMD push "$DEST"; then
    echo "  Push failed."
    FAILED+=("$SRC_FILE (push failed for $DEST)")
    continue
  fi

  echo "  Done."
  OK=$((OK + 1))
done

echo "========================================"
echo "Summary: ${OK} image(s) loaded, tagged and pushed."

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "Failed (${#FAILED[@]}):"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
f
