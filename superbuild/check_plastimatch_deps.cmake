# Fails unless plastimatch resolved ITK, DCMTK and dlib to the copies this superbuild built.
#
# Reads plastimatch's own CMakeCache.txt rather than trusting the arguments that were passed
# in, because the bug this exists to catch was precisely an argument that was passed in and
# then ignored: PLM_SYSTEM_ITK/PLM_SYSTEM_DCMTK are tri-state string enums, a BOOL=ON landed in
# the cache as the string "ON", neither branch matched, and plastimatch quietly built its own
# ITK and DCMTK instead. The cache is what plastimatch actually decided, so that is what gets
# asserted.
#
# Two independent things are checked, because either alone can pass while the build is wrong:
#
#   1. The enum values are literally "YES". This catches a value that did not land, which is
#      the original failure, and it catches it even on a machine where a system ITK happens to
#      exist and would satisfy check 2 on its own.
#   2. Each *_DIR points inside this superbuild's install prefix. This catches resolution to a
#      system or Homebrew copy, which is what PLM_PREFER_SYSTEM_DLIB's find_package(dlib QUIET)
#      would do silently, and it is the check that keeps working if upstream ever renames or
#      restructures the enums.

foreach(_required PLM_BINARY_DIR ITK_PREFIX DCMTK_PREFIX DLIB_PREFIX)
  if(NOT ${_required})
    message(FATAL_ERROR "${_required} must be set")
  endif()
endforeach()

set(_cache "${PLM_BINARY_DIR}/CMakeCache.txt")
if(NOT EXISTS "${_cache}")
  message(FATAL_ERROR "No CMakeCache.txt at ${_cache} -- did plastimatch configure?")
endif()
file(READ "${_cache}" _cache_text)

# Normalises separators and, on Windows, case: CMake writes forward slashes into the cache but
# the prefixes are interpolated from this build's own variables, and a drive letter can differ
# in case between the two.
function(_normalise _path _out)
  file(TO_CMAKE_PATH "${_path}" _p)
  string(REGEX REPLACE "/+$" "" _p "${_p}")
  if(WIN32)
    string(TOLOWER "${_p}" _p)
  endif()
  set(${_out} "${_p}" PARENT_SCOPE)
endfunction()

# Any type: ITK_DIR is PATH, dlib_DIR is PATH, but an -D on the command line can land as
# UNINITIALIZED, and matching the type would make this check silently vacuous again.
function(_cache_get _var _out)
  if(_cache_text MATCHES "(^|\n)${_var}:[^=\n]*=([^\n]*)")
    set(${_out} "${CMAKE_MATCH_2}" PARENT_SCOPE)
  else()
    set(${_out} "" PARENT_SCOPE)
  endif()
endfunction()

# Accumulated with string(APPEND), not list(APPEND): the messages contain semicolons, and a
# list would either split on them or lose them when joined.
set(_errors "")

# --- 1. the enum values landed -----------------------------------------------------------
foreach(_enum PLM_SYSTEM_ITK PLM_SYSTEM_DCMTK)
  _cache_get("${_enum}" _value)
  if(NOT _value STREQUAL "YES")
    string(APPEND _errors
      "${_enum} is \"${_value}\", expected \"YES\". It is a string enum over "
      "{NO, PREFERRED, YES}; anything else makes plastimatch skip find_package "
      "and build its own copy.\n\n")
  endif()
endforeach()

# --- 2. the dependencies resolved into this superbuild -----------------------------------
foreach(_dep "ITK_DIR;${ITK_PREFIX};ITK" "DCMTK_DIR;${DCMTK_PREFIX};DCMTK" "dlib_DIR;${DLIB_PREFIX};dlib")
  list(GET _dep 0 _var)
  list(GET _dep 1 _prefix)
  list(GET _dep 2 _name)

  _cache_get("${_var}" _value)
  if(NOT _value)
    string(APPEND _errors
      "${_var} is unset in ${_cache}, so plastimatch did not find ${_name} through "
      "CMAKE_PREFIX_PATH.\n\n")
  else()
    _normalise("${_value}" _got)
    _normalise("${_prefix}" _want)
    # The trailing slash matters: without it a sibling prefix such as .../deps/itk-other
    # passes as a prefix match of .../deps/itk.
    string(FIND "${_got}" "${_want}/" _at)
    if(NOT _at EQUAL 0)
      string(APPEND _errors
        "${_var} is \"${_value}\", which is outside this superbuild's ${_name} at "
        "\"${_prefix}\". plastimatch is building against a copy of ${_name} that was not built "
        "here, so none of the settings this package depends on are guaranteed.\n\n")
    else()
      message(STATUS "plastimatch: ${_name} -> ${_value}")
    endif()
  endif()
endforeach()

if(_errors)
  message(FATAL_ERROR
    "plastimatch did not use this superbuild's dependencies:\n\n${_errors}")
endif()

message(STATUS "plastimatch: dependencies resolved to the superbuild, good")
