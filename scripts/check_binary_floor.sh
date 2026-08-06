#!/usr/bin/env bash
#
# Assert that a Linux package's runtime requirements stay within the manylinux baseline it
# claims to target.
#
# Building inside a manylinux container is necessary but not sufficient. The image ships a
# gcc-toolset newer than its own base runtime libraries, so a careless build satisfies glibc
# and then emits a libstdc++ requirement (GLIBCXX_3.4.32) that the target distributions
# cannot meet. Both floors have to be checked, and neither is visible from the build
# succeeding -- only from the finished binary.
#
# Defaults correspond to manylinux_2_28 (AlmaLinux 8 / RHEL 8):
#   glibc 2.28, libstdc++ from GCC 8 -> GLIBCXX_3.4.25, CXXABI_1.3.11
#
# Usage: check_binary_floor.sh <extracted-package-dir> [max_glibc] [max_glibcxx] [max_cxxabi]

set -euo pipefail

target_dir="${1:?usage: check_binary_floor.sh <dir> [max_glibc] [max_glibcxx] [max_cxxabi]}"
max_glibc="${2:-2.28}"
max_glibcxx="${3:-3.4.25}"
max_cxxabi="${4:-1.3.11}"

# Highest version referenced under a given symbol namespace across every ELF file found.
highest() {
  local prefix="$1" found=""
  while IFS= read -r -d '' f; do
    if head -c 4 "$f" | grep -q $'\x7fELF'; then
      found+="$(readelf -V "$f" 2>/dev/null | grep -oE "${prefix}_[0-9][0-9.]*" || true)"$'\n'
    fi
  done < <(find "$target_dir" -type f -print0)
  printf '%s' "$found" | sed "s/^${prefix}_//" | grep -E '^[0-9]' | sort -V | tail -n1
}

# True when $1 is greater than $2 under version ordering.
exceeds() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ] && [ "$1" != "$2" ]
}

fail=0
for ns in GLIBC:$max_glibc GLIBCXX:$max_glibcxx CXXABI:$max_cxxabi; do
  prefix="${ns%%:*}"
  limit="${ns##*:}"
  actual="$(highest "$prefix")"

  if [ -z "$actual" ]; then
    echo "  ${prefix}: not referenced"
    continue
  fi

  if exceeds "$actual" "$limit"; then
    echo "::error::${prefix}_${actual} required, but the target baseline provides at most ${prefix}_${limit}"
    fail=1
  else
    echo "  ${prefix}: requires ${actual}, baseline ${limit} — ok"
  fi
done

echo "--- dynamic dependencies ---"
while IFS= read -r -d '' f; do
  if head -c 4 "$f" | grep -q $'\x7fELF'; then
    echo "$(basename "$f"): $(readelf -d "$f" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/' | tr '\n' ' ')"
  fi
done < <(find "$target_dir" -type f -print0)

if [ "$fail" -ne 0 ]; then
  echo
  echo "The package requires newer runtime libraries than the manylinux baseline provides."
  echo "Wheels built from it would install cleanly and then fail at run time."
  exit 1
fi

echo "package stays within the manylinux baseline"
