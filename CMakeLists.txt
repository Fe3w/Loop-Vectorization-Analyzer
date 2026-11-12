cmake_minimum_required(VERSION 3.20)
project(LoopLens LANGUAGES CXX)

# LLVM 20 is pinned (see DECISIONS.md). Override only for experiments:
#   cmake -DLOOPLENS_LLVM_VERSION=21 ...
set(LOOPLENS_LLVM_VERSION 20 CACHE STRING "LLVM major version to build against")
set(LLVM_DIR "/usr/lib/llvm-${LOOPLENS_LLVM_VERSION}/lib/cmake/llvm" CACHE PATH "LLVMConfig.cmake dir")

# No version in find_package: LLVM's LLVMConfigVersion.cmake demands an exact
# major.minor match, so "20" (= 20.0) rejects 20.1.x. Check the major ourselves.
find_package(LLVM REQUIRED CONFIG)
if(NOT LLVM_VERSION_MAJOR EQUAL LOOPLENS_LLVM_VERSION)
  message(FATAL_ERROR "LoopLens needs LLVM ${LOOPLENS_LLVM_VERSION}.x, found ${LLVM_PACKAGE_VERSION} at ${LLVM_DIR}")
endif()
message(STATUS "LoopLens: using LLVM ${LLVM_PACKAGE_VERSION} from ${LLVM_DIR}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)   # for clangd / IDE

include_directories(SYSTEM ${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

# apt.llvm.org builds LLVM without RTTI; the plugin must match.
if(NOT LLVM_ENABLE_RTTI)
  add_compile_options(-fno-rtti)
endif()

add_subdirectory(lib)
add_subdirectory(test)
