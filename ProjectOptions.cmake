include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(torrentinfo_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(torrentinfo_setup_options)
  option(torrentinfo_ENABLE_HARDENING "Enable hardening" ON)
  option(torrentinfo_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    torrentinfo_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    torrentinfo_ENABLE_HARDENING
    OFF)

  torrentinfo_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR torrentinfo_PACKAGING_MAINTAINER_MODE)
    option(torrentinfo_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(torrentinfo_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(torrentinfo_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(torrentinfo_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(torrentinfo_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(torrentinfo_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(torrentinfo_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(torrentinfo_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(torrentinfo_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(torrentinfo_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(torrentinfo_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(torrentinfo_ENABLE_PCH "Enable precompiled headers" OFF)
    option(torrentinfo_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(torrentinfo_ENABLE_IPO "Enable IPO/LTO" ON)
    option(torrentinfo_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(torrentinfo_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(torrentinfo_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(torrentinfo_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(torrentinfo_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(torrentinfo_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(torrentinfo_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(torrentinfo_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(torrentinfo_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(torrentinfo_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(torrentinfo_ENABLE_PCH "Enable precompiled headers" OFF)
    option(torrentinfo_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      torrentinfo_ENABLE_IPO
      torrentinfo_WARNINGS_AS_ERRORS
      torrentinfo_ENABLE_USER_LINKER
      torrentinfo_ENABLE_SANITIZER_ADDRESS
      torrentinfo_ENABLE_SANITIZER_LEAK
      torrentinfo_ENABLE_SANITIZER_UNDEFINED
      torrentinfo_ENABLE_SANITIZER_THREAD
      torrentinfo_ENABLE_SANITIZER_MEMORY
      torrentinfo_ENABLE_UNITY_BUILD
      torrentinfo_ENABLE_CLANG_TIDY
      torrentinfo_ENABLE_CPPCHECK
      torrentinfo_ENABLE_COVERAGE
      torrentinfo_ENABLE_PCH
      torrentinfo_ENABLE_CACHE)
  endif()

  torrentinfo_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (torrentinfo_ENABLE_SANITIZER_ADDRESS OR torrentinfo_ENABLE_SANITIZER_THREAD OR torrentinfo_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(torrentinfo_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(torrentinfo_global_options)
  if(torrentinfo_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    torrentinfo_enable_ipo()
  endif()

  torrentinfo_supports_sanitizers()

  if(torrentinfo_ENABLE_HARDENING AND torrentinfo_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR torrentinfo_ENABLE_SANITIZER_UNDEFINED
       OR torrentinfo_ENABLE_SANITIZER_ADDRESS
       OR torrentinfo_ENABLE_SANITIZER_THREAD
       OR torrentinfo_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${torrentinfo_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${torrentinfo_ENABLE_SANITIZER_UNDEFINED}")
    torrentinfo_enable_hardening(torrentinfo_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(torrentinfo_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(torrentinfo_warnings INTERFACE)
  add_library(torrentinfo_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  torrentinfo_set_project_warnings(
    torrentinfo_warnings
    ${torrentinfo_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(torrentinfo_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    torrentinfo_configure_linker(torrentinfo_options)
  endif()

  include(cmake/Sanitizers.cmake)
  torrentinfo_enable_sanitizers(
    torrentinfo_options
    ${torrentinfo_ENABLE_SANITIZER_ADDRESS}
    ${torrentinfo_ENABLE_SANITIZER_LEAK}
    ${torrentinfo_ENABLE_SANITIZER_UNDEFINED}
    ${torrentinfo_ENABLE_SANITIZER_THREAD}
    ${torrentinfo_ENABLE_SANITIZER_MEMORY})

  set_target_properties(torrentinfo_options PROPERTIES UNITY_BUILD ${torrentinfo_ENABLE_UNITY_BUILD})

  if(torrentinfo_ENABLE_PCH)
    target_precompile_headers(
      torrentinfo_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(torrentinfo_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    torrentinfo_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(torrentinfo_ENABLE_CLANG_TIDY)
    torrentinfo_enable_clang_tidy(torrentinfo_options ${torrentinfo_WARNINGS_AS_ERRORS})
  endif()

  if(torrentinfo_ENABLE_CPPCHECK)
    torrentinfo_enable_cppcheck(${torrentinfo_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(torrentinfo_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    torrentinfo_enable_coverage(torrentinfo_options)
  endif()

  if(torrentinfo_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(torrentinfo_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(torrentinfo_ENABLE_HARDENING AND NOT torrentinfo_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR torrentinfo_ENABLE_SANITIZER_UNDEFINED
       OR torrentinfo_ENABLE_SANITIZER_ADDRESS
       OR torrentinfo_ENABLE_SANITIZER_THREAD
       OR torrentinfo_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    torrentinfo_enable_hardening(torrentinfo_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
