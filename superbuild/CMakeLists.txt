# Build layer: compiles plastimatch and its dependencies into a self-contained package.
#
# This exists because upstream plastimatch publishes source archives only, and its own in-tree
# dependency superbuild cannot be used: SuperBuild/External_DCMTK.cmake fetches DCMTK 3.6.2
# from ftp://dicom.offis.de, a server retired years ago, and neither it nor External_ITK.cmake
# builds with the settings a redistributable package needs.
#
# That in-tree superbuild is live, not dead, and it is reached by *falling through* -- the top
# level runs it whenever find_package fails, without an error. (The separate "Broken superbuild
# stuff" block at src/CMakeLists.txt:550, which builds plastimatch inside itself, is the one
# wrapped in `if (false)`.) External_plastimatch.cmake therefore sets PLM_SYSTEM_ITK and
# PLM_SYSTEM_DCMTK to YES to make that fallback unreachable, and check_plastimatch_deps.cmake
# verifies it stayed unreachable.
#
# Structured after dcmqi's CMakeExternals/, which is the reason dcmqi's Linux workflow is 133
# lines where a hand-rolled equivalent is 500. One CMake invocation builds zlib-ng, ITK,
# DCMTK, dlib and plastimatch in dependency order, on all three platforms, so the workflow
# only has to say "configure and build this".
#
# Usage:
#   cmake -S superbuild -B build -DCMAKE_BUILD_TYPE=Release
#   cmake --build build
#
# The result is a CPack-ready plastimatch build tree at ${CMAKE_BINARY_DIR}/plastimatch-build.

cmake_minimum_required(VERSION 3.21)

# C and CXX are enabled deliberately, even though this project compiles nothing itself. Two
# things depend on it: the detected compilers are forwarded to every sub-project so they are
# all built with the same one, and MSVC is only defined once a compiler has been enabled --
# with LANGUAGES NONE the Windows-specific branches below silently never fire.
project(plastimatch-superbuild LANGUAGES C CXX)

# Timestamp extracted archives at extraction time, so changing a dependency's URL actually
# triggers a rebuild instead of being masked by the archive's own mtimes.
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

include(ExternalProject)

#-------------------------------------------------------------------------------------------
# Dependency pins
#
# Every dependency is pinned by version *and* checksum. A version alone is not a pin: GitHub's
# auto-generated tag tarballs (archive/refs/tags/*.tar.gz) are not guaranteed byte-stable and
# have been silently regenerated before, and a tag can be force-moved to a different commit.
# Without URL_HASH either would change what gets compiled into the published binaries with no
# signal. This mirrors how plastimatchUrls.cmake pins the archives the wheels are built from.
#
# A mismatch here is a hard failure, which is the intended behaviour: investigate why the
# bytes changed before updating the hash.
#
# To update a dependency, change the version and recompute:
#   curl -fsSL <url> | shasum -a 256
#
# Bumping any of these changes the content hash of this directory, which is what the build
# workflow keys its dependency cache on -- so a version change invalidates exactly the
# affected build and nothing else.
#-------------------------------------------------------------------------------------------
set(ITK_VERSION "5.4.0" CACHE STRING "ITK version to build")
set(ITK_SHA256 "cdd6ce44f15c1246c3c7a439bbbb431dc09706d6465d79fafb6fb14a02517e3b")

set(DCMTK_VERSION "3.6.8" CACHE STRING "DCMTK version to build")
set(DCMTK_SHA256 "fca429a215739702fe8d96178964036246a35e2ea8adb12da33851e2be8e9a07")

set(ZLIBNG_VERSION "2.3.3" CACHE STRING "zlib-ng version to build")
set(ZLIBNG_SHA256 "f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1")

# The bundled libs/dlib-19.1 in plastimatch cannot be used: it still relies on
# std::binary_function, removed in C++17, and ITK 5.4 forces C++17 on consumers via
# INTERFACE_COMPILE_FEATURES. plastimatch supports linking a real dlib -- the dlib .cpp
# includes in src/sys/dlib_threads.cxx are guarded by !DLIB_HAVE_LIBRARY -- so build a
# current one instead.
set(DLIB_VERSION "19.24.9" CACHE STRING "dlib version to build")
set(DLIB_SHA256 "65ff8debc3ffea84430bdd4992982082caf505404e16d986b7493c00f96f44e9")

