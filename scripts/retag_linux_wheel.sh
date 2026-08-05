#!/usr/bin/env bash
#
# cibuildwheel repair step for Linux wheels.
#
# The wheels built here contain a prebuilt, statically linked plastimatch executable and no
# compiled Python extension module. auditwheel -- cibuildwheel's default repair tool -- only
# inspects extension modules, so it neither vendors anything nor validates the executable.
# The wheel would therefore be tagged with whatever manylinux version the *build container*
# implements, which says nothing about the glibc the *bundled binary* requires. Installing
# such a wheel succeeds and then fails at run time with
#
#   /lib64/libc.so.6: version `GLIBC_2.39' not found
#
# This script reads the actual glibc requirement out of the ELF binaries in the wheel and
# retags the wheel to match, so pip refuses to install it on too-old systems instead.
#
# Usage: retag_linux_wheel.sh <wheel> <dest_dir>

set -euo pipefail

wheel_path="$1"
dest_dir="$2"

arch="$(uname -m)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

unzip -q "$wheel_path" -d "$workdir/unpacked"

# Collect every GLIBC_x.y version referenced by any ELF file in the wheel and keep the
# highest. readelf -V reads .gnu.version_r, which is where the versioned symbol
# requirements live.
versions=""
while IFS= read -r -d '' f; do
  if head -c 4 "$f" | grep -q $'\x7fELF'; then
    v="$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' || true)"
    versions="$versions$v"$'\n'
  fi
done < <(find "$workdir/unpacked" -type f -print0)

max_glibc="$(printf '%s' "$versions" | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)"

if [ -z "$max_glibc" ]; then
  echo "::error::found no ELF binaries in $wheel_path -- refusing to guess a platform tag"
  exit 1
fi

tag="manylinux_${max_glibc//./_}_${arch}"
echo "bundled binaries require glibc >= ${max_glibc}; tagging wheel as ${tag}"

python -m pip install --quiet --disable-pip-version-check wheel
python -m wheel tags --remove --platform-tag "$tag" "$wheel_path"

# `wheel tags` writes the retagged wheel next to the input and, with --remove, deletes the
# original. Whatever .whl remains in that directory is the one to hand back.
retagged="$(find "$(dirname "$wheel_path")" -maxdepth 1 -name '*.whl' -print -quit)"
if [ -z "$retagged" ]; then
  echo "::error::retagging produced no wheel"
  exit 1
fi

mkdir -p "$dest_dir"
cp "$retagged" "$dest_dir/"
echo "wrote $dest_dir/$(basename "$retagged")"
