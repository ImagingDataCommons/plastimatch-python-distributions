# DCMTK, built static against the shared zlib.
#
# CMAKE_CXX_STANDARD=17 matters: left at its default, DCMTK 3.6.8 reports "C++11 features
# disabled" and falls back to the pre-C++11 OFrvalue emulation in
# ofstd/include/dcmtk/ofstd/ofutil.h, which newer compilers reject outright (AppleClang 17:
# "no member named 'pt' in OFrvalue_storage<T, >"). plastimatch compiles those same headers
# under C++17, so the emulation has to be off here too.
#
# BUILD_APPS=OFF skips the ~30 command line tools; plastimatch only links the libraries. The
# optional backends are off to keep the static link self-contained (costs TLS and DICOM
# character-set conversion) and to keep the three platforms configured identically.
#
# DCMTK_DEFAULT_DICT=builtin compiles the DICOM data dictionary into the library. DCMTK
# defaults it to "builtin" only on Windows and to "external" on Unix, where the dictionary is
# instead loaded at run time from a file under the install prefix. That file is not part of
# the plastimatch package, so a package built with the external dictionary has no dictionary
# at all on a user's machine: DCMTK then resolves no VRs and every DICOM read fails with
# "Sorry, could not load input as any known type" -- with exit status 0 and no output file.
# The project's own tests do not catch it, because the build machine still has the file at
# the compiled-in path. Hence also the round-trip test in tests/test_executable.py.
#
# DCMTK_USE_FIND_PACKAGE=ON is required for zlib on Windows, where DCMTK otherwise globs a
# prebuilt "support libraries" directory for zlib_d.lib/zlib_o.lib and silently disables zlib
# when it is not found -- exactly what shipped in dcmqi 1.5.5, whose Windows build could not
# load deflated data. Unix already defaults it ON; forcing it keeps all three platforms on
# the same find_package(ZLIB) path.

set(DCMTK_PREFIX "${SB_INSTALL_DIR}/dcmtk")

set(_dcmtk_extra_args)
if(MSVC)
  # DCMTK hardcodes /MT into CMAKE_CXX_FLAGS_RELEASE, which collides with the /MD used by
  # ITK and plastimatch. This option is the supported way to flip it; overriding
  # CMAKE_*_FLAGS_RELEASE from the command line does not survive DCMTK's own cache logic.
  list(APPEND _dcmtk_extra_args -DDCMTK_COMPILE_WIN32_MULTITHREADED_DLL:BOOL=ON)
endif()

ExternalProject_Add(DCMTK
  URL "https://github.com/DCMTK/dcmtk/archive/refs/tags/DCMTK-${DCMTK_VERSION}.tar.gz"
  URL_HASH SHA256=${DCMTK_SHA256}
  PREFIX "${CMAKE_BINARY_DIR}/dcmtk"
  DEPENDS zlib
  CMAKE_CACHE_ARGS
    ${SB_COMMON_ARGS}
    ${_dcmtk_extra_args}
    -DCMAKE_INSTALL_PREFIX:PATH=${DCMTK_PREFIX}
    -DCMAKE_CXX_STANDARD:STRING=17
    -DDCMTK_ENABLE_CXX11:BOOL=ON
    -DBUILD_APPS:BOOL=OFF
    -DDCMTK_WITH_ZLIB:BOOL=ON
    -DDCMTK_USE_FIND_PACKAGE:BOOL=ON
    -DZLIB_ROOT:PATH=${ZLIB_PREFIX}
    -DZLIB_INCLUDE_DIR:PATH=${ZLIB_INCLUDE_DIR}
    -DZLIB_LIBRARY:FILEPATH=${ZLIB_LIBRARY}
    -DDCMTK_WITH_OPENSSL:BOOL=OFF
    -DDCMTK_WITH_PNG:BOOL=OFF
    -DDCMTK_WITH_TIFF:BOOL=OFF
    -DDCMTK_WITH_XML:BOOL=OFF
    -DDCMTK_WITH_ICONV:BOOL=OFF
    -DDCMTK_WITH_ICU:BOOL=OFF
    -DDCMTK_WITH_SNDFILE:BOOL=OFF
    -DDCMTK_DEFAULT_DICT:STRING=builtin
    -DDCMTK_ENABLE_PRIVATE_TAGS:BOOL=ON
    -DDCMTK_ENABLE_CHARSET_CONVERSION:STRING=OFF
  LOG_CONFIGURE ON
  LOG_OUTPUT_ON_FAILURE ON
  )

# find_package(ZLIB) is QUIET inside DCMTK and a miss is downgraded to a warning, so DCMTK
# will happily continue with zlib disabled -- silently costing deflate support in the shipped
# package. The configure log is checked rather than trusted.
ExternalProject_Add_Step(DCMTK check-zlib-enabled
  COMMAND ${CMAKE_COMMAND}
    -DLOG_DIR=${CMAKE_BINARY_DIR}/dcmtk/src/DCMTK-stamp
    -P ${CMAKE_CURRENT_LIST_DIR}/check_dcmtk_zlib.cmake
  DEPENDEES configure
  DEPENDERS build
  COMMENT "Checking that DCMTK enabled zlib"
  )
