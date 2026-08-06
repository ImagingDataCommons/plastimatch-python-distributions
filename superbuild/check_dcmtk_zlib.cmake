# Fails if DCMTK configured itself without zlib.
#
# DCMTK's find_package(ZLIB) is QUIET and a miss is downgraded to a warning, so the build
# succeeds and produces a library that cannot read or write Deflated Explicit VR Little
# Endian datasets. Nothing downstream notices until a user hands plastimatch a deflated
# DICOM file, so the configure log is checked here.

file(GLOB _logs "${LOG_DIR}/*configure*.log")
if(NOT _logs)
  message(FATAL_ERROR "No DCMTK configure log found in ${LOG_DIR}")
endif()

set(_enabled FALSE)
foreach(_log IN LISTS _logs)
  file(READ "${_log}" _content)
  if(_content MATCHES "DCMTK ZLIB support will be enabled")
    set(_enabled TRUE)
  endif()
endforeach()

if(NOT _enabled)
  foreach(_log IN LISTS _logs)
    file(STRINGS "${_log}" _zlib_lines REGEX "[Zz][Ll][Ii][Bb]")
    foreach(_line IN LISTS _zlib_lines)
      message(STATUS "  ${_line}")
    endforeach()
  endforeach()
  message(FATAL_ERROR
    "DCMTK did not enable zlib -- deflated DICOM would be unreadable in the shipped package.")
endif()
message(STATUS "DCMTK: zlib enabled, good")
