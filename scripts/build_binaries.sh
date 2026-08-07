#!/usr/bin/env bash
#
# Configure and build the superbuild, then test and package plastimatch.
#
# One script for all three platforms. It is invoked directly on macOS and Windows runners
# (the latter under git-bash) and inside a manylinux container on Linux -- which is the
# whole point of routing everything through a script rather than through per-platform YAML.
#
# Environment:
#   SOURCE_DIR    repository root (default: cwd)
#   BUILD_DIR     superbuild binary directory (default: $SOURCE_DIR/build)
#   PLM_GIT_TAG   plastimatch tag/branch/commit to package (default: superbuild's own default)
#   PLM_GIT_REPO  plastimatch repository (default: superbuild's own default)
#   OSX_ARCH      macOS target architecture (arm64 or x86_64)
#   OSX_TARGET    macOS deployment target (default 13.0)

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-$(pwd)}"
BUILD_DIR="${BUILD_DIR:-${SOURCE_DIR}/build}"
OSX_TARGET="${OSX_TARGET:-13.0}"

configure_args=(
  -S "${SOURCE_DIR}/superbuild"
  -B "${BUILD_DIR}"
  -DCMAKE_BUILD_TYPE=Release
)

case "$(uname -s)" in
  Darwin)
    generator="Ninja"
    # Both are required. Without the deployment target the binary inherits the runner's OS
    # version as its floor, which is how the first round of wheels ended up requiring
    # macOS 15 and excluding most Apple Silicon machines.
    configure_args+=(
      -DCMAKE_OSX_ARCHITECTURES="${OSX_ARCH:?OSX_ARCH must be set on macOS}"
      -DCMAKE_OSX_DEPLOYMENT_TARGET="${OSX_TARGET}"
    )
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # The Visual Studio generator rather than Ninja: it sets up the MSVC environment itself,
    # where Ninja would need vcvarsall sourced into this shell first.
    generator="Visual Studio 17 2022"
    configure_args+=(-A x64)
    ;;
  *)
    generator="Ninja"
    ;;
esac

configure_args+=(-G "${generator}")

if [ -n "${PLM_GIT_REPO:-}" ]; then
  configure_args+=(-DPLASTIMATCH_GIT_REPOSITORY="${PLM_GIT_REPO}")
fi
if [ -n "${PLM_GIT_TAG:-}" ]; then
  configure_args+=(-DPLASTIMATCH_GIT_TAG="${PLM_GIT_TAG}")
fi

echo "=== configuring superbuild (${generator}) ==="
cmake "${configure_args[@]}"

echo "=== building superbuild ==="
# --config Release is a no-op for Ninja and required for the Visual Studio generator.
cmake --build "${BUILD_DIR}" --config Release

plm_build="${BUILD_DIR}/plastimatch-build"

echo "=== running the plastimatch test suite ==="
# Gating. The suite runs ~578 tests in well under a minute on Linux and macOS. A failure
# here should block the package rather than be reported and ignored.
( cd "${plm_build}" && ctest --output-on-failure -C Release )

echo "=== packaging ==="
# The archive's name is not the same on every platform. plastimatch's CMakeLists resets
# CPACK_PACKAGE_NAME to "Plastimatch" inside an `if (CPACK_GENERATOR STREQUAL "WIX")` block,
# and CPACK_GENERATOR defaults to WIX on Windows, so the name is fixed at configure time and
# `cpack -G ZIP` does not undo it:
#
#   Linux/macOS   plastimatch-1.10.0-Linux.zip
#   Windows       Plastimatch-1.10.0-win64.zip
#
# So do not guess it. cpack reports the absolute path of what it wrote; parse that instead,
# which is also immune to any future change in how the name is composed.
cpack_log="${BUILD_DIR}/cpack-output.txt"
( cd "${plm_build}" && cpack -G ZIP -C Release ) | tee "${cpack_log}"

package="$(tr -d '\r' < "${cpack_log}" \
  | sed -n 's/^CPack: - package: \(.*\) generated\.$/\1/p' | head -1)"

if [ -z "${package}" ] || [ ! -f "${package}" ]; then
  echo "::error::could not determine which package cpack produced; see ${cpack_log}" >&2
  exit 1
fi

# The basename, not the path. On Linux this script runs inside the manylinux container, where
# BUILD_DIR is /work/build; the workflow steps that consume this run on the host, where the
# same directory has a different absolute path. The basename is the only part that travels.
basename "${package}" > "${BUILD_DIR}/package-name.txt"

ls -la "${package}"
echo "package: ${package}"
