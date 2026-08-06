# Fails if ITK installed its own bundled zlib despite ITK_USE_SYSTEM_ZLIB=ON.
#
# Two zlibs in one executable do not coexist: zlib-ng's ZLIB_SYMBOL_PREFIX renames only the
# documented public API, so ~85 internal symbols -- deflateInit2, inflateInit2 and friends --
# stay unprefixed and collide at link time. The resulting error names a plastimatch object
# file and gives no hint that ITK is the cause, so check here instead.

if(NOT ITK_PREFIX)
  message(FATAL_ERROR "ITK_PREFIX must be set")
endif()

# lib/ and lib64/ are both searched: this check silently passes -- the worst outcome for a
# guard -- if it looks in a directory the libraries were never installed to.
file(GLOB _bundled
  "${ITK_PREFIX}/lib/libitkzlib*" "${ITK_PREFIX}/lib/itkzlib*"
  "${ITK_PREFIX}/lib64/libitkzlib*" "${ITK_PREFIX}/lib64/itkzlib*")
if(_bundled)
  message(FATAL_ERROR
    "ITK built its own zlib despite ITK_USE_SYSTEM_ZLIB=ON: ${_bundled}\n"
    "It will collide with the shared zlib at link time. Check that ZLIB_LIBRARY pointed at "
    "a real file when ITK was configured.")
endif()
message(STATUS "ITK: no bundled zlib, good")
