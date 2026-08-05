# Wheel layer: download a prebuilt plastimatch archive and install its executables into
# the Python package. No compiling happens here -- see .github/workflows/build-binaries.yml
# for the layer that produces the archives.
#
# Structured after the dcmqi and s5cmd python distributions:
# https://github.com/ImagingDataCommons/dcmqi-python-distributions/blob/main/CMakeLists.txt

cmake_minimum_required(VERSION 3.15...3.26)
project(${SKBUILD_PROJECT_NAME} LANGUAGES NONE)

# Sets in the current scope:
# - plastimatch_archive_url
# - plastimatch_archive_sha256
# - plastimatch_archive_filename
# - plastimatch_version
include(${CMAKE_CURRENT_SOURCE_DIR}/plastimatchUrls.cmake)

message(STATUS "plastimatch archive: ${plastimatch_archive_filename}")
message(STATUS "plastimatch archive url: ${plastimatch_archive_url}")

#
# Download & extract archive
#
# The plastimatch archives contain a single top-level directory whose name varies by
# platform (plastimatch-1.10.0-Linux, -Darwin, -win64). CMake strips a lone top-level
# directory during extraction, so bin/ lands directly in extract_dir on all three and the
# install rules below need no per-platform pathing.
#
set(download_dir "${PROJECT_BINARY_DIR}")
set(extract_dir "${PROJECT_BINARY_DIR}/plastimatch-binary-distribution")
include(FetchContent)
FetchContent_Populate(plastimatch
  URL ${plastimatch_archive_url}
  URL_HASH SHA256=${plastimatch_archive_sha256}
  DOWNLOAD_DIR ${download_dir}
  SOURCE_DIR "${extract_dir}"
  )

#
# Install executables
#

set(_permissions PERMISSIONS
  OWNER_READ OWNER_WRITE OWNER_EXECUTE
  GROUP_READ GROUP_EXECUTE
  WORLD_READ WORLD_EXECUTE
  )

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/binaries.txt" _plastimatch_binaries)

# Fail at configure time with a useful message rather than at install time with a bare
# "file INSTALL cannot find". A missing executable here means the archive layout changed or
# the build that produced it dropped a target, and that is worth surfacing loudly.
foreach(_binary IN LISTS _plastimatch_binaries)
  set(_path "${extract_dir}/bin/${_binary}${CMAKE_EXECUTABLE_SUFFIX}")
  if(NOT EXISTS "${_path}")
    message(FATAL_ERROR
      "Executable '${_binary}${CMAKE_EXECUTABLE_SUFFIX}' listed in binaries.txt is not "
      "present in ${plastimatch_archive_filename} (looked for ${_path}).")
  endif()
  install(PROGRAMS "${_path}" DESTINATION "plastimatch/bin" ${_permissions})
endforeach()

# On Windows the packaged executables are linked against the dynamic MSVC runtime, and the
# archive ships the redistributable DLLs alongside them. They have to travel into the wheel
# in the same directory as the .exe files or nothing runs on a machine without the
# Visual C++ redistributable installed.
if(WIN32)
  file(GLOB _runtime_dlls "${extract_dir}/bin/*.dll")
  if(_runtime_dlls)
    message(STATUS "Bundling Windows runtime DLLs:")
    foreach(_dll IN LISTS _runtime_dlls)
      get_filename_component(_dll_name "${_dll}" NAME)
      message(STATUS "  ${_dll_name}")
    endforeach()
    install(PROGRAMS ${_runtime_dlls} DESTINATION "plastimatch/bin" ${_permissions})
  else()
    message(WARNING
      "No runtime DLLs found next to the Windows executables. This is only correct if the "
      "binaries were linked against the static MSVC runtime.")
  endif()
endif()

#
# Install upstream license and copyright
#
# The wheel ships a statically linked plastimatch, so it carries plastimatch's own BSD-style
# license plus the licenses of ITK, DCMTK, dlib and zlib-ng linked into it. plastimatch's
# LICENSE.TXT lives at share/doc/plastimatch/ on Unix and doc/ on Windows, hence the glob.
file(GLOB_RECURSE _license_files
  "${extract_dir}/LICENSE.TXT"
  "${extract_dir}/doc/LICENSE.TXT"
  "${extract_dir}/doc/COPYRIGHT.TXT"
  "${extract_dir}/share/doc/plastimatch/LICENSE.TXT"
  "${extract_dir}/share/doc/plastimatch/COPYRIGHT.TXT"
  )
if(_license_files)
  install(FILES ${_license_files} DESTINATION "plastimatch/share/licenses")
else()
  message(WARNING "No upstream license files found in ${plastimatch_archive_filename}.")
endif()
