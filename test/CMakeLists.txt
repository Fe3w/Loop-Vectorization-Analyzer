# Generates build/test/lit.site.cfg.py with real paths, then `ninja check`
# runs every test under test/.
set(LOOPLENS_LLVM_TOOLS_DIR ${LLVM_TOOLS_BINARY_DIR})
set(LOOPLENS_PLUGIN_DIR ${CMAKE_BINARY_DIR}/lib)

configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in
  ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
  @ONLY
)

# lit: prefer the copy shipped with llvm-NN-tools, else `lit` on PATH (pipx).
find_program(LIT_COMMAND
  NAMES lit llvm-lit lit.py
  HINTS ${LLVM_TOOLS_BINARY_DIR}
        /usr/lib/llvm-${LOOPLENS_LLVM_VERSION}/build/utils/lit
)
if(NOT LIT_COMMAND)
  message(WARNING "lit not found: install llvm-${LOOPLENS_LLVM_VERSION}-tools or `pipx install lit`")
endif()

add_custom_target(check
  COMMAND ${LIT_COMMAND} -v ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS LoopLens
  COMMENT "Running LoopLens lit tests"
  USES_TERMINAL
)