#-------------------------------------------------------------------------------------------
# Which plastimatch to package
#
# Defaults to the upstream GitLab repository so this project packages plastimatch without
# forking it. Point these at a fork or a different revision to package something else.
#
# Pinned to a full commit SHA rather than the tag name, for the same reason the dependencies
# carry checksums: a git tag is a mutable pointer, and a full SHA is content-addressed by
# construction. The tag it corresponds to is recorded alongside it.
#
# Resolve a tag to its commit with:
#   curl -fsSL https://gitlab.com/api/v4/projects/plastimatch%2Fplastimatch/repository/tags/<tag>
#-------------------------------------------------------------------------------------------
set(PLASTIMATCH_GIT_REPOSITORY "https://gitlab.com/plastimatch/plastimatch.git"
    CACHE STRING "plastimatch git repository to package")

# plastimatch 1.10.0, released 2024-09-16.
set(PLASTIMATCH_GIT_TAG "db24480dc1086df3278992d62a86e70d8654cb5d"
    CACHE STRING "plastimatch commit to package (a full SHA; a tag or branch also works)")
set(PLASTIMATCH_VERSION_LABEL "1.10.0"
    CACHE STRING "Human-readable label for the pinned plastimatch revision")

#-------------------------------------------------------------------------------------------
# Shared configuration
#-------------------------------------------------------------------------------------------
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "" FORCE)
endif()

set(SB_INSTALL_DIR "${CMAKE_BINARY_DIR}/deps" CACHE PATH
    "Where the dependencies install to")

# Arguments every sub-project inherits. Passing the macOS settings down explicitly matters:
# ExternalProject does not forward them, and a dependency built for the wrong architecture or
# with a higher deployment target than plastimatch itself fails at link time or, worse,
# silently raises the floor of the finished package.
set(SB_COMMON_ARGS
  -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
  -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON
  -DBUILD_SHARED_LIBS:BOOL=OFF
  -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
  -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
  # Pin the library install directory. GNUInstallDirs resolves CMAKE_INSTALL_LIBDIR to
  # "lib64" on 64-bit RHEL-family systems -- which is what the manylinux images are -- and to
  # "lib" on macOS and Debian. Leaving it to the default means the dependency install trees
  # have a different shape on Linux than everywhere else, and any path this superbuild
  # computes for a specific library is then wrong on exactly one platform.
  -DCMAKE_INSTALL_LIBDIR:STRING=lib
  )

if(APPLE)
  list(APPEND SB_COMMON_ARGS
    -DCMAKE_OSX_ARCHITECTURES:STRING=${CMAKE_OSX_ARCHITECTURES}
    -DCMAKE_OSX_DEPLOYMENT_TARGET:STRING=${CMAKE_OSX_DEPLOYMENT_TARGET}
    -DCMAKE_OSX_SYSROOT:PATH=${CMAKE_OSX_SYSROOT}
    )
endif()

if(MSVC)
  # DCMTK 3.6.8 hardcodes /MT into CMAKE_CXX_FLAGS_RELEASE while ITK and plastimatch use the
  # default /MD, which the linker rejects outright ("mismatch detected for
  # 'RuntimeLibrary'"). Everything is put on the dynamic runtime; DCMTK gets a dedicated
  # option for it in External_DCMTK.cmake because overriding its CMAKE_*_FLAGS_RELEASE
  # directly does not survive its own cache logic.
  list(APPEND SB_COMMON_ARGS
    -DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreadedDLL
    )
endif()

message(STATUS "superbuild: ITK ${ITK_VERSION}, DCMTK ${DCMTK_VERSION}, "
               "zlib-ng ${ZLIBNG_VERSION}, dlib ${DLIB_VERSION}")
message(STATUS "superbuild: packaging plastimatch ${PLASTIMATCH_VERSION_LABEL} "
               "(${PLASTIMATCH_GIT_REPOSITORY}@${PLASTIMATCH_GIT_TAG})")
if(APPLE)
  message(STATUS "superbuild: macOS arch=${CMAKE_OSX_ARCHITECTURES} "
                 "deployment target=${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()

#-------------------------------------------------------------------------------------------
# Dependencies, in build order
#-------------------------------------------------------------------------------------------
include(${CMAKE_CURRENT_LIST_DIR}/External_zlib.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/External_ITK.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/External_DCMTK.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/External_dlib.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/External_plastimatch.cmake)
