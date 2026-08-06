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
    -DCMAKE_PREFIX_PATH:STRING=${ZLIB_PREFIX}|${ITK_PREFIX}|${DCMTK_PREFIX}|${DLIB_PREFIX}
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG:BOOL=ON
    -DCMAKE_CXX_STANDARD:STRING=17
    -Ddlib_INCLUDE_DIR:PATH=${DLIB_PREFIX}/include
    -DPLM_SYSTEM_ITK:BOOL=ON
    -DPLM_SYSTEM_DCMTK:BOOL=ON
    -DPLM_PREFER_SYSTEM_DLIB:BOOL=ON
    -DPLM_CONFIG_ENABLE_CUDA:BOOL=OFF
    -DPLM_CONFIG_ENABLE_OPENCL:BOOL=OFF
    -DPLM_CONFIG_ENABLE_QT:BOOL=OFF
    -DPLM_CONFIG_ENABLE_OPENMP:BOOL=ON
    -DPLM_CONFIG_ENABLE_SSE2:BOOL=ON
    -DPLM_BUILD_TESTING:BOOL=ON
  # No install step: the workflow runs ctest and cpack against this build tree, and
  # plastimatch's CPack configuration is what produces the package layout the wheels expect.
  INSTALL_COMMAND ""
  )
