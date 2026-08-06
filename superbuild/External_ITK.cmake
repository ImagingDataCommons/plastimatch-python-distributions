# ITK, built static against the shared zlib.
#
# Module_ITKReview is on because plastimatch uses filters from it. Testing and examples are
# off: they roughly double the build time and nothing in the package links them.

set(ITK_PREFIX "${SB_INSTALL_DIR}/itk")

ExternalProject_Add(ITK
  URL "https://github.com/InsightSoftwareConsortium/ITK/releases/download/v${ITK_VERSION}/InsightToolkit-${ITK_VERSION}.tar.gz"
  URL_HASH SHA256=${ITK_SHA256}
  PREFIX "${CMAKE_BINARY_DIR}/itk"
  DEPENDS zlib
  CMAKE_CACHE_ARGS
    ${SB_COMMON_ARGS}
    -DCMAKE_INSTALL_PREFIX:PATH=${ITK_PREFIX}
    -DBUILD_TESTING:BOOL=OFF
    -DBUILD_EXAMPLES:BOOL=OFF
    -DModule_ITKReview:BOOL=ON
    -DITK_USE_SYSTEM_ZLIB:BOOL=ON
    -DZLIB_ROOT:PATH=${ZLIB_PREFIX}
    -DZLIB_INCLUDE_DIR:PATH=${ZLIB_INCLUDE_DIR}
    -DZLIB_LIBRARY:FILEPATH=${ZLIB_LIBRARY}
  )

# Guard the regression that cost a full CI round: if ITK ever builds its own zlib again, its
# internals (deflateInit2, inflateInit2, ...) collide with the shared copy at link time.
# Catch it here, next to the cause, rather than in a link error much later.
ExternalProject_Add_Step(ITK check-no-bundled-zlib
  COMMAND ${CMAKE_COMMAND}
    -DITK_LIB_DIR=${ITK_PREFIX}/lib
    -P ${CMAKE_CURRENT_LIST_DIR}/check_itk_zlib.cmake
  DEPENDEES install
  COMMENT "Checking that ITK did not build its own zlib"
  )
