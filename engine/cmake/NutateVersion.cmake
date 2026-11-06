# Shared calendar-version contract for all engine builds.
function(nutate_read_version version_file output_variable)
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${version_file}")
  # Validate raw ASCII bytes: CMake text reads normalize line endings. Permit
  # YYYY.X with no newline, one LF, or one CRLF; reject all other whitespace.
  file(READ "${version_file}" version_hex HEX)
  if(NOT version_hex MATCHES "^3[1-9]3[0-9]3[0-9]3[0-9]2e(30|3[1-9](3[0-9])*)(0a|0d0a)?$")
    message(FATAL_ERROR
      "VERSION must contain exactly YYYY.X (for example 2026.0), with no v prefix, suffix, whitespace, or leading zeros in X")
  endif()
  file(READ "${version_file}" version_text)
  string(STRIP "${version_text}" version_text)
  set(${output_variable} "${version_text}" PARENT_SCOPE)
endfunction()
