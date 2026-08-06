# Copies the zlib-ng static library to a fixed path.
#
# zlib-ng names its output differently across platforms and configurations (libz.a, libz-ng.a,
# zlib.lib, zlibstatic.lib, ...), but ITK and DCMTK need an explicit ZLIB_LIBRARY path that
# the superbuild can compute at configure time, before zlib has been built. Resolving the
# real name here and copying it to a canonical one lets the dependents be configured with a
# path that is known up front.
#
# Both lib/ and lib64/ are searched. The superbuild passes CMAKE_INSTALL_LIBDIR=lib so this
# should not be necessary, but a project that ignores it would otherwise fail here with a
# confusing "not found" -- and on RHEL-family systems, which is what the manylinux images
# are, lib64 is the default that gets ignored *to*.
#
# Invoked as: cmake -DZLIB_PREFIX=... -DTARGET_PATH=... -P canonicalize_zlib.cmake

if(NOT ZLIB_PREFIX OR NOT TARGET_PATH)
  message(FATAL_ERROR "ZLIB_PREFIX and TARGET_PATH must both be set")
endif()

file(GLOB _candidates
  "${ZLIB_PREFIX}/lib/*.a"
  "${ZLIB_PREFIX}/lib/*.lib"
  "${ZLIB_PREFIX}/lib64/*.a"
  "${ZLIB_PREFIX}/lib64/*.lib"
  )
list(REMOVE_ITEM _candidates "${TARGET_PATH}")

list(LENGTH _candidates _count)
if(_count EQUAL 0)
  message(FATAL_ERROR
    "No static zlib library found under ${ZLIB_PREFIX} (searched lib/ and lib64/). "
    "zlib-ng did not install what was expected -- check that BUILD_SHARED_LIBS was OFF.")
endif()
if(_count GREATER 1)
  # More than one archive means the naming assumption has drifted, and silently picking the
  # first would be how a subtly wrong zlib gets linked into every downstream project.
  message(FATAL_ERROR
    "Expected exactly one static zlib library under ${ZLIB_PREFIX}, found ${_count}: "
    "${_candidates}")
endif()

list(GET _candidates 0 _source)
get_filename_component(_target_dir "${TARGET_PATH}" DIRECTORY)
file(MAKE_DIRECTORY "${_target_dir}")
file(COPY_FILE "${_source}" "${TARGET_PATH}" ONLY_IF_DIFFERENT)
message(STATUS "zlib: ${_source} -> ${TARGET_PATH}")
