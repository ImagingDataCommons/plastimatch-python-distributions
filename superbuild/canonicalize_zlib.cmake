# Copies the zlib-ng static library to a fixed filename.
#
# zlib-ng names its output differently across platforms and configurations (libz.a, libz-ng.a,
# zlib.lib, zlibstatic.lib, ...), but ITK and DCMTK need an explicit ZLIB_LIBRARY path that
# the superbuild can compute at configure time, before zlib has been built. Resolving the
# real name here and copying it to a canonical one lets the dependents be configured with a
# path that is known up front.
#
# Invoked as: cmake -DZLIB_LIB_DIR=... -DOUTPUT_NAME=... -P canonicalize_zlib.cmake

if(NOT ZLIB_LIB_DIR OR NOT OUTPUT_NAME)
  message(FATAL_ERROR "ZLIB_LIB_DIR and OUTPUT_NAME must both be set")
endif()

set(_target "${ZLIB_LIB_DIR}/${OUTPUT_NAME}")

file(GLOB _candidates "${ZLIB_LIB_DIR}/*.a" "${ZLIB_LIB_DIR}/*.lib")
list(REMOVE_ITEM _candidates "${_target}")

list(LENGTH _candidates _count)
if(_count EQUAL 0)
  message(FATAL_ERROR
    "No static zlib library found in ${ZLIB_LIB_DIR}. zlib-ng did not install what was "
    "expected -- check that BUILD_SHARED_LIBS was OFF.")
endif()
if(_count GREATER 1)
  # More than one archive means the naming assumption has drifted, and silently picking the
  # first would be how a subtly wrong zlib gets linked into every downstream project.
  message(FATAL_ERROR
    "Expected exactly one static zlib library in ${ZLIB_LIB_DIR}, found ${_count}: "
    "${_candidates}")
endif()

list(GET _candidates 0 _source)
file(COPY_FILE "${_source}" "${_target}" ONLY_IF_DIFFERENT)
message(STATUS "zlib: ${_source} -> ${_target}")
