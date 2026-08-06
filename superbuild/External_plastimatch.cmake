# plastimatch itself, built against the dependencies above.
#
# The dependencies are found through CMAKE_PREFIX_PATH rather than by passing ITK_DIR,
# DCMTK_DIR and dlib_DIR explicitly. Those paths contain version-dependent subdirectories
# (lib/cmake/ITK-5.4, ...) that would otherwise have to be globbed at build time, which is
# what forced the hand-rolled workflows into a shell step here.
#
# CMAKE_FIND_PACKAGE_PREFER_CONFIG=ON is required for dlib. On a case-insensitive filesystem
# (macOS), find_package(dlib) looking for "Finddlib.cmake" in MODULE mode matches
# plastimatch's own cmake/FindDlib.cmake, a legacy module that searches for a system dlib,
# fails, and prevents CONFIG mode from ever running -- so dlib_DIR was ignored as an unused
# variable and the bundled libs/dlib-19.1 got compiled instead. Preferring CONFIG picks up
# dlibConfig.cmake and makes all platforms resolve dependencies the same way; packages
# without a config file still fall back to MODULE.
#
# dlib_INCLUDE_DIR is passed explicitly because plastimatch's src/CMakeLists.txt copies it
# into DLIB_INCLUDE_DIR, which src/clp consumes as a plain include path rather than through
# the dlib::dlib target.
#
# The optional accelerators (FFTW, nlopt, libyaml, Octave, wxWidgets, Qt, CUDA, OpenCL) are
# left out so all platforms produce a feature-identical package.

set(PLASTIMATCH_BINARY_DIR "${CMAKE_BINARY_DIR}/plastimatch-build")

# SSE2 is enabled per *target* architecture, not host. plastimatch's cmake/FindSSE.cmake probes
# the build machine's CPU, and its Darwin branch shells out to
# `sysctl -n machdep.cpu.features`, a MIB that does not exist on Apple Silicon. The output is
# then interpolated unquoted into STRING(REGEX REPLACE ... ${CPUINFO}), so on arm64 the empty
# result collapses the argument list and configure dies with "STRING sub-command REGEX, mode
# REPLACE needs at least 6 arguments total".
#
# Turning it off everywhere would be simpler but is not free: SSE2_FOUND is exported through
# src/sys/plm_config.h.in as a preprocessor definition, and the #if (SSE2_FOUND) blocks it
# gates are the vectorised B-spline registration paths in bspline.cxx, bspline_mi.cxx,
# bspline_mse.cxx and bspline_warp.cxx -- the hot loops of the main use case. So keep it on
# wherever it means something and off where it cannot.
#
# Detecting on the host and baking the result into a redistributable binary is safe here only
# because SSE2 is part of the x86-64 ABI, so every machine that can run the package has it.
if(APPLE AND CMAKE_OSX_ARCHITECTURES)
  set(_plm_target_arch "${CMAKE_OSX_ARCHITECTURES}")
else()
  set(_plm_target_arch "${CMAKE_SYSTEM_PROCESSOR}")
endif()
if(_plm_target_arch MATCHES "^([xX]86_64|[aA][mM][dD]64|i[3-6]86)$")
  set(_plm_enable_sse2 ON)
else()
  set(_plm_enable_sse2 OFF)
endif()
message(STATUS "plastimatch: target arch ${_plm_target_arch}, SSE2 ${_plm_enable_sse2}")

set(_plm_extra_args)
if(MSVC)
  # MSVC reports __cplusplus as 199711L unless told otherwise, which makes plastimatch's
  # C++17 feature detection take the wrong branch. CMake appends a command line
  # CMAKE_CXX_FLAGS to the platform defaults, so this does not clobber them.
  list(APPEND _plm_extra_args "-DCMAKE_CXX_FLAGS:STRING=/Zc:__cplusplus")
endif()

