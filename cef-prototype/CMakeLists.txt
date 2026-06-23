# komo swiftcef — minimal Swift + CEF de-risk (macOS only).
# Based on CEF's cefsimple CMakeLists (BSD-style license).

enable_language(Swift)

# Main app sources: CEF C++/Obj-C++ + the Swift UI layer.
set(SWIFTCEF_SRCS
  simple_app.cc
  simple_app.h
  simple_handler.cc
  simple_handler.h
  cefsimple_mac.mm
  simple_handler_mac.mm
  main.swift
  )
source_group(swiftcef FILES ${SWIFTCEF_SRCS})

# Helper (subprocess) executable sources.
set(SWIFTCEF_HELPER_SRCS
  process_helper_mac.cc
  )

# Bundle resources.
set(SWIFTCEF_RESOURCES_SRCS
  mac/Info.plist.in
  mac/cefsimple.icns
  mac/English.lproj/InfoPlist.strings
  mac/English.lproj/MainMenu.xib
  )

set(CEF_TARGET "swiftcef")
set(CEF_HELPER_TARGET "swiftcef_Helper")
set(CEF_HELPER_OUTPUT_NAME "swiftcef Helper")

SET_CEF_TARGET_OUT_DIR()

list(APPEND CEF_COMPILER_FLAGS -fobjc-arc)

set(CEF_APP "${CEF_TARGET_OUT_DIR}/${CEF_TARGET}.app")
set(EXECUTABLE_NAME "${CEF_TARGET}")
set(PRODUCT_NAME "${CEF_TARGET}")

# Main app bundle target.
add_executable(${CEF_TARGET} MACOSX_BUNDLE ${SWIFTCEF_RESOURCES_SRCS} ${SWIFTCEF_SRCS})
SET_EXECUTABLE_TARGET_PROPERTIES(${CEF_TARGET})
add_dependencies(${CEF_TARGET} libcef_dll_wrapper)
target_link_libraries(${CEF_TARGET} libcef_dll_wrapper ${CEF_STANDARD_LIBS})
set_target_properties(${CEF_TARGET} PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/mac/Info.plist.in
  # Let the Swift driver perform the final link so the Swift runtime is pulled in.
  LINKER_LANGUAGE Swift
  )

# CEF sets exe link flags in `-Wl,` form (for clang++); swiftc (our linker for
# this target) only understands the `-Xlinker` form. Convert them.
foreach(_prop LINK_FLAGS LINK_FLAGS_RELEASE LINK_FLAGS_DEBUG)
  get_target_property(_val ${CEF_TARGET} ${_prop})
  if(_val)
    string(REPLACE "-Wl," "-Xlinker " _val "${_val}")
    set_target_properties(${CEF_TARGET} PROPERTIES ${_prop} "${_val}")
  endif()
endforeach()

# Compile the Swift file as a library so swiftc doesn't synthesize its own
# main() — CEF's main() (in cefsimple_mac.mm) is the real entry point.
target_compile_options(${CEF_TARGET} PRIVATE $<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>)

# Copy the CEF framework into Contents/Frameworks (+ symlinks).
COPY_MAC_FRAMEWORK("${CEF_TARGET}" "${CEF_BINARY_DIR}" "${CEF_APP}")

# Build the helper app variants (Renderer/GPU/Plugin/Alerts) and nest them.
foreach(_suffix_list ${CEF_HELPER_APP_SUFFIXES})
  string(REPLACE ":" ";" _suffix_list ${_suffix_list})
  list(GET _suffix_list 0 _name_suffix)
  list(GET _suffix_list 1 _target_suffix)
  list(GET _suffix_list 2 _plist_suffix)

  set(_helper_target "${CEF_HELPER_TARGET}${_target_suffix}")
  set(_helper_output_name "${CEF_HELPER_OUTPUT_NAME}${_name_suffix}")

  set(_helper_info_plist "${CMAKE_CURRENT_BINARY_DIR}/helper-Info${_target_suffix}.plist")
  file(READ "${CMAKE_CURRENT_SOURCE_DIR}/mac/helper-Info.plist.in" _plist_contents)
  string(REPLACE "\${EXECUTABLE_NAME}" "${_helper_output_name}" _plist_contents ${_plist_contents})
  string(REPLACE "\${PRODUCT_NAME}" "${_helper_output_name}" _plist_contents ${_plist_contents})
  string(REPLACE "\${BUNDLE_ID_SUFFIX}" "${_plist_suffix}" _plist_contents ${_plist_contents})
  file(WRITE ${_helper_info_plist} ${_plist_contents})

  add_executable(${_helper_target} MACOSX_BUNDLE ${SWIFTCEF_HELPER_SRCS})
  SET_EXECUTABLE_TARGET_PROPERTIES(${_helper_target})
  add_dependencies(${_helper_target} libcef_dll_wrapper)
  target_link_libraries(${_helper_target} libcef_dll_wrapper ${CEF_STANDARD_LIBS})
  set_target_properties(${_helper_target} PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${_helper_info_plist}
    OUTPUT_NAME ${_helper_output_name}
    )
  add_dependencies(${CEF_TARGET} "${_helper_target}")

  add_custom_command(
    TARGET ${CEF_TARGET}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CEF_TARGET_OUT_DIR}/${_helper_output_name}.app"
            "${CEF_APP}/Contents/Frameworks/${_helper_output_name}.app"
    VERBATIM
    )
endforeach()

set(PREFIXES "mac/")
COPY_MAC_RESOURCES("${SWIFTCEF_RESOURCES_SRCS}" "${PREFIXES}" "${CEF_TARGET}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CEF_APP}")
