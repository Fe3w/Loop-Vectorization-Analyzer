# A MODULE library is loaded by `opt -load-pass-plugin`; opt already
# contains LLVM, so we do NOT link LLVM libraries into the plugin.
add_library(LoopLens MODULE
  Classifier.cpp
  JsonReport.cpp
  LoopLensAnalyze.cpp
  LoopRecord.cpp
  Remarks.cpp
  Repair.cpp
)

# Produce build/lib/LoopLens.so (no "lib" prefix), matching the lit tests.
set_target_properties(LoopLens PROPERTIES
  PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)
