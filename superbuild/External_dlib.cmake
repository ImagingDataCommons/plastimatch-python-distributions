# dlib, minimal build.
#
# plastimatch only uses the optimization, threading, svm and command line parser headers, so
# the GUI and BLAS backends are off to keep the static link self-contained.
#
# PNG and JPEG support must stay ON even though plastimatch never loads images.
# dlib/image_io.h -- reached via dlib/data_io.h -- unconditionally includes png_loader.h and
# jpeg_loader.h, and with support off both spell their guard as
# COMPILE_TIME_ASSERT(sizeof(T) == 0). T is an undeclared, non-dependent name, so that is a
# hard parse-time error rather than one deferred to instantiation.
#
# PNG_FOUND=0/JPEG_FOUND=0 take the deliberate early-out in dlib's
# cmake_utils/find_lib{png,jpeg}.cmake ("if (DEFINED ..._FOUND) return()"), which makes dlib
# statically compile its own bundled libpng/zlib/libjpeg into libdlib.a instead of linking
# the system copies -- so the package stays self-contained.

set(DLIB_PREFIX "${SB_INSTALL_DIR}/dlib")

set(_dlib_extra_args)
if(APPLE)
  # dlib's vendored libpng calls isnan()/isinf() without including math.h, which AppleClang
  # rejects. Forcing the include is what makes the vendored copy compile on macOS. The
  # fdopen define works around dlib's vendored libjpeg redefining it.
  list(APPEND _dlib_extra_args
    "-DCMAKE_C_FLAGS:STRING=-include math.h -Dfdopen=fdopen")
endif()

ExternalProject_Add(dlib
  URL "https://github.com/davisking/dlib/archive/refs/tags/v${DLIB_VERSION}.tar.gz"
  URL_HASH SHA256=${DLIB_SHA256}
  PREFIX "${CMAKE_BINARY_DIR}/dlib"
  CMAKE_CACHE_ARGS
    ${SB_COMMON_ARGS}
    ${_dlib_extra_args}
    -DCMAKE_INSTALL_PREFIX:PATH=${DLIB_PREFIX}
    -DCMAKE_CXX_STANDARD:STRING=17
    -DDLIB_NO_GUI_SUPPORT:BOOL=ON
    -DDLIB_PNG_SUPPORT:BOOL=ON
    -DPNG_FOUND:BOOL=0
    -DDLIB_JPEG_SUPPORT:BOOL=ON
    -DJPEG_FOUND:BOOL=0
    -DDLIB_GIF_SUPPORT:BOOL=OFF
    -DDLIB_WEBP_SUPPORT:BOOL=OFF
    -DDLIB_USE_BLAS:BOOL=OFF
    -DDLIB_USE_LAPACK:BOOL=OFF
    -DDLIB_USE_CUDA:BOOL=OFF
    -DDLIB_USE_MKL_FFT:BOOL=OFF
    -DDLIB_LINK_WITH_SQLITE3:BOOL=OFF
  )
