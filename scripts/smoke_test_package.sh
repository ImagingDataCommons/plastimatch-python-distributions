#!/usr/bin/env bash
#
# Exercise a packaged plastimatch archive the way a user would.
#
# This tests the *package*, not the build tree. ctest runs against the build directory, where
# files the package omits are still lying around -- that is how a DCMTK built with an external
# data dictionary passed 578/578 tests while every DICOM read in the shipped zip failed. So
# this extracts the archive somewhere clean, scrubs DCMDICTPATH so no host dictionary can be
# picked up, and checks a real DICOM round-trip.
#
# Note that `plastimatch convert` exits 0 even when it cannot read its input, so the
# assertions are on the output files rather than on exit status.
#
# Usage: smoke_test_package.sh <path-to-package.zip>

set -euo pipefail

archive="${1:?usage: smoke_test_package.sh <package.zip>}"

unset DCMDICTPATH || true

smoke="$(mktemp -d)"
trap 'rm -rf "$smoke"' EXIT

unzip -q "$archive" -d "$smoke/extracted"

bin="$(find "$smoke/extracted" -type f \( -name plastimatch -o -name plastimatch.exe \) -print -quit)"
if [ -z "$bin" ]; then
  echo "::error::no plastimatch executable found in $archive"
  exit 1
fi
echo "testing $bin"

"$bin" --version

"$bin" synth --output "$smoke/s.mha" --pattern sphere --dim 24 \
  --origin "-24 -24 -24" --spacing "2 2 2" --center "0 0 0" --radius 12
test -s "$smoke/s.mha" || { echo "::error::packaged binary could not write an image"; exit 1; }

"$bin" convert --input "$smoke/s.mha" --output-dicom "$smoke/dcm" --output-type short
test -n "$(ls -A "$smoke/dcm" 2>/dev/null)" || {
  echo "::error::packaged binary wrote no DICOM"; exit 1; }

"$bin" convert --input "$smoke/dcm" --output-img "$smoke/rt.mha"
test -s "$smoke/rt.mha" || {
  echo "::error::packaged binary could not read back DICOM -- is the DCMTK data dictionary compiled in?"
  exit 1; }

"$bin" header "$smoke/rt.mha" | tee "$smoke/hdr.txt"
grep -q "Size = 24 24 24" "$smoke/hdr.txt" || {
  echo "::error::DICOM round-trip lost image geometry"; exit 1; }

echo "packaged binary OK: image I/O, DICOM write and DICOM read all work"
