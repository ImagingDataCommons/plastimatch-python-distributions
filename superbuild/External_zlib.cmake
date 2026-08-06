# zlib-ng in ZLIB_COMPAT mode, providing the classic zlib API that DCMTK expects.
#
# One zlib is shared by ITK and DCMTK, which is mandatory rather than tidy. ITK 5.4 bundles
# zlib-ng too, and a second copy in the same executable collides: ZLIB_SYMBOL_PREFIX renames
# only the documented public API, leaving ~85 internal symbols unprefixed -- including
# deflateInit2 and inflateInit2, which is exactly what the linker rejects ("multiple
# definition of `deflateInit2'; libitkzlib-5.4.a"). So ITK is pointed at this zlib with
# ITK_USE_SYSTEM_ZLIB=ON and never builds its own. dcmqi shares a single zlib across ITK and
# DCMTK for the same reason. The prefix is kept so this copy cannot clash with any system
# zlib pulled in transitively.

set(ZLIB_PREFIX "${SB_INSTALL_DIR}/zlib")

# zlib-ng's static library filename varies by platform and configuration, and ExternalProject
# needs a path that is known at configure time to hand to ITK and DCMTK. Rather than glob at
# build time -- which the hand-rolled workflows had to do -- copy the built archive to a
# canonical name as a post-install step.
if(MSVC)
  set(ZLIB_CANONICAL_NAME "plmzlib.lib")
else()
  set(ZLIB_CANONICAL_NAME "libplmzlib.a")
endif()
set(ZLIB_LIBRARY "${ZLIB_PREFIX}/lib/${ZLIB_CANONICAL_NAME}")
set(ZLIB_INCLUDE_DIR "${ZLIB_PREFIX}/include")

ExternalProject_Add(zlib
  URL "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${ZLIBNG_VERSION}.tar.gz"
  URL_HASH SHA256=${ZLIBNG_SHA256}
  PREFIX "${CMAKE_BINARY_DIR}/zlib"
  CMAKE_CACHE_ARGS
    ${SB_COMMON_ARGS}
    -DCMAKE_INSTALL_PREFIX:PATH=${ZLIB_PREFIX}
    -DZLIB_COMPAT:BOOL=ON
    -DZLIB_SYMBOL_PREFIX:STRING=plm_zlib_
    -DZLIB_ENABLE_TESTS:BOOL=OFF
    -DWITH_GTEST:BOOL=OFF
  )

ExternalProject_Add_Step(zlib canonicalize
  COMMAND ${CMAKE_COMMAND}
    -DZLIB_PREFIX=${ZLIB_PREFIX}
    -DTARGET_PATH=${ZLIB_LIBRARY}
    -P ${CMAKE_CURRENT_LIST_DIR}/canonicalize_zlib.cmake
  DEPENDEES install
  COMMENT "Copying the zlib static library to a canonical name"
  )
