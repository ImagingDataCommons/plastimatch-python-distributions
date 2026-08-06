# Fails if ITK installed its own bundled zlib despite ITK_USE_SYSTEM_ZLIB=ON.
#
# Two zlibs in one executable do not coexist: zlib-ng's ZLIB_SYMBOL_PREFIX renames only the
# documented public API, so ~85 internal symbols -- deflateInit2, inflateInit2 and friends --
# stay unprefixed and collide at link time. The resulting error names a plastimatch object
# file and gives no hint that ITK is the cause, so check here instead.

file(GLOB _bundled "${ITK_LIB_DIR}/libitkzlib*" "${ITK_LIB_DIR}/itkzlib*")
if(_bundled)
  message(FATAL_ERROR
    "ITK built its own zlib despite ITK_USE_SYSTEM_ZLIB=ON: ${_bundled}\n"
    "It will collide with the shared zlib at link time. Check that ZLIB_LIBRARY pointed at "
    "a real file when ITK was configured.")
endif()
message(STATUS "ITK: no bundled zlib, good")