ExternalProject_Add(plastimatch
  GIT_REPOSITORY "${PLASTIMATCH_GIT_REPOSITORY}"
  GIT_TAG "${PLASTIMATCH_GIT_TAG}"
  # Not shallow: plastimatch's CMakeLists.txt runs `git describe` to compute
  # PLASTIMATCH_VERSION_STRING and PLM_VERSION_TWEAK, and a shallow clone has no tags to
  # describe against, which silently produces a package labelled with a bare commit hash.
  GIT_SHALLOW OFF
  PREFIX "${CMAKE_BINARY_DIR}/plastimatch"
  BINARY_DIR "${PLASTIMATCH_BINARY_DIR}"
  DEPENDS zlib ITK DCMTK dlib
  LIST_SEPARATOR |
  CMAKE_CACHE_ARGS
    ${SB_COMMON_ARGS}
    ${_plm_extra_args}
    # plastimatch 1.10.0 opens with cmake_minimum_required(VERSION 3.1.3), and CMake 4 removed
    # compatibility below 3.5 -- so the released tag cannot be configured by a current CMake
    # at all. This is CMake's documented escape hatch for exactly that situation, and it is
    # needed here because upstream's released source is not ours to patch. Note that
    # plastimatch's own master has since raised the minimum to 3.7, which is why the CI on a
    # fork tracking master never hit this.
    -DCMAKE_POLICY_VERSION_MINIMUM:STRING=3.5
    -DCMAKE_PREFIX_PATH:STRING=${ZLIB_PREFIX}|${ITK_PREFIX}|${DCMTK_PREFIX}|${DLIB_PREFIX}
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG:BOOL=ON
    -DCMAKE_CXX_STANDARD:STRING=17
    -Ddlib_INCLUDE_DIR:PATH=${DLIB_PREFIX}/include
    # STRING, not BOOL, and "YES", not "ON". These two are declared with sb_option_enum, which
    # is option_enum -> set(... CACHE STRING ...) over the value set {NO, PREFERRED, YES}, and
    # CMake will not overwrite a cache entry this superbuild has already seeded. Passing
    # BOOL=ON therefore pinned the value at the string "ON", which matches neither branch of
    #
    #   if (PLM_SYSTEM_ITK STREQUAL "YES")        find_package (ITK REQUIRED)
    #   elseif (PLM_SYSTEM_ITK STREQUAL "PREFERRED") find_package (ITK QUIET)
    #   if (NOT ITK_FOUND AND NOT PLM_SYSTEM_ITK STREQUAL "YES")  <nested superbuild>
    #
    # so find_package never ran, ITK_FOUND stayed false, and plastimatch fell through to its
    # own in-tree superbuild -- downloading and building an ITK and a DCMTK of its own choosing
    # and ignoring everything this project had just built. There was no error: the fallback is
    # the documented behaviour for an unrecognised value.
    #
    # YES rather than PREFERRED is deliberate. PREFERRED keeps that fallback reachable, so a
    # dependency this superbuild failed to expose would be silently replaced by DCMTK 3.6.2
    # fetched over FTP from the retired dicom.offis.de -- built with none of the settings the
    # package depends on, including the builtin dictionary. YES makes both find_package calls
    # REQUIRED and makes the fallback branch unreachable by construction, so a resolution
    # failure is a build failure.
    -DPLM_SYSTEM_ITK:STRING=YES
    -DPLM_SYSTEM_DCMTK:STRING=YES
    # Plain sb_option booleans, unlike the two above -- verified against the pinned revision.
    -DPLM_PREFER_SYSTEM_DLIB:BOOL=ON
    -DPLM_CONFIG_ENABLE_CUDA:BOOL=OFF
    -DPLM_CONFIG_ENABLE_OPENCL:BOOL=OFF
    -DPLM_CONFIG_ENABLE_QT:BOOL=OFF
    -DPLM_CONFIG_ENABLE_OPENMP:BOOL=ON
    -DPLM_CONFIG_ENABLE_SSE2:BOOL=${_plm_enable_sse2}
    -DPLM_BUILD_TESTING:BOOL=ON
  # No install step: the workflow runs ctest and cpack against this build tree, and
  # plastimatch's CPack configuration is what produces the package layout the wheels expect.
  INSTALL_COMMAND ""
  )

# The guard for the class of bug that made this file wrong for four CI rounds: plastimatch
# resolving a dependency to something other than what this superbuild built, and saying so only
# in a STATUS line in the middle of several thousand lines of configure output. Every fallback
# involved here is quiet by design -- find_package(dlib QUIET), and an unrecognised
# PLM_SYSTEM_ITK value falling through to the in-tree superbuild -- so nothing downstream fails.
# The build goes green and ships a package built against the wrong ITK, the wrong DCMTK, or the
# C++17-incompatible bundled dlib.
#
# Checked right after configure, before anything is compiled against the wrong headers.
ExternalProject_Add_Step(plastimatch check-deps
  COMMAND ${CMAKE_COMMAND}
    -DPLM_BINARY_DIR=${PLASTIMATCH_BINARY_DIR}
    -DITK_PREFIX=${ITK_PREFIX}
    -DDCMTK_PREFIX=${DCMTK_PREFIX}
    -DDLIB_PREFIX=${DLIB_PREFIX}
    -P ${CMAKE_CURRENT_LIST_DIR}/check_plastimatch_deps.cmake
  DEPENDEES configure
  DEPENDERS build
  COMMENT "Checking that plastimatch resolved the superbuild's dependencies"
  )
