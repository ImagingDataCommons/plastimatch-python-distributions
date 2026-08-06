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

# Highest version referenced under a symbol namespace across every ELF file in the wheel.
# readelf -V reads .gnu.version_r, which is where versioned symbol requirements live.
highest() {
  local prefix="$1" found=""
  while IFS= read -r -d '' f; do
    if head -c 4 "$f" | grep -q $'\x7fELF'; then
      found+="$(readelf -V "$f" 2>/dev/null | grep -oE "${prefix}_[0-9][0-9.]*" || true)"$'\n'
    fi
  done < <(find "$workdir/unpacked" -type f -print0)
  printf '%s' "$found" | sed "s/^${prefix}_//" | grep -E '^[0-9]' | sort -V | tail -n1
}

exceeds() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ] && [ "$1" != "$2" ]
}

max_glibc="$(highest GLIBC)"

if [ -z "$max_glibc" ]; then
  echo "::error::found no ELF binaries in $wheel_path -- refusing to guess a platform tag"
  exit 1
fi

# The glibc version becomes the platform tag, but glibc is not the only runtime dependency
# and it is the only one a tag can express. A binary built with a gcc-toolset newer than its
# container's base runtime satisfies glibc and still requires a libstdc++ that the target
# distributions do not ship -- pip would install the wheel and it would fail with
# "GLIBCXX_3.4.32 not found". There is no tag for that, so it has to be a hard failure.
#
# Limits correspond to the libstdc++ shipped with the glibc baseline being targeted:
#   glibc 2.28 (RHEL 8)  -> GCC 8  -> GLIBCXX_3.4.25, CXXABI_1.3.11
max_glibcxx_allowed="${MAX_GLIBCXX:-3.4.25}"
max_cxxabi_allowed="${MAX_CXXABI:-1.3.11}"

fail=0
for ns in "GLIBCXX:${max_glibcxx_allowed}" "CXXABI:${max_cxxabi_allowed}"; do
  prefix="${ns%%:*}"
  limit="${ns##*:}"
  actual="$(highest "$prefix")"
  if [ -n "$actual" ] && exceeds "$actual" "$limit"; then
    echo "::error::wheel requires ${prefix}_${actual}, but the targeted baseline provides at most ${prefix}_${limit}"
    echo "          Build the binaries against an older C++ runtime, or link it statically."
    fail=1
  elif [ -n "$actual" ]; then
    echo "${prefix}: requires ${actual}, baseline ${limit} — ok"
  fi
done
[ "$fail" -eq 0 ] || exit 1

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
