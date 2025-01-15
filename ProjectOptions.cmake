include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(sqlite_cpp_supports_sanitizers)
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

macro(sqlite_cpp_setup_options)
  option(sqlite_cpp_ENABLE_HARDENING "Enable hardening" ON)
  option(sqlite_cpp_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    sqlite_cpp_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    sqlite_cpp_ENABLE_HARDENING
    OFF)

  sqlite_cpp_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR sqlite_cpp_PACKAGING_MAINTAINER_MODE)
    option(sqlite_cpp_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(sqlite_cpp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(sqlite_cpp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(sqlite_cpp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(sqlite_cpp_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(sqlite_cpp_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(sqlite_cpp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(sqlite_cpp_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(sqlite_cpp_ENABLE_IPO "Enable IPO/LTO" ON)
    option(sqlite_cpp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(sqlite_cpp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(sqlite_cpp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(sqlite_cpp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(sqlite_cpp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(sqlite_cpp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(sqlite_cpp_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(sqlite_cpp_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(sqlite_cpp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(sqlite_cpp_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      sqlite_cpp_ENABLE_IPO
      sqlite_cpp_WARNINGS_AS_ERRORS
      sqlite_cpp_ENABLE_USER_LINKER
      sqlite_cpp_ENABLE_SANITIZER_ADDRESS
      sqlite_cpp_ENABLE_SANITIZER_LEAK
      sqlite_cpp_ENABLE_SANITIZER_UNDEFINED
      sqlite_cpp_ENABLE_SANITIZER_THREAD
      sqlite_cpp_ENABLE_SANITIZER_MEMORY
      sqlite_cpp_ENABLE_UNITY_BUILD
      sqlite_cpp_ENABLE_CLANG_TIDY
      sqlite_cpp_ENABLE_CPPCHECK
      sqlite_cpp_ENABLE_COVERAGE
      sqlite_cpp_ENABLE_PCH
      sqlite_cpp_ENABLE_CACHE)
  endif()

  sqlite_cpp_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (sqlite_cpp_ENABLE_SANITIZER_ADDRESS OR sqlite_cpp_ENABLE_SANITIZER_THREAD OR sqlite_cpp_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(sqlite_cpp_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(sqlite_cpp_global_options)
  if(sqlite_cpp_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    sqlite_cpp_enable_ipo()
  endif()

  sqlite_cpp_supports_sanitizers()

  if(sqlite_cpp_ENABLE_HARDENING AND sqlite_cpp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR sqlite_cpp_ENABLE_SANITIZER_UNDEFINED
       OR sqlite_cpp_ENABLE_SANITIZER_ADDRESS
       OR sqlite_cpp_ENABLE_SANITIZER_THREAD
       OR sqlite_cpp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${sqlite_cpp_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${sqlite_cpp_ENABLE_SANITIZER_UNDEFINED}")
    sqlite_cpp_enable_hardening(sqlite_cpp_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(sqlite_cpp_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(sqlite_cpp_warnings INTERFACE)
  add_library(sqlite_cpp_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  sqlite_cpp_set_project_warnings(
    sqlite_cpp_warnings
    ${sqlite_cpp_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(sqlite_cpp_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    sqlite_cpp_configure_linker(sqlite_cpp_options)
  endif()

  include(cmake/Sanitizers.cmake)
  sqlite_cpp_enable_sanitizers(
    sqlite_cpp_options
    ${sqlite_cpp_ENABLE_SANITIZER_ADDRESS}
    ${sqlite_cpp_ENABLE_SANITIZER_LEAK}
    ${sqlite_cpp_ENABLE_SANITIZER_UNDEFINED}
    ${sqlite_cpp_ENABLE_SANITIZER_THREAD}
    ${sqlite_cpp_ENABLE_SANITIZER_MEMORY})

  set_target_properties(sqlite_cpp_options PROPERTIES UNITY_BUILD ${sqlite_cpp_ENABLE_UNITY_BUILD})

  if(sqlite_cpp_ENABLE_PCH)
    target_precompile_headers(
      sqlite_cpp_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(sqlite_cpp_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    sqlite_cpp_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(sqlite_cpp_ENABLE_CLANG_TIDY)
    sqlite_cpp_enable_clang_tidy(sqlite_cpp_options ${sqlite_cpp_WARNINGS_AS_ERRORS})
  endif()

  if(sqlite_cpp_ENABLE_CPPCHECK)
    sqlite_cpp_enable_cppcheck(${sqlite_cpp_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(sqlite_cpp_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    sqlite_cpp_enable_coverage(sqlite_cpp_options)
  endif()

  if(sqlite_cpp_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(sqlite_cpp_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(sqlite_cpp_ENABLE_HARDENING AND NOT sqlite_cpp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR sqlite_cpp_ENABLE_SANITIZER_UNDEFINED
       OR sqlite_cpp_ENABLE_SANITIZER_ADDRESS
       OR sqlite_cpp_ENABLE_SANITIZER_THREAD
       OR sqlite_cpp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    sqlite_cpp_enable_hardening(sqlite_cpp_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
