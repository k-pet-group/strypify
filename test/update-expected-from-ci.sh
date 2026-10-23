#! /bin/bash
# Replaces the reference images (expected-*.png) with the images generated on Linux by a CI run.
# Use this after a Strype release changes how things look and so makes the image tests fail.
#
# Usage (from test/):  ./update-expected-from-ci.sh RUN_ID
#
# CI uploads the generated images on every run (as images-Ubuntu, images-Windows and images-macOS), whether or not
# the comparison passed. Only the Linux ones are used as references; the other platforms are compared to them
# loosely. IMPORTANT: look at the images before committing them -- they become the references, so a wrong render
# (e.g. a dialog, or the wrong project) would be treated as correct from then on.
set -e

RUN_ID="$1"
if [ -z "$RUN_ID" ]; then
  echo "Usage: $0 RUN_ID" >&2
  exit 1
fi

DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

gh run download "$RUN_ID" -n images-Ubuntu -D "$DOWNLOAD_DIR"
for ACTUAL in "$DOWNLOAD_DIR"/actual-*.png; do
  NAME=$(basename "$ACTUAL")
  cp "$ACTUAL" "expected-${NAME#actual-}"
done
echo "Updated the reference images from the Linux images of run $RUN_ID"
